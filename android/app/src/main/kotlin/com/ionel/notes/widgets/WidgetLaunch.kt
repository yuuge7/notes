package com.ionel.notes.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Build
import com.ionel.notes.MainActivity

/**
 * How a tap on a widget reaches the app: an intent to MainActivity naming
 * what to do, which the app reads as a widget action.
 */
object WidgetLaunch {
    private const val ACTION = "com.ionel.notes.WIDGET"
    private const val EXTRA_ACTION = "widgetAction"
    private const val EXTRA_NOTE = "noteId"
    private const val EXTRA_FEED = "feed"

    const val NEW_NOTE = "newNote"
    const val NEW_LIST = "newList"
    const val ADD_PHOTOS = "addPhotos"
    const val TAKE_PHOTO = "takePhoto"
    private const val OPEN = "open"
    private const val SHOW_FEED = "showFeed"
    private const val ADD_ITEM = "addItem"

    /**
     * Where the request codes of each widget's own intents start. Two per
     * widget, past the fixed codes above; request codes rather than intent
     * data keep them apart, since FlutterActivity reads data as a deep link.
     * Widget ids are unique across both kinds of widget.
     */
    private const val WIDGET_CODES = 100

    /** Starts [action] in the app. Each action has a request code of its own, so their intents stay apart. */
    fun pending(context: Context, action: String): PendingIntent {
        val code = when (action) {
            NEW_NOTE -> 1
            NEW_LIST -> 2
            ADD_PHOTOS -> 3
            TAKE_PHOTO -> 4
            else -> error("Unknown widget action $action")
        }
        return PendingIntent.getActivity(
            context,
            code,
            intent(context).putExtra(EXTRA_ACTION, action),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    /**
     * The + on notes widget [widgetId]: a note for its [feed], which the app
     * pins or labels to match. Null for a feed that is gone.
     */
    fun newNote(context: Context, widgetId: Int, feed: String?) =
        forFeed(context, WIDGET_CODES + widgetId * 2, NEW_NOTE, feed)

    /** The heading of notes widget [widgetId]: the app, at the page its [feed] mirrors. */
    fun showFeed(context: Context, widgetId: Int, feed: String) =
        forFeed(context, WIDGET_CODES + widgetId * 2 + 1, SHOW_FEED, feed)

    /** The + on note widget [widgetId]: its list [noteId], with a new item ready to type into. */
    fun addItem(context: Context, widgetId: Int, noteId: String) =
        forNote(context, WIDGET_CODES + widgetId * 2, ADD_ITEM, noteId)

    /** The heading of note widget [widgetId]: its note [noteId], open in the app. */
    fun showNote(context: Context, widgetId: Int, noteId: String) =
        forNote(context, WIDGET_CODES + widgetId * 2 + 1, OPEN, noteId)

    private fun forNote(context: Context, code: Int, action: String, noteId: String): PendingIntent =
        PendingIntent.getActivity(
            context,
            code,
            intent(context).putExtra(EXTRA_ACTION, action).putExtra(EXTRA_NOTE, noteId),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    private fun forFeed(context: Context, code: Int, action: String, feed: String?): PendingIntent =
        PendingIntent.getActivity(
            context,
            code,
            intent(context).putExtra(EXTRA_ACTION, action).putExtra(EXTRA_FEED, feed),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    /** Opens the settings of widget [widgetId], a notes or a note widget, to choose what it shows. */
    fun setup(context: Context, widgetId: Int): PendingIntent = PendingIntent.getActivity(
        context,
        widgetId,
        Intent(context, NotesWidgetSetup::class.java)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    /** Opens the app as the launcher icon does. */
    fun app(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        5,
        Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    /**
     * The intent every note in the list opens with, completed by [openNote].
     * It must be mutable for the note to be filled in.
     */
    fun noteTemplate(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        6,
        intent(context),
        (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0) or
            PendingIntent.FLAG_UPDATE_CURRENT,
    )

    /** What one note in the list adds to [noteTemplate]. */
    fun openNote(noteId: String): Intent =
        Intent().putExtra(EXTRA_ACTION, OPEN).putExtra(EXTRA_NOTE, noteId)

    /**
     * The action [intent] carries, as the app reads it, or null for an intent
     * that is not a widget tap. An intent brought back from recents is not a
     * new tap, and would open the same note again.
     */
    fun read(intent: Intent?): Map<String, String>? {
        if (intent?.action != ACTION) return null
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return null
        val action = intent.getStringExtra(EXTRA_ACTION) ?: return null
        return buildMap {
            put("action", action)
            intent.getStringExtra(EXTRA_NOTE)?.let { put("noteId", it) }
            intent.getStringExtra(EXTRA_FEED)?.let { put("feed", it) }
        }
    }

    private fun intent(context: Context) = Intent(context, MainActivity::class.java)
        .setAction(ACTION)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
}
