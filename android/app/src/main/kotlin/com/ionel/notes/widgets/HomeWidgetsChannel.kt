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
 * widget taps handed back, and placing a widget from settings.
 */
class HomeWidgetsChannel(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, CHANNEL)
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /** A widget tap the app has not taken yet: the one that started it, or one that came before it listened. */
    private var pending: Map<String, String>? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "publish" -> {
                    val snapshot = call.argument<String>("snapshot")
                    if (snapshot == null) {
                        result.error("snapshot", "No snapshot", null)
                        return@setMethodCallHandler
                    }
                    io.execute {
                        try {
                            WidgetSnapshot.write(context, snapshot)
                            main.post {
                                NotesWidget.refresh(context)
                                result.success(null)
                            }
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
                "pin" -> {
                    val provider = when (call.argument<String>("widget")) {
                        "notes" -> NotesWidget::class.java
                        "capture" -> CaptureWidget::class.java
                        else -> {
                            result.error("widget", "Unknown widget", null)
                            return@setMethodCallHandler
                        }
                    }
                    result.success(
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            AppWidgetManager.getInstance(context)
                                .requestPinAppWidget(ComponentName(context, provider), null, null),
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

    private companion object {
        const val CHANNEL = "com.ionel.notes/widgets"
    }
}
