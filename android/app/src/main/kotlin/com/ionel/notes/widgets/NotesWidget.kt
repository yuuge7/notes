package com.ionel.notes.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import com.ionel.notes.R

/**
 * The notes widget: one feed of notes as cards, under a heading with its name,
 * the count, and a new note button. Each widget shows the feed chosen for it:
 * every note, the pinned ones, or one label's. Drawn from the last snapshot
 * the app handed over, so it shows the notes with the app closed.
 */
class NotesWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        update(context, manager, ids)
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        WidgetFeeds.forget(context, ids)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_PLACED) {
            // Placed from the app's settings, with the feed chosen there.
            val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            val feed = intent.getStringExtra(EXTRA_FEED)
            if (id != AppWidgetManager.INVALID_APPWIDGET_ID && feed != null) {
                WidgetFeeds.choose(context, id, feed)
                redraw(context, id)
            }
            return
        }
        super.onReceive(context, intent)
    }

    companion object {
        private const val ACTION_PLACED = "com.ionel.notes.WIDGET_PLACED"
        private const val EXTRA_FEED = "feed"

        /** Redraws every notes widget from the snapshot just saved. */
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, NotesWidget::class.java))
            if (ids.isNotEmpty()) update(context, manager, ids)
        }

        /** Redraws one widget, set to a different feed. */
        fun redraw(context: Context, id: Int) {
            update(context, AppWidgetManager.getInstance(context), intArrayOf(id))
        }

        /**
         * Sent by the launcher once it has placed a widget the app asked for,
         * so the new widget shows [feed]. Mutable, for the launcher to add
         * the widget's id.
         */
        fun placed(context: Context, feed: String): PendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, NotesWidget::class.java).setAction(ACTION_PLACED).putExtra(EXTRA_FEED, feed),
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0) or
                PendingIntent.FLAG_UPDATE_CURRENT,
        )

        private fun update(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val snapshot = WidgetSnapshot.read(context)
            for (id in ids) manager.updateAppWidget(id, views(context, id, snapshot))
            // Before Android 12 the list fills itself from the service, which
            // reads the snapshot again when told it changed.
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                manager.notifyAppWidgetViewDataChanged(ids, R.id.notes_list)
            }
        }

        private fun views(context: Context, id: Int, snapshot: WidgetSnapshot?) =
            RemoteViews(context.packageName, R.layout.widget_notes).apply {
                val feed = snapshot?.feed(WidgetFeeds.of(context, id))
                val (headerTap, emptyText, emptyTap) = when {
                    feed != null -> Triple(
                        WidgetLaunch.showFeed(context, id, feed.key),
                        feed.empty,
                        WidgetLaunch.newNote(context, id, feed.key),
                    )
                    // A label deleted since the widget was set to it: the
                    // widget asks for another choice rather than showing nothing.
                    snapshot != null -> WidgetLaunch.setup(context, id).let {
                        Triple(it, context.getString(R.string.widget_notes_gone), it)
                    }
                    else -> WidgetLaunch.app(context).let {
                        Triple(it, context.getString(R.string.widget_notes_waiting), it)
                    }
                }

                setTextViewText(R.id.notes_title, feed?.title ?: context.getString(R.string.widget_notes_title))
                setViewVisibility(R.id.notes_count, if (feed == null) View.GONE else View.VISIBLE)
                if (feed != null) {
                    setTextViewText(
                        R.id.notes_count,
                        context.resources.getQuantityString(R.plurals.widget_notes_count, feed.count, feed.count),
                    )
                }
                setOnClickPendingIntent(R.id.notes_header, headerTap)
                setOnClickPendingIntent(R.id.notes_add, WidgetLaunch.newNote(context, id, feed?.key))

                list(context, id, feed?.notes.orEmpty())
                setPendingIntentTemplate(R.id.notes_list, WidgetLaunch.noteTemplate(context))
                setEmptyView(R.id.notes_list, R.id.notes_empty)
                setTextViewText(R.id.notes_empty, emptyText)
                setOnClickPendingIntent(R.id.notes_empty, emptyTap)
            }

        /**
         * The cards, handed to the launcher with the rest of the widget from
         * Android 12. Recent versions treat a widget whose list a service
         * fills as legacy: an update only tells the launcher to fetch it,
         * which the Pixel launcher drops, so the heading kept its first name
         * and count while the cards moved on.
         */
        @Suppress("DEPRECATION") // setRemoteAdapter(Intent): the one list API before Android 12.
        private fun RemoteViews.list(context: Context, id: Int, notes: List<WidgetNote>) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val items = RemoteViews.RemoteCollectionItems.Builder()
                    .setHasStableIds(true)
                    .setViewTypeCount(1)
                for (note in notes) items.addItem(NoteCards.itemId(note), NoteCards.card(context, note))
                setRemoteAdapter(R.id.notes_list, items.build())
                return
            }
            // A service per widget: the data URI keeps each widget's intent
            // apart, or Android would share one list between them.
            val service = Intent(context, NotesWidgetService::class.java)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            service.data = Uri.parse(service.toUri(Intent.URI_INTENT_SCHEME))
            setRemoteAdapter(R.id.notes_list, service)
        }
    }
}
