package com.example.pastehive

import android.accessibilityservice.AccessibilityService
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent

/**
 * Notices when the user copies something in any app, and has the clipboard
 * sent to the other devices without their doing anything more.
 *
 * Android does not tell apps when the clipboard changes and does not let
 * them read it from the background. What an accessibility service can see
 * are two signs of a copy: a tap on a button labelled with the system's own
 * word for Copy or Cut, and the small "copied" preview Android shows in the
 * corner afterwards. On either, it reads the clipboard through a window of
 * one transparent pixel (see [readClipboard]) and hands the text on.
 *
 * It looks at nothing else: only the label of what was tapped and the name
 * of the window that appeared. It is off until the user switches it on in
 * Android's accessibility settings.
 *
 * While it is on, Android keeps the app's process alive, so this also keeps
 * sync running with the app's screen closed.
 */
class CopyWatcherService : AccessibilityService() {
    private val handler = Handler(Looper.getMainLooper())
    private var lastCapture = 0L

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.i(PhoneEngine.TAG, "copy watcher: on")
        // Sync should be running whenever the watcher is, screen or no screen.
        PhoneEngine.ensure(this)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event ?: return
        // What happens inside this app is its own business.
        if (event.packageName == packageName) return
        val sign = when (event.eventType) {
            AccessibilityEvent.TYPE_VIEW_CLICKED ->
                if (isCopyOrCut(event)) "tap" else null
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED ->
                if (isCopiedPreview(event)) "preview" else null
            else -> null
        } ?: return

        // Text that arrived from another device and was put on the clipboard
        // by this app shows the same preview.
        if (PhoneEngine.wroteJustNow()) return

        // One copy shows more than one sign; and the copy itself needs a
        // moment to reach the clipboard before it is read.
        val now = System.currentTimeMillis()
        if (now - lastCapture < 700) return
        lastCapture = now
        Log.i(PhoneEngine.TAG, "copy watcher: copy noticed ($sign) in ${event.packageName}")
        handler.postDelayed({ readClipboard() }, 250)
    }

    /**
     * Reads the clipboard through a window of one transparent pixel.
     *
     * Android shows the clipboard only to the app whose window has focus. A
     * service like this one may put a window of its own over whatever is on
     * screen; for the instant that window has focus, the clipboard can be
     * read. Nothing is drawn and no screen is opened, so nothing moves: the
     * app underneath stays where it is, keyboard included.
     */
    private fun readClipboard() {
        val windows = getSystemService(WINDOW_SERVICE) as WindowManager
        var removed = false
        lateinit var probe: View
        fun remove() {
            if (removed) return
            removed = true
            // Not from inside the window's own focus report: Android is
            // still using the window at that point and crashes without it.
            handler.post {
                try {
                    windows.removeView(probe)
                } catch (e: Exception) {
                    // Already gone.
                }
            }
        }
        var asked = false
        probe = object : View(this) {
            override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
                super.onWindowFocusChanged(hasWindowFocus)
                if (!hasWindowFocus || asked) return
                asked = true
                Log.i(PhoneEngine.TAG, "copy watcher: reading the clipboard")
                PhoneEngine.capture(this@CopyWatcherService, onlyIfNew = true) { remove() }
            }
        }
        val params = WindowManager.LayoutParams(
            1,
            1,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            // Able to take focus, but not the keyboard's: the keyboard stays
            // with the app underneath. Touches pass through.
            WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            windowAnimations = 0
            title = "PasteHive"
        }
        try {
            windows.addView(probe, params)
        } catch (e: Exception) {
            Log.w(PhoneEngine.TAG, "copy watcher: could not look at the clipboard", e)
            return
        }
        // Never linger: if focus is not given, give up.
        handler.postDelayed({ if (!asked) remove() }, 1500)
    }

    override fun onInterrupt() {}

    private fun isCopyOrCut(event: AccessibilityEvent): Boolean {
        // The system's own labels, in whatever language the phone is set to.
        val labels = listOf(
            getString(android.R.string.copy),
            getString(android.R.string.cut),
        )
        val shown = buildList {
            event.text?.forEach { add(it?.toString()) }
            add(event.contentDescription?.toString())
        }
        return shown.any { text ->
            val label = text?.trim() ?: return@any false
            // "Copy", and an app's own "Copy link", "Copy text" and the like.
            labels.any {
                label.equals(it, ignoreCase = true) ||
                    label.startsWith("$it ", ignoreCase = true)
            }
        }
    }

    // The preview Android itself shows after any copy, however it was made.
    // It is the one system window reported as a bare frame: the volume panel
    // and the other system dialogs report a class of their own, and the
    // notification shade reports nothing. (Seen on Android 17; a tap on the
    // Copy button of the text-selection menu is not reported at all there.)
    // Should some other system window match, the cost is one needless look
    // at the clipboard, which sends nothing when the text has not changed.
    private fun isCopiedPreview(event: AccessibilityEvent): Boolean {
        if (event.packageName != "com.android.systemui") return false
        val window = event.className?.toString().orEmpty()
        return window == "android.widget.FrameLayout" ||
            window.contains("clipboard", ignoreCase = true)
    }
}
