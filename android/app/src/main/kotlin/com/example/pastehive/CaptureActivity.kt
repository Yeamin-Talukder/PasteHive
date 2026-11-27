package com.example.pastehive

import android.app.Activity
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.Toast

/**
 * Reads the clipboard and hands it to the app, then goes away.
 *
 * Android lets an app read the clipboard only while one of its windows has
 * the user's attention, so a background service cannot do it. This activity
 * is invisible and exists for the instant that takes: it is what the
 * notification's "Send clipboard" button and the quick-settings tile open.
 */
class CaptureActivity : Activity() {
    private var done = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Nothing to draw.
        overridePendingTransition(0, 0)
    }

    // The clipboard can be read once the window has focus, not before.
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || done) return
        done = true
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val text = clipboard.primaryClip
            ?.takeIf { it.itemCount > 0 }
            ?.getItemAt(0)
            ?.coerceToText(this)
            ?.toString()
        if (text.isNullOrBlank()) {
            Toast.makeText(this, "Nothing on the clipboard to send", Toast.LENGTH_SHORT).show()
        } else {
            deliver(text)
            Toast.makeText(this, "Sent to your devices", Toast.LENGTH_SHORT).show()
        }
        finish()
        overridePendingTransition(0, 0)
    }

    private fun deliver(text: String) {
        val channel = MainActivity.channel
        if (channel != null) {
            // The app is alive in the background: tell it directly.
            channel.invokeMethod("sharedText", text)
        } else {
            // It is not running: start it with the text, as Share would.
            startActivity(
                Intent(this, MainActivity::class.java)
                    .setAction(Intent.ACTION_SEND)
                    .setType("text/plain")
                    .putExtra(Intent.EXTRA_TEXT, text)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }
}
