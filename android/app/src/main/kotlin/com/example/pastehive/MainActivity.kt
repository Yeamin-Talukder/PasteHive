package com.example.pastehive

import android.content.Context
import android.content.Intent
import android.net.Uri
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
        takeShared(intent)
    }

    // The app was already open when something was shared to it.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        takeShared(intent)
    }

    // Files shared to the app go to the other devices as files; anything
    // else that was shared is text.
    private fun takeShared(intent: Intent?) {
        val files = sharedFilesOf(intent)
        if (files.isNotEmpty()) {
            PhoneEngine.deliverFiles(this, files)
        } else {
            sharedTextOf(intent)?.let { PhoneEngine.deliver(this, it) }
        }
    }

    @Suppress("DEPRECATION")
    private fun sharedFilesOf(intent: Intent?): List<Uri> = when (intent?.action) {
        Intent.ACTION_SEND ->
            listOfNotNull(intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
        Intent.ACTION_SEND_MULTIPLE ->
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM).orEmpty()
        else -> emptyList()
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
