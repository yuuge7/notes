package com.ionel.notes.widgets

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.accessibility.AccessibilityNodeInfo
import android.view.animation.PathInterpolator
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.TextView
import android.window.OnBackInvokedDispatcher
import com.ionel.notes.R

/**
 * A widget's settings. For a notes widget: every note, the pinned ones, or
 * one label's. For a note widget: which note, from the grid's first, pinned
 * ones first.
 *
 * The launcher opens it as a widget is placed, and again from the widget's
 * own settings; the widget opens it too when its label or note has been
 * deleted. The choices come from the snapshot, so it lists them with the app
 * closed. A choice applies the moment it is made, as in the app's settings.
 */
class NotesWidgetSetup : Activity() {
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private var forNote = false
    private lateinit var scrim: View
    private lateinit var sheet: View
    private var closing = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        widgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        // Backing out while placing a widget takes it off the home screen.
        setResult(RESULT_CANCELED, result())
        val provider = AppWidgetManager.getInstance(this).getAppWidgetInfo(widgetId)?.provider
        val kinds = listOf(NotesWidget::class.java.name, NoteWidget::class.java.name)
        if (provider == null || provider.className !in kinds || provider.packageName != packageName) {
            finish()
            return
        }
        forNote = provider.className == NoteWidget::class.java.name

