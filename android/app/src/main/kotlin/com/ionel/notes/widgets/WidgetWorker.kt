package com.ionel.notes.widgets

import android.content.BroadcastReceiver
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * The app's own Dart, run with no screen, for what a note widget asks of the
 * notes: an item ticked off, or a note just chosen that the snapshot does not
 * carry yet. See widget_worker.dart.
 *
 * Started the first time it is needed and kept for the life of the process,
 * as the notifications plugin keeps its own for Done and Snooze: the database
 * may be served from its isolates to the app's, so it is never shut down under
 * them. Everything here runs on the main thread.
 */
object WidgetWorker {
    private const val TAG = "WidgetWorker"
    private const val CHANNEL = "com.ionel.notes/widget_worker"

    /** Past this, whoever waits is let go: a receiver has ten seconds in all. */
    private const val TIMEOUT_MS = 8_000L

    private val main = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var ready = false

    /** Asked for before the Dart side was listening, in order. */
    private val waiting = mutableListOf<Job>()

    private class Job(val method: String, val arguments: Any?, val done: () -> Unit)

    /** Ticks item [itemId] of note [noteId] off, or back on. [done] runs once it is written and the widgets redrawn. */
    fun setChecked(context: Context, noteId: String, itemId: String, checked: Boolean, done: () -> Unit) {
        run(
            context,
            Job("setChecked", mapOf("noteId" to noteId, "itemId" to itemId, "checked" to checked), once(done)),
        )
    }

    /** Hands the widgets a fresh snapshot, for the notes the note widgets show now. */
    fun refresh(context: Context, done: () -> Unit = {}) {
        run(context, Job("refresh", null, once(done)))
    }

    /**
     * After an update to the app, a snapshot in the old shape reads as none,
     * and the widgets would wait for the app to be opened. Called as they
     * update, which Android asks of them after every app update: the worker
     * writes one in the new shape, keeping [receiver] alive until it has.
     */
    fun healIfStale(receiver: BroadcastReceiver, context: Context) {
        if (!WidgetSnapshot.stale(context)) return
        val pending = receiver.goAsync()
        refresh(context) { pending.finish() }
    }

    private fun run(context: Context, job: Job) {
        try {
            start(context.applicationContext)
        } catch (e: Exception) {
            Log.e(TAG, "The widget worker could not start", e)
            job.done()
            return
        }
        if (ready) send(job) else waiting += job
    }

    private fun start(context: Context) {
        if (engine != null) return
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(context)
        loader.ensureInitializationComplete(context, null)
        // Plugins register themselves, as in the app: the database needs
        // path_provider to find its file. The widgets' channel lets the Dart
        // side hand over snapshots as the app does.
        val engine = FlutterEngine(context)
        HomeWidgetsChannel(context, engine.dartExecutor.binaryMessenger)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                if (call.method != "ready") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                ready = true
                result.success(null)
                val jobs = waiting.toList()
                waiting.clear()
                jobs.forEach(::send)
            }
        }
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                "package:notes/data/home_widgets/widget_worker.dart",
                "widgetWorker",
            ),
        )
        this.engine = engine
    }

    private fun send(job: Job) {
        val channel = channel ?: return job.done()
        channel.invokeMethod(
            job.method,
            job.arguments,
            object : MethodChannel.Result {
                override fun success(result: Any?) = job.done()

                override fun error(code: String, message: String?, details: Any?) {
                    Log.e(TAG, "${job.method} failed: $message")
                    job.done()
                }

                override fun notImplemented() {
                    Log.e(TAG, "${job.method} is not known to the worker")
                    job.done()
                }
            },
        )
    }

    /** [done] at most once: when the work is, or at the timeout, whichever comes first. */
    private fun once(done: () -> Unit): () -> Unit {
        var called = false
        val call = {
            if (!called) {
                called = true
                done()
            }
        }
        main.postDelayed({ call() }, TIMEOUT_MS)
        return call
    }
}
