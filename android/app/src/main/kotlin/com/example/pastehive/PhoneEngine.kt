package com.example.pastehive

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.lang.ref.WeakReference
import java.nio.ByteBuffer

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

    /** Lets go of the window held for a clipboard read, once it is read. */
    private var releaseFocus: (() -> Unit)? = null

    /** The last copied picture that was converted, and which copy it was. */
    private var lastImageKey: String? = null
    private var lastImage: Map<String, Any>? = null

    private val main = Handler(Looper.getMainLooper())

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

    /**
     * Has the Dart side look at the clipboard now, text or picture, and
     * record and send what it finds.
     *
     * Android shows the clipboard only to an app whose window has focus, so
     * the caller holds a focused window until [whenRead] is called: that is
     * as soon as the clipboard itself has been read, before a picture has
     * been converted and sent.
     */
    fun capture(context: Context, onlyIfNew: Boolean, whenRead: () -> Unit) {
        ensure(context)
        if (!dartReady) {
            // Still starting: text can wait for it, a picture cannot.
            readClipboard(context.applicationContext)?.let { deliver(context, it, onlyIfNew) }
            whenRead()
            return
        }
        var released = false
        val release = {
            if (!released) {
                released = true
                if (releaseFocus != null) releaseFocus = null
                whenRead()
            }
        }
        releaseFocus = release
        main.postDelayed({ release() }, 4000)
        channel?.invokeMethod(
            "capture",
            null,
            object : MethodChannel.Result {
                override fun success(result: Any?) = release()
                override fun error(code: String, message: String?, details: Any?) = release()
                override fun notImplemented() = release()
            },
        )
    }

    /** Whether there is anything on the clipboard this app could send. */
    fun clipboardHasContent(app: Context): Boolean = try {
        val clipboard = app.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val item = clipboard.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)
        item != null && (!item.text.isNullOrBlank() || item.uri != null)
    } catch (e: Exception) {
        false
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
            "readClipboard" -> {
                val text = readClipboard(app)
                // With text found nothing more is read: the window that
                // was holding focus for this can go.
                if (!text.isNullOrBlank()) releaseFocus?.invoke()
                result.success(text)
            }
            "readClipboardImage" -> readClipboardImage(app, result)
            "writeClipboardImage" ->
                result.success(writeClipboardImage(app, call.arguments as? String))
            "writeClipboard" -> {
                writeClipboard(app, call.arguments as? String ?: "")
                result.success(null)
            }
            "openUrl" -> {
                val url = call.arguments as? String
                // Only ever a web address.
                if (url != null && url.startsWith("https://")) {
                    open(app, Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                }
                result.success(null)
            }
            "installApk" -> result.success(installApk(app, call.arguments as? String))
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

    /**
     * The text on the clipboard; null when there is none or Android will not
     * show it. A copied picture is not text: its address is left alone.
     */
    fun readClipboard(app: Context): String? = try {
        val clipboard = app.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val item = clipboard.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)
        when {
            item == null -> null
            item.text != null -> item.text.toString()
            item.uri != null -> null
            else -> item.coerceToText(app)?.toString()
        }
    } catch (e: Exception) {
        null
    }

    /**
     * The picture on the clipboard, as a PNG with its size; null when there
     * is none. On Android a copied picture is an address another app hands
     * out; its bytes are fetched while this app may still read them, and
     * turning them into a PNG, which takes a moment, happens off the main
     * thread.
     */
    private fun readClipboardImage(app: Context, result: MethodChannel.Result) {
        val raw: ByteArray?
        val key: String
        try {
            val clipboard = app.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clip = clipboard.primaryClip
            val uri = clip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri
            val isPicture = uri != null && (
                clip.description.hasMimeType("image/*") ||
                    app.contentResolver.getType(uri)?.startsWith("image/") == true
                )
            // A picture this app put there itself is not a new copy.
            if (!isPicture || uri!!.authority == filesAuthority(app)) {
                releaseFocus?.invoke()
                result.success(null)
                return
            }
            val stamp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                clip.description.timestamp
            } else {
                0L
            }
            key = "$uri@$stamp"
            // Asked again about the same copy (the app looks each time it
            // comes to the front): the answer is already known.
            if (key == lastImageKey) {
                releaseFocus?.invoke()
                result.success(lastImage)
                return
            }
            raw = app.contentResolver.openInputStream(uri)?.use { it.readBytes() }
        } catch (e: Exception) {
            Log.w(TAG, "the copied picture could not be read", e)
            releaseFocus?.invoke()
            result.success(null)
            return
        }
        releaseFocus?.invoke()
        if (raw == null) {
            result.success(null)
            return
        }
        Thread {
            val image = try {
                encodePicture(raw)
            } catch (e: Throwable) {
                // Too large to hold in memory, or not a picture after all.
                Log.w(TAG, "the copied picture could not be converted", e)
                null
            }
            main.post {
                lastImageKey = key
                lastImage = image
                Log.i(TAG, "read a picture: ${image?.get("width")} x ${image?.get("height")}")
                result.success(image)
            }
        }.start()
    }

    // Other devices take pictures as PNG, of at most 5 MB. A photo is far
    // larger than that as a PNG, so it is made smaller until it fits.
    private fun encodePicture(raw: ByteArray): Map<String, Any>? {
        var bitmap = decodePicture(raw) ?: return null
        var longest = 2048
        while (true) {
            val scale = longest.toFloat() / maxOf(bitmap.width, bitmap.height)
            if (scale < 1f) {
                val smaller = Bitmap.createScaledBitmap(
                    bitmap,
                    maxOf(1, (bitmap.width * scale).toInt()),
                    maxOf(1, (bitmap.height * scale).toInt()),
                    true,
                )
                if (smaller !== bitmap) bitmap.recycle()
                bitmap = smaller
            }
            val out = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            if (out.size() <= 4_500_000 || longest <= 480) {
                val image = mapOf(
                    "png" to out.toByteArray(),
                    "width" to bitmap.width,
                    "height" to bitmap.height,
                )
                bitmap.recycle()
                return image
            }
            longest = longest * 3 / 4
        }
    }

    private fun decodePicture(raw: ByteArray): Bitmap? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            // Turns a photo the right way up, which the older way does not.
            return ImageDecoder.decodeBitmap(
                ImageDecoder.createSource(ByteBuffer.wrap(raw)),
            ) { decoder, info, _ ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                val longest = maxOf(info.size.width, info.size.height)
                var sample = 1
                while (longest / sample > 4096) sample *= 2
                decoder.setTargetSampleSize(sample)
            }
        }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(raw, 0, raw.size, bounds)
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 4096) sample *= 2
        return BitmapFactory.decodeByteArray(
            raw,
            0,
            raw.size,
            BitmapFactory.Options().apply { inSampleSize = sample },
        )
    }

    /**
     * Puts a stored picture on the clipboard. Android's clipboard holds a
     * picture as an address; whichever app pastes it is let read that one
     * file.
     */
    private fun writeClipboardImage(app: Context, path: String?): Boolean {
        if (path == null) return false
        return try {
            val file = File(path)
            // Only the app's own stored pictures.
            if (!file.canonicalPath.startsWith(app.filesDir.canonicalPath)) return false
            val uri = FileProvider.getUriForFile(app, filesAuthority(app), file)
            val clipboard = app.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            clipboard.setPrimaryClip(ClipData.newUri(app.contentResolver, "Picture", uri))
            lastWrite = SystemClock.elapsedRealtime()
            Log.i(TAG, "put a picture on the clipboard")
            true
        } catch (e: Exception) {
            Log.w(TAG, "the picture could not be put on the clipboard", e)
            false
        }
    }

    private fun filesAuthority(app: Context) = "${app.packageName}.files"

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

    /**
     * Hands a downloaded update to Android's installer, which shows the
     * user what is about to be installed and asks them to confirm. The
     * first time, Android first asks them to let this app install apps.
     */
    private fun installApk(app: Context, path: String?): Boolean {
        if (path == null) return false
        return try {
            val file = File(path)
            // Only a file this app downloaded itself, into its own cache.
            if (!file.canonicalPath.startsWith(app.cacheDir.canonicalPath)) return false
            val uri = FileProvider.getUriForFile(app, filesAuthority(app), file)
            app.startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION,
                    ),
            )
            true
        } catch (e: Exception) {
            Log.w(TAG, "the update could not be handed to the installer", e)
            false
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
