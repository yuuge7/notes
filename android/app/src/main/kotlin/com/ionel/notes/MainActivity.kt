package com.ionel.notes

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Hosts Flutter, and the system pickers an export is saved with and an import
 * is opened from.
 *
 * Both go through the Storage Access Framework, so the app holds no storage
 * permission: Android grants access to the one file the person picks. Files
 * are copied as streams on a background thread, so an export full of photos
 * never has to fit in memory or cross the channel as bytes.
 */
class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /** The call waiting for a picker to close, and for a save, the file to copy. */
    private var pending: MethodChannel.Result? = null
    private var pendingSource: File? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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

        // Clear of the codes the image picker plugin uses for its own results.
        const val SAVE = 41731
        const val OPEN = 41732
    }
}
