package com.ionel.notes.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService

/**
 * Fills a notes widget's list before Android 12, one card per note in the feed
 * it shows. From Android 12 the widget hands the launcher its cards itself;
 * see NotesWidget.
 */
class NotesWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory = Cards(
        applicationContext,
        intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID),
    )

    private class Cards(private val context: Context, private val widgetId: Int) : RemoteViewsFactory {
        private var notes: List<WidgetNote> = emptyList()

        override fun onCreate() = Unit

        override fun onDataSetChanged() {
            notes = WidgetSnapshot.read(context)?.feed(WidgetFeeds.of(context, widgetId))?.notes.orEmpty()
        }

        override fun onDestroy() {
            notes = emptyList()
        }

        override fun getCount() = notes.size

        override fun getViewAt(position: Int): RemoteViews? =
            notes.getOrNull(position)?.let { NoteCards.card(context, it) }

        override fun getLoadingView(): RemoteViews? = null

        override fun getViewTypeCount() = 1

        override fun getItemId(position: Int) = notes.getOrNull(position)?.let(NoteCards::itemId) ?: position.toLong()

        override fun hasStableIds() = true
    }
}
