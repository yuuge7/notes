package com.ionel.notes.widgets

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.widget.RemoteViews
import com.ionel.notes.R

/**
 * The new note widget: the compose bar on the home screen. At four cells it
 * reads as the bar does; narrower, the words go, then photos and the camera.
 */
class CaptureWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, views(context, manager.getAppWidgetOptions(id)))
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        options: Bundle,
    ) {
        manager.updateAppWidget(id, views(context, options))
    }

    private fun views(context: Context, options: Bundle): RemoteViews {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // The launcher picks the largest of these that fits as the widget
            // is resized, without calling back.
            return RemoteViews(
                mapOf(
                    SizeF(SMALL_WIDTH, 40f) to layout(context, R.layout.widget_capture_small),
                    SizeF(MEDIUM_WIDTH, 40f) to layout(context, R.layout.widget_capture_medium),
                    SizeF(FULL_WIDTH, 40f) to layout(context, R.layout.widget_capture),
                ),
            )
        }
        // Before Android 12, from the width the launcher reports. In portrait,
        // the narrowest it will be is the width it has.
        val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, FULL_WIDTH.toInt())
        return layout(
            context,
            when {
                width >= FULL_WIDTH -> R.layout.widget_capture
                width >= MEDIUM_WIDTH -> R.layout.widget_capture_medium
                else -> R.layout.widget_capture_small
            },
        )
    }

    private fun layout(context: Context, layout: Int) = RemoteViews(context.packageName, layout).apply {
        setOnClickPendingIntent(R.id.capture_note, WidgetLaunch.pending(context, WidgetLaunch.NEW_NOTE))
        setOnClickPendingIntent(R.id.capture_list, WidgetLaunch.pending(context, WidgetLaunch.NEW_LIST))
        if (layout != R.layout.widget_capture_small) {
            setOnClickPendingIntent(R.id.capture_photos, WidgetLaunch.pending(context, WidgetLaunch.ADD_PHOTOS))
            setOnClickPendingIntent(R.id.capture_camera, WidgetLaunch.pending(context, WidgetLaunch.TAKE_PHOTO))
        }
    }

    private companion object {
        /**
         * Widths in dp from which each layout fits: every button 48dp wide, and
         * room for the words beside the four. On a typical phone that is two
         * cells, three, and four.
         */
        const val SMALL_WIDTH = 110f
        const val MEDIUM_WIDTH = 210f
        const val FULL_WIDTH = 300f
    }
}
