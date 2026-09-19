package com.ionel.notes.widgets

import android.content.Context
import org.json.JSONObject
import java.io.File

/** A checklist item as the widget shows it. */
data class WidgetItem(val text: String, val checked: Boolean, val indent: Int)

/** A note as the widget shows it, worked out by the app; see widget_snapshot.dart. */
data class WidgetNote(
    val id: String,
    val pigment: String,
    val title: String,
    val body: String,
    val items: List<WidgetItem>,
    val more: Int,
    val meta: String,
    val empty: Boolean,
    val description: String,
)

/**
 * One set of notes a notes widget can show: all of them, the pinned ones, or
 * one label's. The app works out every word of it; see widget_snapshot.dart.
 */
data class WidgetFeed(
    val key: String,
    /** How the widget's settings offer it. */
    val name: String,
    /** The widget's heading. */
    val title: String,
    val count: Int,
    val notes: List<WidgetNote>,
    val preview: String,
    val empty: String,
) {
    val isLabel get() = key.startsWith(WidgetFeeds.LABEL_PREFIX)
}

/**
 * The notes the widgets show, as the app last handed them over: every feed a
 * widget can be set to.
 *
 * Kept in a file, so the widgets draw without the app running: after a
 * reboot, or when the launcher asks for the list again hours later.
 */
data class WidgetSnapshot(val feeds: List<WidgetFeed>) {
    /** The feed kept under [key], or null for a label deleted since it was chosen. */
    fun feed(key: String) = feeds.firstOrNull { it.key == key }

    companion object {
        /** Out of backups, like the database it comes from. */
        private fun file(context: Context) = File(context.noBackupFilesDir, "widgets/notes.json")

        /**
         * Replaces the snapshot. Written beside the old one and moved into
         * place, so a widget reading at the same moment gets one or the other,
         * never half of each.
         */
        fun write(context: Context, json: String) {
            val target = file(context)
            target.parentFile?.mkdirs()
            val next = File(target.parentFile, "notes.json.next")
            next.writeText(json)
            if (!next.renameTo(target)) {
                target.delete()
                check(next.renameTo(target)) { "The widget snapshot could not be saved" }
            }
        }

        /** The snapshot, or null before the app has handed one over. */
        fun read(context: Context): WidgetSnapshot? {
            val source = file(context)
            if (!source.exists()) return null
            return try {
                parse(JSONObject(source.readText()))
            } catch (e: Exception) {
                // A snapshot this version cannot read shows as none; the app
                // writes a fresh one the next time it runs.
                null
            }
        }

        /** Each feed names its notes by id, so a note on several is written once. */
        private fun parse(json: JSONObject): WidgetSnapshot {
            check(json.getInt("version") == VERSION) { "A snapshot from another version" }
            val feeds = json.getJSONArray("feeds")
            val notes = json.getJSONObject("notes")
            val parsed = mutableMapOf<String, WidgetNote>()
            return WidgetSnapshot(
                List(feeds.length()) { index ->
                    val feed = feeds.getJSONObject(index)
                    val ids = feed.getJSONArray("notes")
                    WidgetFeed(
                        key = feed.getString("feed"),
                        name = feed.getString("name"),
                        title = feed.getString("title"),
                        count = feed.getInt("count"),
                        notes = List(ids.length()) { i ->
                            val id = ids.getString(i)
                            parsed.getOrPut(id) { note(notes.getJSONObject(id)) }
                        },
                        preview = feed.optString("preview"),
                        empty = feed.optString("empty"),
                    )
                },
            )
        }

        private fun note(note: JSONObject): WidgetNote {
            val items = note.optJSONArray("items")
            return WidgetNote(
                id = note.getString("id"),
                pigment = note.optString("pigment", "graphite"),
                title = note.optString("title"),
                body = note.optString("body"),
                items = List(items?.length() ?: 0) { i ->
                    val item = items!!.getJSONObject(i)
                    WidgetItem(
                        text = item.optString("text"),
                        checked = item.optBoolean("checked"),
                        indent = item.optInt("indent"),
                    )
                },
                more = note.optInt("more"),
                meta = note.optString("meta"),
                empty = note.optBoolean("empty"),
                description = note.optString("description"),
            )
        }

        /** The snapshot's shape, which widget_snapshot.dart writes. */
        private const val VERSION = 2
    }
}