        setContentView(R.layout.widget_setup)
        scrim = findViewById(R.id.setup_scrim)
        sheet = findViewById(R.id.setup_sheet)
        scrim.setOnClickListener { close() }
        fitBehindSystemBars()
        if (forNote) listNotes(findViewById(R.id.setup_options)) else listChoices(findViewById(R.id.setup_options))

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            onBackInvokedDispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT) { close() }
        }
        if (savedInstanceState == null) enter()
        Faces.apply(this, findViewById(R.id.setup_heading), Faces.META_STRONG)
    }

    @Deprecated("Android 12 and earlier; see onCreate for the rest.")
    override fun onBackPressed() = close()

    private fun result() = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)

    private fun listChoices(options: LinearLayout) {
        val snapshot = WidgetSnapshot.read(this)
        val chosen = WidgetFeeds.of(this, widgetId)
        fun add(key: String, feed: WidgetFeed?, fallback: Int = 0) = options.addView(
            option(
                options,
                key,
                feed?.name ?: getString(fallback),
                count = feed?.count,
                preview = feed?.preview.orEmpty(),
                chosen = key == chosen,
            ),
        )

        // Before the app has run there is no snapshot to name these, and no
        // labels to offer.
        add(WidgetFeeds.ALL, snapshot?.feed(WidgetFeeds.ALL), R.string.widget_setup_all)
        add(WidgetFeeds.PINNED, snapshot?.feed(WidgetFeeds.PINNED), R.string.widget_setup_pinned)

        options.addView(text(getString(R.string.widget_setup_labels), R.style.WidgetSetupText_Section, Faces.META_STRONG, header = true))
        val labels = snapshot?.feeds.orEmpty().filter { it.isLabel }
        for (feed in labels) add(feed.key, feed)
        if (labels.isEmpty()) {
            val hint = if (snapshot == null) R.string.widget_setup_waiting else R.string.widget_setup_no_labels
            options.addView(text(getString(hint), R.style.WidgetSetupText_Hint, Faces.UI))
        }
    }

    /**
     * The notes a note widget can show, each by its headline over what
     * follows. A note chosen from its own menu in the app may be further down
     * the grid than these; it comes first, marked.
     */
    private fun listNotes(options: LinearLayout) {
        val snapshot = WidgetSnapshot.read(this)
        if (snapshot == null) {
            options.addView(text(getString(R.string.widget_setup_notes_waiting), R.style.WidgetSetupText_Hint, Faces.UI))
            return
        }
        val chosen = WidgetNotes.of(this, widgetId)
        val current = chosen?.let { snapshot.page(it) as? PageState.Shown }?.page
        if (current != null && snapshot.choices.none { it.id == current.id }) {
            val name = current.title.ifEmpty { current.label }
            options.addView(option(options, current.id, name, count = null, preview = "", chosen = true))
        }
        for (choice in snapshot.choices) {
            options.addView(
                option(options, choice.id, choice.name, count = null, preview = choice.preview, chosen = choice.id == chosen),
            )
        }
        if (snapshot.choices.isEmpty() && current == null) {
            options.addView(text(getString(R.string.widget_setup_no_notes), R.style.WidgetSetupText_Hint, Faces.UI))
        }
    }

    private fun option(
        parent: ViewGroup,
        key: String,
        name: String,
        count: Int?,
        preview: String,
        chosen: Boolean,
    ): View {
        val row = layoutInflater.inflate(R.layout.widget_setup_option, parent, false)
        row.findViewById<RadioButton>(R.id.option_radio).isChecked = chosen
        row.findViewById<TextView>(R.id.option_name).apply {
            text = name
            Faces.apply(this@NotesWidgetSetup, this, Faces.UI)
        }
        row.findViewById<TextView>(R.id.option_count).apply {
            text = count?.toString().orEmpty()
            visibility = if (count == null) View.GONE else View.VISIBLE
            Faces.apply(this@NotesWidgetSetup, this, Faces.META)
        }
        row.findViewById<TextView>(R.id.option_preview).apply {
            text = preview
            visibility = if (text.isEmpty()) View.GONE else View.VISIBLE
            Faces.apply(this@NotesWidgetSetup, this, Faces.READING)
        }

        // TalkBack hears one radio button: the name, how many notes, and
        // the first of them; for a note, its headline and what follows.
        row.contentDescription = listOfNotNull(
            name,
            count?.let { resources.getQuantityString(R.plurals.widget_setup_count, it, it) },
            preview.takeIf { it.isNotEmpty() },
        ).joinToString(". ")
        row.accessibilityDelegate = object : View.AccessibilityDelegate() {
            override fun onInitializeAccessibilityNodeInfo(host: View, info: AccessibilityNodeInfo) {
                super.onInitializeAccessibilityNodeInfo(host, info)
                info.className = RadioButton::class.java.name
                info.isCheckable = true
                info.isChecked = chosen
            }
        }
        row.setOnClickListener { choose(key) }
        return row
    }

    private fun text(value: String, style: Int, face: Faces.Face, header: Boolean = false) =
        TextView(this, null, 0, style).apply {
            text = value
            val gap = (24 * resources.displayMetrics.density).toInt()
            setPadding(gap, if (header) gap else gap / 3, gap, gap / 3)
            if (header && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) isAccessibilityHeading = true
            Faces.apply(this@NotesWidgetSetup, this, face)
        }

    private fun choose(key: String) {
        if (closing) return
        if (forNote) {
            NoteWidget.chosen(applicationContext, widgetId, key)
        } else {
            WidgetFeeds.choose(this, widgetId, key)
            NotesWidget.redraw(this, widgetId)
        }
        setResult(RESULT_OK, result())
        close()
    }

    /**
     * Draws under the system bars, as the app does, with the sheet's content
     * clear of them. Before Android 11 the window stops above the navigation
     * bar, which the theme paints as the sheet.
     */
    @Suppress("DEPRECATION") // Bar colours: ignored from Android 15, needed before it.
    private fun fitBehindSystemBars() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        window.setDecorFitsSystemWindows(false)
        window.navigationBarColor = Color.TRANSPARENT
        window.statusBarColor = Color.TRANSPARENT
        val night = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        window.insetsController?.setSystemBarsAppearance(
            if (night) 0 else WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS,
            WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS,
        )
        val bottom = sheet.paddingBottom
        val top = (sheet.layoutParams as ViewGroup.MarginLayoutParams).topMargin
        scrim.setOnApplyWindowInsetsListener { _, insets ->
            val bars = insets.getInsets(WindowInsets.Type.systemBars())
            sheet.setPadding(sheet.paddingLeft, sheet.paddingTop, sheet.paddingRight, bottom + bars.bottom)
            (sheet.layoutParams as ViewGroup.MarginLayoutParams).topMargin = top + bars.top
            sheet.requestLayout()
            insets
        }
    }

    /**
     * The sheet rises and the scrim fades in, as the app's sheets open. The
     * system's animation scale applies, so with animations off it is simply
     * there.
     */
    private fun enter() {
        scrim.background.mutate().alpha = 0
        sheet.visibility = View.INVISIBLE
        sheet.post {
            sheet.translationY = sheet.height.toFloat()
            sheet.visibility = View.VISIBLE
            sheet.animate().translationY(0f).setDuration(ENTER_MS).setInterpolator(EASE_OUT)
                .setUpdateListener { scrim.background.alpha = (255 * it.animatedFraction).toInt() }
                .start()
        }
    }

    private fun close() {
        if (closing) return
        closing = true
        sheet.animate().cancel()
        val from = scrim.background.alpha
        sheet.animate().translationY(sheet.height.toFloat()).setDuration(EXIT_MS).setInterpolator(EASE_IN)
            .setUpdateListener { scrim.background.alpha = (from * (1 - it.animatedFraction)).toInt() }
            .withEndAction {
                finish()
                @Suppress("DEPRECATION") // The replacement is Android 14's; this covers all.
                overridePendingTransition(0, 0)
            }
            .start()
    }

    /**
     * The app's own faces, read from the copies Flutter ships in the APK. A
     * launcher cannot load them into a widget, but this is the app's own
     * window. Android 7 has no way to set a variable font's weight, and keeps
     * the system faces the styles name.
     */
    private object Faces {
        class Face(val file: String, val axes: String)

        val UI = Face("SchibstedGrotesk.ttf", "'wght' 500")
        val READING = Face("Literata.ttf", "'wght' 400")
        val META = Face("MartianMono.ttf", "'wdth' 100, 'wght' 400")
        val META_STRONG = Face("MartianMono.ttf", "'wdth' 100, 'wght' 600")

        private val loaded = mutableMapOf<Face, Typeface?>()

        fun apply(activity: Activity, view: TextView, face: Face) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val typeface = loaded.getOrPut(face) {
                try {
                    Typeface.Builder(activity.assets, "flutter_assets/assets/fonts/${face.file}")
                        .setFontVariationSettings(face.axes)
                        .build()
                } catch (e: Exception) {
                    null
                }
            }
            if (typeface != null) view.typeface = typeface
        }
    }

    private companion object {
        /** Motion.page and Motion.standard, entering on easeOutCubic and leaving on easeInCubic. */
        const val ENTER_MS = 250L
        const val EXIT_MS = 180L
        val EASE_OUT = PathInterpolator(0.33f, 1f, 0.68f, 1f)
        val EASE_IN = PathInterpolator(0.32f, 0f, 0.67f, 0f)
    }
}
