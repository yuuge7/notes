package com.ionel.notes.widgets

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * The app's side of the home screen widgets: the snapshot the app hands over,
 * widget taps handed back, placing a widget from settings or a note, and the
 * notes the note widgets show.
 *
 * The app's engine has one, and so does WidgetWorker's, which hands over
 * snapshots the same way; only the [app]'s is told when a note widget
 * changes.
 */
class HomeWidgetsChannel(
    private val context: Context,
    messenger: BinaryMessenger,
    private val app: Boolean = false,
) {
    private val channel = MethodChannel(messenger, CHANNEL)
    private val main = Handler(Looper.getMainLooper())

    /** A widget tap the app has not taken yet: the one that started it, or one that came before it listened. */
    private var pending: Map<String, String>? = null

    init {
        if (app) running = this
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "publish" -> {
                    val snapshot = call.argument<String>("snapshot")
                    if (snapshot == null) {
                        result.error("snapshot", "No snapshot", null)
                        return@setMethodCallHandler
                    }
                    // Drawn off the main thread, which Flutter shares; from
                    // Android 12 each widget's cards are built with it. One
                    // thread for both engines, so two snapshots never write
                    // over each other half way.
                    io.execute {
                        try {
                            WidgetSnapshot.write(context, snapshot)
                            NotesWidget.refresh(context)
                            NoteWidget.refresh(context)
                            main.post { result.success(null) }
                        } catch (e: Exception) {
                            main.post { result.error("io", e.message, null) }
                        }
                    }
                }
                "takeAction" -> {
                    result.success(pending)
                    pending = null
                }
                "canPin" -> result.success(
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        AppWidgetManager.getInstance(context).isRequestPinAppWidgetSupported,
                )
                "shownNotes" -> result.success(WidgetNotes.shown(context))
                "pin" -> {
                    val feed = call.argument<String>("feed") ?: WidgetFeeds.ALL
                    val noteId = call.argument<String>("noteId")
                    val (provider, placed) = when (call.argument<String>("widget")) {
                        "notes" -> NotesWidget::class.java to NotesWidget.placed(context, feed)
                        // Without a note the widget asks for one itself.
                        "note" -> NoteWidget::class.java to noteId?.let { NoteWidget.placed(context, it) }
                        "capture" -> CaptureWidget::class.java to null
                        else -> {
                            result.error("widget", "Unknown widget", null)
                            return@setMethodCallHandler
                        }
                    }
                    result.success(
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            AppWidgetManager.getInstance(context)
                                .requestPinAppWidget(ComponentName(context, provider), null, placed),
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    /** The widget tap that started the app, for the app to take once it runs. */
    fun launchedWith(action: Map<String, String>?) {
        pending = action
    }

    /** A widget tap while the app runs. Kept for later if the app is not listening yet. */
    fun deliver(action: Map<String, String>) {
        channel.invokeMethod(
            "action",
            action,
            object : MethodChannel.Result {
                override fun success(result: Any?) = Unit

                override fun error(code: String, message: String?, details: Any?) {
                    pending = action
                }

                override fun notImplemented() {
                    pending = action
                }
            },
        )
    }

    /** The app's engine is going; a note widget changing has no one to tell. */
    fun detach() {
        if (running === this) running = null
    }

    companion object {
        private const val CHANNEL = "com.ionel.notes/widgets"
        private val io = Executors.newSingleThreadExecutor()

        /** The running app's channel, while its engine lives. */
        private var running: HomeWidgetsChannel? = null

        /**
         * Tells the running app which notes the note widgets show now, so its
         * next snapshot carries them. With the app closed there is no one to
         * tell: it asks when it next starts.
         */
        fun shownChanged(context: Context) {
            running?.channel?.invokeMethod("shownNotes", WidgetNotes.shown(context))
        }
    }
}
