package com.ionel.notes.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService

/**
 * Fills a widget's list before Android 12: for a notes widget one card per
 * note in the feed it shows, and for a note widget ([EXTRA_PAGE]) the rows of
 * its note. From Android 12 the widgets hand the launcher their lists
 * themselves; see NotesWidget and NoteWidget.
 */
class NotesWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        return if (intent.getBooleanExtra(EXTRA_PAGE, false)) Rows(applicationContext, id) else Cards(applicationContext, id)
    }

    companion object {
        const val EXTRA_PAGE = "page"
    }

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

    private class Rows(private val context: Context, private val widgetId: Int) : RemoteViewsFactory {
        private var rows: List<NotePages.Row> = emptyList()

        override fun onCreate() = Unit

        override fun onDataSetChanged() {
            val noteId = WidgetNotes.of(context, widgetId)
            val state = noteId?.let { WidgetSnapshot.read(context)?.page(it) }
            rows = if (state is PageState.Shown) NotePages.rows(context, widgetId, state.page) else emptyList()
        }

        override fun onDestroy() {
            rows = emptyList()
        }

        override fun getCount() = rows.size

        override fun getViewAt(position: Int): RemoteViews? = rows.getOrNull(position)?.views

        override fun getLoadingView(): RemoteViews? = null

        override fun getViewTypeCount() = NotePages.VIEW_TYPES

        override fun getItemId(position: Int) = rows.getOrNull(position)?.id ?: position.toLong()

        override fun hasStableIds() = true
    }
}
