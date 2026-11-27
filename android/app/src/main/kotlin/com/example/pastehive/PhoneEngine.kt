package com.example.pastehive

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/**
 * The app's Dart side, kept running apart from its screen.
 *
 * The history and the connections to the other devices live in Dart. If they
 * belonged to the screen they would stop whenever the screen was closed, and
 * a copy noticed afterwards would have nowhere to go. So the engine is made
 * once per process, by whichever part needs it first (the screen, the copy
 * watcher, or the capture activity), and the screen merely attaches to it.
 *
 * Everything here is used from the main thread.
 */
object PhoneEngine {
    const val TAG = "PasteHive"
    private const val ID = "pastehive"

    private var channel: MethodChannel? = null

    /** Whether the Dart side has said it is listening. */
    private var dartReady = false

    /** Text that arrived before the Dart side was ready to take it. */
    private val pending = ArrayList<String>()

    /** What was last handed over, so the same copy is not sent twice. */
    private var lastText: String? = null

    /** When this app last put something on the clipboard itself. */
    private var lastWrite = 0L

    /**
     * Whether the clipboard was just written by this app: Android shows its
     * copied preview for that too, and it is not a copy to look at.
     */
    fun wroteJustNow(): Boolean =
        lastWrite != 0L && SystemClock.elapsedRealtime() - lastWrite < 2000

    /** Lets the phone hear what other devices announce to the whole network. */
    private var multicastLock: WifiManager.MulticastLock? = null

    /** The screen, while there is one; asking for a permission needs it. */
    var screen: WeakReference<MainActivity>? = null

    /** The running engine, started now if this is the first call. */
    fun ensure(context: Context): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        cache.get(ID)?.let { return it }
        val app = context.applicationContext
        Log.i(TAG, "starting the engine")
        val engine = FlutterEngine(app)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "pastehive/phone").also {
            it.setMethodCallHandler { call, result -> handle(app, call, result) }
        }
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        cache.put(ID, engine)
        return engine
    }

    /**
     * Hands copied or shared text to the Dart side, starting it if need be.
     *
     * With [onlyIfNew], text equal to the last one handed over is dropped:
     * a copy can be noticed more than once.
     */
    fun deliver(context: Context, text: String, onlyIfNew: Boolean = false): Boolean {
        if (text.isBlank()) return false
        if (onlyIfNew && text == lastText) {
            Log.i(TAG, "same text as last time, not sent again")
            return false
        }
        lastText = text
        ensure(context)
        if (dartReady) {
            Log.i(TAG, "handing over ${text.length} characters")
            channel?.invokeMethod("sharedText", text)
        } else {
            Log.i(TAG, "holding ${text.length} characters until the app is ready")
            pending.add(text)
        }
        return true
    }

    /** Whether the user has switched the copy watcher on in Android's settings. */
    fun autoCopyOn(context: Context): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ).orEmpty()
        val mine = ComponentName(context, CopyWatcherService::class.java)
        return enabled.split(':').any { ComponentName.unflattenFromString(it) == mine }
    }

    private fun handle(app: Context, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "deviceName" -> result.success(deviceName())
            // Also how the Dart side says it is ready: from here on, text is
            // passed straight to it.
            "takeSharedTexts" -> {
                dartReady = true
                result.success(ArrayList(pending))
                pending.clear()
            }
            // The clipboard is read and written here and not through Flutter's
            // own channel, which answers only while there is a screen: without
            // one a call to it never returns.
            "readClipboard" -> result.success(readClipboard(app))
            "writeClipboard" -> {
                writeClipboard(app, call.arguments as? String ?: "")
                result.success(null)
            }
            "autoCopyOn" -> result.success(autoCopyOn(app))
            "openAutoCopySettings" -> {
                open(app, Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                result.success(null)
            }
            "openAppInfo" -> {
                open(
                    app,
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", app.packageName, null),
                    ),
                )
                result.success(null)
            }
            "startKeepAlive" -> {
                startKeepAlive(app)
                result.success(null)
            }
            "stopKeepAlive" -> {
                app.stopService(Intent(app, KeepAliveService::class.java))
                releaseMulticastLock()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** The text on the clipboard; null when Android will not show it. */
    fun readClipboard(app: Context): String? = try {
        val clipboard = app.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.primaryClip
            ?.takeIf { it.itemCount > 0 }
            ?.getItemAt(0)
            ?.coerceToText(app)
            ?.toString()
    } catch (e: Exception) {
        null
    }

    private fun writeClipboard(app: Context, text: String) {
        try {
            val clipboard = app.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            clipboard.setPrimaryClip(ClipData.newPlainText("PasteHive", text))
            // What this app put there is not a copy to send back.
            lastText = text
            lastWrite = SystemClock.elapsedRealtime()
        } catch (e: Exception) {
            Log.w(TAG, "the clipboard could not be written", e)
        }
    }

    private fun open(app: Context, intent: Intent) {
        try {
            app.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: Exception) {
            Log.w(TAG, "could not open ${intent.action}", e)
        }
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

    private fun startKeepAlive(app: Context) {
        // From Android 13 a notification needs the user's say-so, which only
        // a screen can ask for. Without it the service still runs; it is
        // just not shown.
        val screen = screen?.get()
        if (screen != null &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            screen.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            screen.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
        acquireMulticastLock(app)
        val service = Intent(app, KeepAliveService::class.java)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                app.startForegroundService(service)
            } else {
                app.startService(service)
            }
        } catch (e: Exception) {
            // Android refuses this when nothing of the app is on screen; the
            // notification then appears the next time the app is opened.
            Log.w(TAG, "the keep-alive notification could not be shown yet", e)
        }
    }

    private fun acquireMulticastLock(app: Context) {
        if (multicastLock?.isHeld == true) return
        val wifi = app.getSystemService(Context.WIFI_SERVICE) as? WifiManager
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
