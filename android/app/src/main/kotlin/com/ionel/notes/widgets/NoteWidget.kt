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
 * The note widget: one note on its own card, chosen as it is placed. A list's
 * items are boxes to tick right on the home screen, with the app closed or
 * open; a text note shows its text. The heading opens the note, and the + on
 * a list opens it on a new item.
 *
 * A tick goes to the app's own code through WidgetWorker, which writes it as
 * the editor would and hands every widget a new snapshot. From Android 12 the
 * launcher flips the box as it is tapped, so it answers at once.
 */
class NoteWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        update(context, manager, ids)
        WidgetWorker.healIfStale(this, context)
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        WidgetNotes.forget(context, ids)
        HomeWidgetsChannel.shownChanged(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        when (intent.action) {
            ACTION_ROW -> row(context, id, intent)
            ACTION_PLACED -> {
                // Placed from a note's menu in the app, with the note chosen there.
                val noteId = intent.getStringExtra(EXTRA_NOTE)
                if (id != AppWidgetManager.INVALID_APPWIDGET_ID && noteId != null) {
                    val pending = goAsync()
                    chosen(context, id, noteId) { pending.finish() }
                }
            }
            else -> super.onReceive(context, intent)
        }
    }

    /** A tap on a row: an item ticked or unticked, or the checked items folded or brought back. */
    private fun row(context: Context, id: Int, intent: Intent) {
        when (intent.getStringExtra(EXTRA_ROW)) {
            ROW_CHECK -> {
                val noteId = intent.getStringExtra(EXTRA_NOTE) ?: return
                val itemId = intent.getStringExtra(EXTRA_ITEM) ?: return
                // From Android 12 the launcher says what the box now shows;
                // before, the row asks for the opposite of what it showed.
                val checked = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    intent.hasExtra(RemoteViews.EXTRA_CHECKED)
                ) {
                    intent.getBooleanExtra(RemoteViews.EXTRA_CHECKED, false)
                } else {
                    intent.getBooleanExtra(EXTRA_CHECKED, false)
                }
                val pending = goAsync()
                WidgetWorker.setChecked(context, noteId, itemId, checked) { pending.finish() }
            }
            ROW_FOLD -> {
                if (id == AppWidgetManager.INVALID_APPWIDGET_ID) return
                WidgetNotes.fold(context, id, intent.getBooleanExtra(EXTRA_FOLDED, true))
                redraw(context, id)
            }
        }
    }

    companion object {
        private const val ACTION_ROW = "com.ionel.notes.NOTE_WIDGET_ROW"
        private const val ACTION_PLACED = "com.ionel.notes.NOTE_WIDGET_PLACED"
        private const val EXTRA_ROW = "row"
        private const val EXTRA_NOTE = "noteId"
        private const val EXTRA_ITEM = "itemId"
        private const val EXTRA_CHECKED = "checked"
        private const val EXTRA_FOLDED = "folded"
        private const val ROW_CHECK = "check"
        private const val ROW_FOLD = "fold"

        /** Redraws every note widget from the snapshot just saved. */
        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, NoteWidget::class.java))
            if (ids.isNotEmpty()) update(context, manager, ids)
        }

        fun redraw(context: Context, id: Int) {
            update(context, AppWidgetManager.getInstance(context), intArrayOf(id))
        }

        /**
         * Widget [id] now shows [noteId]: it redraws, and the app learns
         * which notes to carry whole. A note the snapshot does not carry yet
         * is loaded without waiting for the app to open; [done] runs once it
         * has been.
         */
        fun chosen(context: Context, id: Int, noteId: String, done: () -> Unit = {}) {
            WidgetNotes.choose(context, id, noteId)
            redraw(context, id)
            HomeWidgetsChannel.shownChanged(context)
            val snapshot = WidgetSnapshot.read(context)
            if (snapshot == null || snapshot.page(noteId) == PageState.Pending) {
                WidgetWorker.refresh(context, done)
            } else {
                done()
            }
        }

        /**
         * Sent by the launcher once it has placed a widget the app asked for,
         * so the new widget shows [noteId]. Mutable, for the launcher to add
         * the widget's id.
         */
        fun placed(context: Context, noteId: String): PendingIntent = PendingIntent.getBroadcast(
            context,
            1,
            Intent(context, NoteWidget::class.java).setAction(ACTION_PLACED).putExtra(EXTRA_NOTE, noteId),
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0) or
                PendingIntent.FLAG_UPDATE_CURRENT,
        )

        /** What a row with a box adds to the list's template: tick or untick the item. */
        fun check(noteId: String, itemId: String, checked: Boolean): Intent = Intent()
            .putExtra(EXTRA_ROW, ROW_CHECK)
            .putExtra(EXTRA_NOTE, noteId)
            .putExtra(EXTRA_ITEM, itemId)
            .putExtra(EXTRA_CHECKED, checked)

        /** What the count over the checked items adds: fold them or bring them back on this widget. */
        fun fold(widgetId: Int, folded: Boolean): Intent = Intent()
            .putExtra(EXTRA_ROW, ROW_FOLD)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            .putExtra(EXTRA_FOLDED, folded)

        /**
         * The broadcast every row of a list completes. One per widget, by
         * request code; mutable for the row to be filled in.
         */
        private fun rowTemplate(context: Context, widgetId: Int): PendingIntent = PendingIntent.getBroadcast(
            context,
            widgetId,
            Intent(context, NoteWidget::class.java).setAction(ACTION_ROW),
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0) or
                PendingIntent.FLAG_UPDATE_CURRENT,
        )

        private fun update(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val snapshot = WidgetSnapshot.read(context)
            for (id in ids) manager.updateAppWidget(id, views(context, id, snapshot))
            // Before Android 12 the list fills itself from the service, which
            // reads the snapshot again when told it changed.
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                manager.notifyAppWidgetViewDataChanged(ids, R.id.note_rows)
            }
        }

        private fun views(context: Context, id: Int, snapshot: WidgetSnapshot?): RemoteViews {
            val noteId = WidgetNotes.of(context, id)
            val state = if (noteId == null || snapshot == null) null else snapshot.page(noteId)
            if (state is PageState.Shown) return page(context, id, state.page)

            // Nothing to show yet, or any more: the widget says why, and a
            // tap leads to what would fix it.
            val (text, tap) = when {
                noteId == null -> R.string.widget_note_unset to WidgetLaunch.setup(context, id)
                snapshot == null -> R.string.widget_note_waiting to WidgetLaunch.app(context)
                state == PageState.Gone -> R.string.widget_note_gone to WidgetLaunch.setup(context, id)
                else -> R.string.widget_note_pending to WidgetLaunch.showNote(context, id, noteId)
            }
            return RemoteViews(context.packageName, R.layout.widget_note).apply {
                setInt(android.R.id.background, "setBackgroundResource", R.drawable.widget_page_graphite)
                setViewVisibility(R.id.note_top, View.VISIBLE)
                setTextViewText(R.id.note_heading, context.getString(R.string.widget_note_title))
                setViewVisibility(R.id.note_heading, View.VISIBLE)
                setViewVisibility(R.id.note_meta, View.GONE)
                setViewVisibility(R.id.note_add, View.GONE)
                setOnClickPendingIntent(R.id.note_header, tap)
                list(context, id, emptyList())
                setEmptyView(R.id.note_rows, R.id.note_rows_empty)
                setTextViewText(R.id.note_rows_empty, context.getString(text))
                setOnClickPendingIntent(R.id.note_rows_empty, tap)
            }
        }

        private fun page(context: Context, id: Int, page: WidgetPage) =
            RemoteViews(context.packageName, R.layout.widget_note).apply {
                setInt(android.R.id.background, "setBackgroundResource", background(page.pigment))

                // An untitled text note has no heading to show; its text starts
                // at the top.
                val open = WidgetLaunch.showNote(context, id, page.id)
                val add = if (page.checklist) WidgetLaunch.addItem(context, id, page.id) else null
                setViewVisibility(
                    R.id.note_top,
                    if (page.title.isEmpty() && page.meta.isEmpty() && add == null) View.GONE else View.VISIBLE,
                )
                setTextViewText(R.id.note_heading, page.title)
                setViewVisibility(R.id.note_heading, if (page.title.isEmpty()) View.GONE else View.VISIBLE)
                setTextViewText(R.id.note_meta, page.meta)
                setViewVisibility(R.id.note_meta, if (page.meta.isEmpty()) View.GONE else View.VISIBLE)
                setContentDescription(R.id.note_header, page.label)
                setOnClickPendingIntent(R.id.note_header, open)
                setViewVisibility(R.id.note_add, if (add == null) View.GONE else View.VISIBLE)
                if (add != null) setOnClickPendingIntent(R.id.note_add, add)

                list(context, id, NotePages.rows(context, id, page))
                // A list's rows tick items, which a broadcast does without
                // opening the app; a text note's row opens it.
                setPendingIntentTemplate(
                    R.id.note_rows,
                    if (page.checklist) rowTemplate(context, id) else WidgetLaunch.noteTemplate(context),
                )
                setEmptyView(R.id.note_rows, R.id.note_rows_empty)
                setTextViewText(R.id.note_rows_empty, page.empty)
                setOnClickPendingIntent(R.id.note_rows_empty, add ?: open)
            }

        /**
         * The rows, handed to the launcher with the rest of the widget from
         * Android 12, as the notes widget hands its cards; before, a service
         * fills them.
         */
        @Suppress("DEPRECATION") // setRemoteAdapter(Intent): the one list API before Android 12.
        private fun RemoteViews.list(context: Context, id: Int, rows: List<NotePages.Row>) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val items = RemoteViews.RemoteCollectionItems.Builder()
                    .setHasStableIds(true)
                    .setViewTypeCount(NotePages.VIEW_TYPES)
                for (row in rows) items.addItem(row.id, row.views)
                setRemoteAdapter(R.id.note_rows, items.build())
                return
            }
            val service = Intent(context, NotesWidgetService::class.java)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                .putExtra(NotesWidgetService.EXTRA_PAGE, true)
            service.data = Uri.parse(service.toUri(Intent.URI_INTENT_SCHEME))
            setRemoteAdapter(R.id.note_rows, service)
        }

        private fun background(pigment: String) = when (pigment) {
            "vermilion" -> R.drawable.widget_page_vermilion
            "amber" -> R.drawable.widget_page_amber
            "moss" -> R.drawable.widget_page_moss
            "verdigris" -> R.drawable.widget_page_verdigris
            "indigo" -> R.drawable.widget_page_indigo
            "plum" -> R.drawable.widget_page_plum
            "clay" -> R.drawable.widget_page_clay
            else -> R.drawable.widget_page_graphite
        }
    }
}
