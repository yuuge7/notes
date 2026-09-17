package com.ionel.notes.widgets

import android.content.Context
import android.content.Intent
import android.text.SpannableString
import android.text.Spanned
import android.text.style.StrikethroughSpan
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import com.ionel.notes.R

/** Fills the notes widget's list, one card per note in the snapshot. */
class NotesWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory = Cards(applicationContext)

    private class Cards(private val context: Context) : RemoteViewsFactory {
        private var notes: List<WidgetNote> = emptyList()

        override fun onCreate() = Unit

        override fun onDataSetChanged() {
            notes = WidgetSnapshot.read(context)?.notes.orEmpty()
        }

        override fun onDestroy() {
            notes = emptyList()
        }

        override fun getCount() = notes.size

        override fun getViewAt(position: Int): RemoteViews? =
            notes.getOrNull(position)?.let(::card)

        override fun getLoadingView(): RemoteViews? = null

        override fun getViewTypeCount() = 1

        override fun getItemId(position: Int) = notes.getOrNull(position)?.id?.hashCode()?.toLong() ?: position.toLong()

        override fun hasStableIds() = true

        private fun card(note: WidgetNote) = RemoteViews(context.packageName, R.layout.widget_note_item).apply {
            setInt(R.id.note_card, "setBackgroundResource", background(note.pigment))
            setContentDescription(R.id.note_card, note.description)
            setOnClickFillInIntent(R.id.note_card, WidgetLaunch.openNote(note.id))

            text(R.id.note_title, note.title)
            text(R.id.note_body, note.body)
            setViewVisibility(R.id.note_empty, if (note.empty) View.VISIBLE else View.GONE)

            val indentStep = (16 * context.resources.displayMetrics.density).toInt()
            val rowPadding = (3 * context.resources.displayMetrics.density).toInt()
            for ((index, slot) in ROWS.withIndex()) {
                val item = note.items.getOrNull(index)
                if (item == null) {
                    setViewVisibility(slot.row, View.GONE)
                    continue
                }
                setViewVisibility(slot.row, View.VISIBLE)
                setViewPadding(slot.row, item.indent * indentStep, rowPadding, 0, rowPadding)
                setImageViewResource(
                    slot.box,
                    if (item.checked) R.drawable.ic_widget_box_done else R.drawable.ic_widget_box_open,
                )
                if (item.checked) {
                    // A checked item reads as on its card: muted, and struck through.
                    val struck = SpannableString(item.text).apply {
                        setSpan(StrikethroughSpan(), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    }
                    setTextViewText(slot.done, struck)
                    setViewVisibility(slot.done, View.VISIBLE)
                    setViewVisibility(slot.open, View.GONE)
                } else {
                    setTextViewText(slot.open, item.text)
                    setViewVisibility(slot.open, View.VISIBLE)
                    setViewVisibility(slot.done, View.GONE)
                }
            }

            text(R.id.note_more, if (note.more > 0) context.getString(R.string.widget_more, note.more) else "")
            text(R.id.note_meta, note.meta)
        }

        /** Sets [value] on a text view, hiding it when there is nothing to show. */
        private fun RemoteViews.text(id: Int, value: String) {
            setTextViewText(id, value)
            setViewVisibility(id, if (value.isEmpty()) View.GONE else View.VISIBLE)
        }

        private fun background(pigment: String) = when (pigment) {
            "vermilion" -> R.drawable.widget_card_vermilion
            "amber" -> R.drawable.widget_card_amber
            "moss" -> R.drawable.widget_card_moss
            "verdigris" -> R.drawable.widget_card_verdigris
            "indigo" -> R.drawable.widget_card_indigo
            "plum" -> R.drawable.widget_card_plum
            "clay" -> R.drawable.widget_card_clay
            else -> R.drawable.widget_card_graphite
        }
    }

    private data class Row(val row: Int, val box: Int, val open: Int, val done: Int)

    private companion object {
        val ROWS = listOf(
            Row(R.id.note_row_1, R.id.note_box_1, R.id.note_item_1, R.id.note_done_1),
            Row(R.id.note_row_2, R.id.note_box_2, R.id.note_item_2, R.id.note_done_2),
            Row(R.id.note_row_3, R.id.note_box_3, R.id.note_item_3, R.id.note_done_3),
            Row(R.id.note_row_4, R.id.note_box_4, R.id.note_item_4, R.id.note_done_4),
            Row(R.id.note_row_5, R.id.note_box_5, R.id.note_item_5, R.id.note_done_5),
        )
    }
}
