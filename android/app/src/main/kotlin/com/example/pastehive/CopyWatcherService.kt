package com.example.pastehive

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent

/**
 * Notices when the user copies something in any app, and has the clipboard
 * sent to the other devices without their doing anything more.
 *
 * Android does not tell apps when the clipboard changes and does not let
 * them read it from the background. What an accessibility service can see
 * are two signs of a copy: a tap on a button labelled with the system's own
 * word for Copy or Cut, and the small "copied" preview Android shows in the
 * corner afterwards. On either, this opens the invisible capture activity,
 * which may read the clipboard for the instant it is in front.
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
        handler.postDelayed({
            try {
                startActivity(
                    Intent(this, CaptureActivity::class.java)
                        .putExtra(CaptureActivity.EXTRA_QUIET, true)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION),
                )
            } catch (e: Exception) {
                Log.w(PhoneEngine.TAG, "copy watcher: could not open the capture", e)
            }
        }, 250)
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
