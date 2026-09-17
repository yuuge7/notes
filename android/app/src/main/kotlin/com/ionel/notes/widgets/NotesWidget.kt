package com.ionel.notes.widgets

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import com.ionel.notes.R

/**
 * The notes widget: pinned notes, then the latest, as cards, under a heading
 * with the count and a new note button. Drawn from the last snapshot the app
 * handed over, so it shows the notes with the app closed.
 */
class NotesWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        update(context, manager, ids)
    }

    companion object {
        /** Redraws every notes widget from the snapshot just saved. */
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, NotesWidget::class.java))
            if (ids.isEmpty()) return
            update(context, manager, ids)
            manager.notifyAppWidgetViewDataChanged(ids, R.id.notes_list)
        }

        private fun update(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val snapshot = WidgetSnapshot.read(context)
            for (id in ids) manager.updateAppWidget(id, views(context, id, snapshot))
        }

        @Suppress("DEPRECATION") // setRemoteAdapter(Intent): the one list API down to Android 7.
        private fun views(context: Context, id: Int, snapshot: WidgetSnapshot?) =
            RemoteViews(context.packageName, R.layout.widget_notes).apply {
                if (snapshot == null) {
                    setViewVisibility(R.id.notes_count, View.GONE)
                } else {
                    setViewVisibility(R.id.notes_count, View.VISIBLE)
                    setTextViewText(
                        R.id.notes_count,
                        context.resources.getQuantityString(
                            R.plurals.widget_notes_count,
                            snapshot.count,
                            snapshot.count,
                        ),
                    )
                }
                setOnClickPendingIntent(R.id.notes_header, WidgetLaunch.app(context))
                setOnClickPendingIntent(R.id.notes_add, WidgetLaunch.pending(context, WidgetLaunch.NEW_NOTE))

                // A service per widget: the data URI keeps each widget's
                // intent apart, or Android would share one list between them.
                val service = Intent(context, NotesWidgetService::class.java)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                service.data = Uri.parse(service.toUri(Intent.URI_INTENT_SCHEME))
                setRemoteAdapter(R.id.notes_list, service)
                setPendingIntentTemplate(R.id.notes_list, WidgetLaunch.noteTemplate(context))

                setEmptyView(R.id.notes_list, R.id.notes_empty)
                setTextViewText(
                    R.id.notes_empty,
                    context.getString(
                        if (snapshot == null) R.string.widget_notes_waiting else R.string.widget_notes_empty,
                    ),
                )
                setOnClickPendingIntent(
                    R.id.notes_empty,
                    if (snapshot == null) {
                        WidgetLaunch.app(context)
                    } else {
                        WidgetLaunch.pending(context, WidgetLaunch.NEW_NOTE)
                    },
                )
            }
    }
}
