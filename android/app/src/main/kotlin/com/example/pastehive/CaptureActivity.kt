package com.example.pastehive

import android.app.Activity
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.Toast

/**
 * Reads the clipboard and hands it to the app, then goes away.
 *
 * Android lets an app read the clipboard only while one of its windows has
 * the user's attention, so a background service cannot do it. This activity
 * is invisible and exists for the instant that takes: it is what the
 * notification's "Send clipboard" button, the quick-settings tile and the
 * copy watcher open.
 */
class CaptureActivity : Activity() {
    companion object {
        /**
         * Set when nobody asked for this capture by hand (a copy was noticed):
         * then it says nothing, and sends nothing it has already sent.
         */
        const val EXTRA_QUIET = "quiet"
    }

    private val handler = Handler(Looper.getMainLooper())
    private var done = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Nothing to draw.
        overridePendingTransition(0, 0)
        // Never linger: if the window is not given focus, give up.
        handler.postDelayed({
            if (!done) {
                Log.w(PhoneEngine.TAG, "capture: no focus, gave up")
                done = true
                finish()
            }
        }, 2000)
    }

    // The clipboard can be read once the window has focus, not before.
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || done) return
        done = true
        val quiet = intent?.getBooleanExtra(EXTRA_QUIET, false) == true
        val text = try {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            clipboard.primaryClip
                ?.takeIf { it.itemCount > 0 }
                ?.getItemAt(0)
                ?.coerceToText(this)
                ?.toString()
        } catch (e: Exception) {
            Log.w(PhoneEngine.TAG, "capture: the clipboard could not be read", e)
            null
        }
        Log.i(PhoneEngine.TAG, "capture: read ${text?.length ?: 0} characters, quiet=$quiet")
        if (text.isNullOrBlank()) {
            if (!quiet) {
                Toast.makeText(this, "Nothing on the clipboard to send", Toast.LENGTH_SHORT).show()
            }
        } else {
            PhoneEngine.deliver(this, text, onlyIfNew = quiet)
            if (!quiet) {
                Toast.makeText(this, "Sent to your devices", Toast.LENGTH_SHORT).show()
            }
        }
        finish()
        overridePendingTransition(0, 0)
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}
