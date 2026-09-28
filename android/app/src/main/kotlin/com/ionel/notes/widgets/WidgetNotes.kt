package com.ionel.notes.widgets

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context

/**
 * Which note each note widget shows, chosen as it is placed or since in its
 * settings, and whether its checked items are folded away there.
 *
 * Kept by Android, as WidgetFeeds is, since a widget draws with the app
 * closed. The app asks for [shown] to know which notes the snapshot carries
 * whole.
 */
object WidgetNotes {
    private fun prefs(context: Context) =
        context.getSharedPreferences("notes_widgets", Context.MODE_PRIVATE)

    /** The note widget [widgetId] shows, or null before one is chosen. */
    fun of(context: Context, widgetId: Int): String? = prefs(context).getString(note(widgetId), null)

    /** Sets the note; its checked items fold as the app's setting has them until tapped. */
    fun choose(context: Context, widgetId: Int, noteId: String) {
        prefs(context).edit().putString(note(widgetId), noteId).remove(folded(widgetId)).apply()
    }

    /** Whether the checked items are folded on this widget, or null where they have not been tapped. */
    fun folded(context: Context, widgetId: Int): Boolean? {
        val prefs = prefs(context)
        return if (prefs.contains(folded(widgetId))) prefs.getBoolean(folded(widgetId), true) else null
    }

    fun fold(context: Context, widgetId: Int, folded: Boolean) {
        prefs(context).edit().putBoolean(folded(widgetId), folded).apply()
    }

    fun forget(context: Context, widgetIds: IntArray) {
        val editor = prefs(context).edit()
        for (id in widgetIds) editor.remove(note(id)).remove(folded(id))
        editor.apply()
    }

    /** Every note a note widget on the home screen shows, once each. */
    fun shown(context: Context): List<String> {
        val ids = AppWidgetManager.getInstance(context)
            .getAppWidgetIds(ComponentName(context, NoteWidget::class.java))
        return ids.toList().mapNotNull { of(context, it) }.distinct()
    }

    private fun note(widgetId: Int) = "note_$widgetId"

    private fun folded(widgetId: Int) = "folded_$widgetId"
}
