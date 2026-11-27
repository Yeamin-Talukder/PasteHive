package com.example.pastehive

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent

/**
 * Notices when the user taps Copy or Cut in any app, and has the clipboard
 * sent to the other devices without their doing anything more.
 *
 * Android does not tell apps when the clipboard changes and does not let
 * them read it from the background. What an accessibility service can see is
 * the tap itself: the button in the menu over selected text is labelled with
 * the system's own words for Copy and Cut. When one is tapped, this opens
 * the invisible capture activity, which may read the clipboard for the
 * instant it is in front.
 *
 * It looks at nothing else: only the label of the thing that was tapped. It
 * is off until the user switches it on in Android's accessibility settings.
 * Copies made some other way (a keyboard's own clipboard, an app's custom
 * button with a different label) are not noticed.
 */
class CopyWatcherService : AccessibilityService() {
    private val handler = Handler(Looper.getMainLooper())
    private var lastCapture = 0L

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_VIEW_CLICKED) return
        // Taps inside this app are its own business.
        if (event.packageName == packageName) return
        if (!isCopyOrCut(event)) return

        // One tap can be reported twice; and the copy itself needs a moment
        // to reach the clipboard before it is read.
        val now = System.currentTimeMillis()
        if (now - lastCapture < 700) return
        lastCapture = now
        handler.postDelayed({
            startActivity(
                Intent(this, CaptureActivity::class.java)
                    .putExtra(CaptureActivity.EXTRA_QUIET, true)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
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
            text != null && labels.any { it.equals(text.trim(), ignoreCase = true) }
        }
    }
}
