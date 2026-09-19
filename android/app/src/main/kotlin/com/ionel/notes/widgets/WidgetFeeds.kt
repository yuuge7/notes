package com.ionel.notes.widgets

import android.content.Context

/**
 * Which feed each notes widget shows, as chosen when it was placed or since
 * in its settings. Keys are the app's; see `WidgetFeed` in home_widgets.dart.
 *
 * Kept by Android rather than the app, since a widget draws with the app
 * closed. A widget placed before there was a choice shows every note.
 */
object WidgetFeeds {
    const val ALL = "all"
    const val PINNED = "pinned"
    const val LABEL_PREFIX = "label:"

    private fun prefs(context: Context) =
        context.getSharedPreferences("notes_widgets", Context.MODE_PRIVATE)

    fun of(context: Context, widgetId: Int): String =
        prefs(context).getString(key(widgetId), null) ?: ALL

    fun choose(context: Context, widgetId: Int, feed: String) {
        prefs(context).edit().putString(key(widgetId), feed).apply()
    }

    fun forget(context: Context, widgetIds: IntArray) {
        val editor = prefs(context).edit()
        for (id in widgetIds) editor.remove(key(id))
        editor.apply()
    }

    private fun key(widgetId: Int) = "feed_$widgetId"
}
