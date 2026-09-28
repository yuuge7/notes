package com.ionel.notes.widgets

import android.content.Context
import android.os.Build
import android.text.SpannableString
import android.text.Spanned
import android.text.style.StrikethroughSpan
import android.view.View
import android.widget.RemoteViews
import com.ionel.notes.R

/**
 * A note widget's list: each item a box to tick, the count the checked items
 * fold under, or the text of a note that is not a list. Drawn for the list
 * the widget hands the launcher itself, and before Android 12 for the one
 * NotesWidgetService fills.
 */
object NotePages {
    /** One row, with an id that stays the same each time it is drawn. */
    class Row(val id: Long, val views: RemoteViews)

    /** Items, the fold, the text, and the count of what is left out. */
    const val VIEW_TYPES = 4

    private const val FOLD_ID = Long.MIN_VALUE
    private const val MORE_ID = Long.MIN_VALUE + 1
    private const val MORE_DONE_ID = Long.MIN_VALUE + 2
    private const val TEXT_ID = Long.MIN_VALUE + 3

    /**
     * The rows of [page] on widget [widgetId]. The checked items are folded
     * as the app's setting has them until the count is tapped on this widget.
     */
    fun rows(context: Context, widgetId: Int, page: WidgetPage): List<Row> {
        if (!page.checklist) {
            return if (page.body.isEmpty()) emptyList() else listOf(Row(TEXT_ID, text(context, page)))
        }
        val folded = WidgetNotes.folded(context, widgetId) ?: page.folded
        return buildList {
            for (item in page.items) add(Row(itemId(item), item(context, page, item)))
            if (page.more > 0) add(Row(MORE_ID, more(context, page.more)))
            if (page.doneCount.isNotEmpty()) {
                add(Row(FOLD_ID, fold(context, widgetId, page, folded)))
                if (!folded) {
                    for (item in page.done) add(Row(itemId(item), item(context, page, item)))
                    if (page.moreDone > 0) add(Row(MORE_DONE_ID, more(context, page.moreDone)))
                }
            }
        }
    }

    private fun itemId(item: WidgetItem) = item.id.hashCode().toLong()

    private fun item(context: Context, page: WidgetPage, item: WidgetItem) =
        RemoteViews(context.packageName, R.layout.widget_note_row).apply {
            val density = context.resources.displayMetrics.density
            setViewPadding(R.id.row, ((4 + item.indent * INDENT_DP) * density).toInt(), 0, 0, 0)
            // Struck through once ticked, as on its card; the launcher mutes
            // the words the moment the box is tapped, and the strike follows
            // with the app's next snapshot.
            val words: CharSequence = if (!item.checked) item.text else SpannableString(item.text).apply {
                setSpan(StrikethroughSpan(), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            val tick = NoteWidget.check(page.id, item.id, checked = !item.checked)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                setTextViewText(R.id.row_check, words)
                setCompoundButtonChecked(R.id.row_check, item.checked)
                setOnCheckedChangeResponse(R.id.row_check, RemoteViews.RemoteResponse.fromFillInIntent(tick))
            } else {
                setImageViewResource(
                    R.id.row_box,
                    if (item.checked) R.drawable.ic_widget_box_done else R.drawable.ic_widget_box_open,
                )
                setTextViewText(if (item.checked) R.id.row_done else R.id.row_text, words)
                setViewVisibility(R.id.row_done, if (item.checked) View.VISIBLE else View.GONE)
                setViewVisibility(R.id.row_text, if (item.checked) View.GONE else View.VISIBLE)
                setContentDescription(
                    R.id.row_check,
                    context.getString(if (item.checked) R.string.widget_item_done else R.string.widget_item_open, item.text),
                )
                setOnClickFillInIntent(R.id.row_check, tick)
            }
        }

    private fun fold(context: Context, widgetId: Int, page: WidgetPage, folded: Boolean) =
        RemoteViews(context.packageName, R.layout.widget_note_fold).apply {
            setTextViewText(R.id.fold_label, page.doneCount)
            setImageViewResource(
                R.id.fold_icon,
                if (folded) R.drawable.ic_widget_expand_more else R.drawable.ic_widget_expand_less,
            )
            setContentDescription(
                R.id.fold_row,
                context.getString(if (folded) R.string.widget_note_show_done else R.string.widget_note_hide_done, page.doneCount),
            )
            setOnClickFillInIntent(R.id.fold_row, NoteWidget.fold(widgetId, folded = !folded))
        }

    private fun text(context: Context, page: WidgetPage) =
        RemoteViews(context.packageName, R.layout.widget_note_text).apply {
            setTextViewText(R.id.page_body, page.body)
            setOnClickFillInIntent(R.id.page_body, WidgetLaunch.openNote(page.id))
        }

    private fun more(context: Context, count: Int) =
        RemoteViews(context.packageName, R.layout.widget_note_more).apply {
            setTextViewText(R.id.page_more, context.getString(R.string.widget_more, count))
        }

    /** A child sits under its parent's words, past the box. */
    private const val INDENT_DP = 34
}
