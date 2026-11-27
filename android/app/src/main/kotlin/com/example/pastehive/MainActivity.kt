package com.example.pastehive

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The app's one screen, plus the few things the Dart side asks Android for:
 * the phone's name, the keep-alive notification, and text handed over from
 * other apps.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    /** Text shared to the app before the Dart side was ready to take it. */
    private var pendingText: String? = null

    /** Lets the phone hear what other devices announce to the whole network. */
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "pastehive/phone",
        ).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "deviceName" -> result.success(deviceName())
                    "takeSharedText" -> {
                        result.success(pendingText)
                        pendingText = null
                    }
                    "startKeepAlive" -> {
                        startKeepAlive()
                        result.success(null)
                    }
                    "stopKeepAlive" -> {
                        stopKeepAlive()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingText = sharedTextOf(intent)
    }

    // The app was already running when something was shared to it.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val text = sharedTextOf(intent) ?: return
        val channel = channel
        if (channel == null) {
            pendingText = text
        } else {
            channel.invokeMethod("sharedText", text)
        }
    }

    override fun onDestroy() {
        releaseMulticastLock()
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

    private fun deviceName(): String {
        val model = Build.MODEL.orEmpty()
        val maker = Build.MANUFACTURER.orEmpty().replaceFirstChar { it.uppercase() }
        return when {
            model.isBlank() -> "Android phone"
            model.startsWith(maker, ignoreCase = true) -> model
            maker.isBlank() -> model
            else -> "$maker $model"
        }
    }

    private fun startKeepAlive() {
        // From Android 13 a notification needs the user's say-so. Without it
        // the service still runs; it is just not shown.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
        acquireMulticastLock()
        val service = Intent(this, KeepAliveService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(service)
        } else {
            startService(service)
        }
    }

    private fun stopKeepAlive() {
        stopService(Intent(this, KeepAliveService::class.java))
        releaseMulticastLock()
    }

    private fun acquireMulticastLock() {
        if (multicastLock?.isHeld == true) return
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        multicastLock = wifi?.createMulticastLock("pastehive-discovery")?.apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseMulticastLock() {
        multicastLock?.takeIf { it.isHeld }?.release()
        multicastLock = null
    }
}
