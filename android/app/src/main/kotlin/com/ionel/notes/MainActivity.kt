package com.ionel.notes

import android.app.Activity
import android.app.UiModeManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import com.ionel.notes.widgets.HomeWidgetsChannel
import com.ionel.notes.widgets.WidgetLaunch
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Hosts Flutter, the system pickers an export is saved with and an import is
 * opened from, and the few settings of the phone the app reaches into.
 *
 * Both go through the Storage Access Framework, so the app holds no storage
 * permission: Android grants access to the one file the person picks. Files
 * are copied as streams on a background thread, so an export full of photos
 * never has to fit in memory or cross the channel as bytes.
 *
 * Taps on the home screen widgets arrive here too, as the intent that starts
 * the activity or a new one while it runs.
 */
class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /** The call waiting for a picker to close, and for a save, the file to copy. */
    private var pending: MethodChannel.Result? = null
    private var pendingSource: File? = null

    private var widgets: HomeWidgetsChannel? = null

    /** Whether Android rebuilt this activity, whose intent was already acted on. */
    private var restored = false

    override fun onCreate(savedInstanceState: Bundle?) {
        restored = savedInstanceState != null
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        WidgetLaunch.read(intent)?.let { widgets?.deliver(it) }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        widgets = HomeWidgetsChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger).apply {
            launchedWith(if (restored) null else WidgetLaunch.read(intent))
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (pending != null) {
                    result.error("busy", "A picker is already open", null)
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "save" -> {
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType(call.argument<String>("mimeType"))
                            .putExtra(Intent.EXTRA_TITLE, call.argument<String>("name"))
                        launch(intent, SAVE, result, File(call.argument<String>("path")!!))
                    }
                    "open" -> {
                        // Some providers call a zip octet-stream, so the
                        // caller lists every type an export may arrive as.
                        val types = call.argument<List<String>>("mimeTypes").orEmpty()
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType("*/*")
                            .putExtra(Intent.EXTRA_MIME_TYPES, types.toTypedArray())
                        launch(intent, OPEN, result, null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setNightMode" -> {
                        setNightMode(call.argument<String>("mode"))
                        result.success(null)
                    }
                    "manufacturer" -> result.success(Build.MANUFACTURER.orEmpty())
                    "openBackgroundSettings" -> result.success(openBackgroundSettings())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Holds the theme chosen in the app as the app's own night mode. Android 12
     * and later draw the launch screen before any Dart runs, from this mode, so
     * a dark choice starts dark even on a light phone. Earlier versions have no
     * such setting, and their launch screen follows the phone.
     */
    private fun setNightMode(mode: String?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val nightMode = when (mode) {
            "light" -> UiModeManager.MODE_NIGHT_NO
            "dark" -> UiModeManager.MODE_NIGHT_YES
            else -> UiModeManager.MODE_NIGHT_AUTO
        }
        getSystemService(UiModeManager::class.java)?.setApplicationNightMode(nightMode)
    }

    /**
     * Opens the page where this phone's maker lets an app run in the
     * background, so reminders ring with the app closed. Makers move these
     * pages between versions, so each known place is tried in turn, and the
     * app's own settings page is the last resort. Returns whether any opened.
     */
    private fun openBackgroundSettings(): Boolean {
        val candidates = OEM_BACKGROUND_PAGES.map { (pkg, cls) ->
            Intent().setComponent(ComponentName(pkg, cls))
        } + Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", packageName, null),
        )
        for (intent in candidates) {
            try {
                startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (e: ActivityNotFoundException) {
                // Not on this phone; try the next.
            } catch (e: SecurityException) {
                // Present but closed to other apps; try the next.
            }
        }
        return false
    }

    /** Opens a picker, and answers the call at once if none can be opened. */
    private fun launch(intent: Intent, requestCode: Int, result: MethodChannel.Result, source: File?) {
        pending = result
        pendingSource = source
        try {
            startActivityForResult(intent, requestCode)
        } catch (e: ActivityNotFoundException) {
            pending = null
            pendingSource = null
            result.error("unavailable", e.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE && requestCode != OPEN) return
        val result = pending ?: return
        val source = pendingSource
        pending = null
        pendingSource = null

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(if (requestCode == SAVE) false else null)
            return
        }
        io.execute {
            try {
                if (requestCode == SAVE) {
                    // "wt" empties a file being written over, so a smaller
                    // export does not keep the tail of a larger one.
                    val output = contentResolver.openOutputStream(uri, "wt")
                        ?: error("The chosen place cannot be written to")
                    output.use { out -> source!!.inputStream().use { it.copyTo(out) } }
                    main.post { result.success(true) }
                } else {
                    // A readable copy of our own: the grant on the picked file
                    // may lapse, and the import reads it more than once.
                    val folder = File(cacheDir, "imports")
                    folder.deleteRecursively()
                    folder.mkdirs()
                    val copy = File(folder, "import.zip")
                    val input = contentResolver.openInputStream(uri)
                        ?: error("The chosen file cannot be read")
                    input.use { stream -> copy.outputStream().use { stream.copyTo(it) } }
                    main.post { result.success(copy.path) }
                }
            } catch (e: Exception) {
                main.post { result.error("io", e.message, null) }
            }
        }
    }

    private companion object {
        const val CHANNEL = "com.ionel.notes/documents"
        const val SYSTEM_CHANNEL = "com.ionel.notes/system"

        /** Where makers known to stop background apps keep the switch that lets one run. */
        val OEM_BACKGROUND_PAGES = listOf(
            "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
            "com.samsung.android.lool" to "com.samsung.android.sm.battery.ui.BatteryActivity",
            "com.samsung.android.lool" to "com.samsung.android.sm.ui.battery.BatteryActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.optimize.process.ProtectActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.oplus.safecenter" to "com.oplus.safecenter.permission.startup.StartupAppListActivity",
            "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager",
        )

        // Clear of the codes the image picker plugin uses for its own results.
        const val SAVE = 41731
        const val OPEN = 41732
    }
}
