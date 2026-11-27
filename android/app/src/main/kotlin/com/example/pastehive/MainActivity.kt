package com.example.pastehive

import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import java.lang.ref.WeakReference

/**
 * The app's one screen. It shows the Dart side, which runs apart from it (see
 * [PhoneEngine]), and takes in text handed over from other apps.
 */
class MainActivity : FlutterActivity() {
    // The shared engine: closing this screen does not stop sync.
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        PhoneEngine.ensure(context)

    override fun onCreate(savedInstanceState: Bundle?) {
        PhoneEngine.screen = WeakReference(this)
        super.onCreate(savedInstanceState)
        sharedTextOf(intent)?.let { PhoneEngine.deliver(this, it) }
    }

    // The app was already open when something was shared to it.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        sharedTextOf(intent)?.let { PhoneEngine.deliver(this, it) }
    }

    override fun onDestroy() {
        if (PhoneEngine.screen?.get() === this) PhoneEngine.screen = null
        super.onDestroy()
    }

    private fun sharedTextOf(intent: Intent?): String? {
        val text = when (intent?.action) {
            Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)
            Intent.ACTION_PROCESS_TEXT ->
                intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
            else -> null
        }
        return text?.takeIf { it.isNotBlank() }
    }
}
