package com.ionel.notes.widgets

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** A checklist item as the widget shows it. On a note widget it has its id, to be ticked off by. */
data class WidgetItem(val text: String, val checked: Boolean, val indent: Int, val id: String = "")

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

/** A note a note widget can be set to, as its settings offer it. */
data class WidgetChoice(val id: String, val name: String, val preview: String)

/**
 * One note whole, as a note widget shows it; see `_encodePage` in
 * widget_snapshot.dart. [items] are the open ones, or all of them when checked
 * items stay in place; [done] the checked ones kept below, under [doneCount].
 */
data class WidgetPage(
    val id: String,
    val pigment: String,
    val checklist: Boolean,
    val title: String,
    val meta: String,
    val label: String,
    val body: String,
    val items: List<WidgetItem>,
    val done: List<WidgetItem>,
    val doneCount: String,
    /** Whether the checked items start folded away, as the app's setting has it. */
    val folded: Boolean,
    /** Open items past what the snapshot holds, and checked ones. */
    val more: Int,
    val moreDone: Int,
    val empty: String,
)

/** What the snapshot says of the note a note widget is set to. */
sealed interface PageState {
    data class Shown(val page: WidgetPage) : PageState

    /** Deleted, or in the trash, since the widget was set to it. */
    data object Gone : PageState

    /** Chosen since the app last handed over a snapshot. */
    data object Pending : PageState
}

/**
 * The notes the widgets show, as the app last handed them over: every feed a
 * notes widget can be set to, the notes a note widget can be set to, and the
 * notes the note widgets show.
 *
 * Kept in a file, so the widgets draw without the app running: after a
 * reboot, or when the launcher asks for the list again hours later.
 */
data class WidgetSnapshot(
    val feeds: List<WidgetFeed>,
    val choices: List<WidgetChoice>,
    private val pages: Map<String, WidgetPage?>,
) {
    /** The feed kept under [key], or null for a label deleted since it was chosen. */
    fun feed(key: String) = feeds.firstOrNull { it.key == key }

    fun page(noteId: String): PageState = when {
        !pages.containsKey(noteId) -> PageState.Pending
        else -> pages[noteId]?.let { PageState.Shown(it) } ?: PageState.Gone
    }

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

        /**
         * Whether there is a snapshot this version cannot read: one the app
         * wrote before an update changed its shape.
         */
        fun stale(context: Context) = file(context).exists() && read(context) == null

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
            val choices = json.getJSONArray("choices")
            val pages = json.getJSONObject("pages")
            return WidgetSnapshot(
                feeds = List(feeds.length()) { index ->
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
                choices = List(choices.length()) { index ->
                    val choice = choices.getJSONObject(index)
                    WidgetChoice(
                        id = choice.getString("id"),
                        name = choice.optString("name"),
                        preview = choice.optString("preview"),
                    )
                },
                pages = pages.keys().asSequence().associateWith { id ->
                    if (pages.isNull(id)) null else page(pages.getJSONObject(id))
                },
            )
        }

        private fun page(page: JSONObject) = WidgetPage(
            id = page.getString("id"),
            pigment = page.optString("pigment", "graphite"),
            checklist = page.optBoolean("checklist"),
            title = page.optString("title"),
            meta = page.optString("meta"),
            label = page.optString("label"),
            body = page.optString("body"),
            items = items(page.optJSONArray("items")),
            done = items(page.optJSONArray("done")),
            doneCount = page.optString("doneCount"),
            folded = page.optBoolean("folded", true),
            more = page.optInt("more"),
            moreDone = page.optInt("moreDone"),
            empty = page.optString("empty"),
        )

        private fun items(items: JSONArray?) = List(items?.length() ?: 0) { i ->
            val item = items!!.getJSONObject(i)
            WidgetItem(
                text = item.optString("text"),
                checked = item.optBoolean("checked"),
                indent = item.optInt("indent"),
                id = item.optString("id"),
            )
        }

        private fun note(note: JSONObject): WidgetNote {
            return WidgetNote(
                id = note.getString("id"),
                pigment = note.optString("pigment", "graphite"),
                title = note.optString("title"),
                body = note.optString("body"),
                items = items(note.optJSONArray("items")),
                more = note.optInt("more"),
                meta = note.optString("meta"),
                empty = note.optBoolean("empty"),
                description = note.optString("description"),
            )
        }

        /** The snapshot's shape, which widget_snapshot.dart writes. */
        private const val VERSION = 3
    }
}
