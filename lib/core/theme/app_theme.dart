import 'package:flutter/material.dart';
import 'package:notes/core/theme/app_colors.dart';
import 'package:notes/core/theme/tokens.dart';
import 'package:notes/core/theme/typography.dart';

/// Builds the two themes from [AppColors].
///
/// The interface is drawn with hairlines and surface colour, never with drop
/// shadows: every elevation is zeroed here so a stray Material default cannot
/// reintroduce one.
abstract final class AppTheme {
  static ThemeData light() => _build(AppColors.light, Brightness.light);

  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors colors, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.accent,
      onPrimary: colors.onAccent,
      secondary: colors.accent,
      onSecondary: colors.onAccent,
      error: colors.danger,
      onError: colors.onAccent,
      surface: colors.card,
      onSurface: colors.ink,
      surfaceContainerHighest: colors.card,
      onSurfaceVariant: colors.inkMuted,
      outline: colors.hairline,
      outlineVariant: colors.hairline,
    );

    final textTheme = TextTheme(
      displaySmall: AppText.display.copyWith(color: colors.ink),
      headlineSmall: AppText.display.copyWith(color: colors.ink, fontSize: 22),
      titleMedium: AppText.uiLarge.copyWith(color: colors.ink),
      titleSmall: AppText.uiStrong.copyWith(color: colors.ink),
      bodyLarge: AppText.uiLarge.copyWith(color: colors.ink),
      bodyMedium: AppText.ui.copyWith(color: colors.ink),
      bodySmall: AppText.ui.copyWith(color: colors.inkMuted, fontSize: 13),
      labelLarge: AppText.uiStrong.copyWith(color: colors.ink),
      labelMedium: AppText.ui.copyWith(color: colors.inkMuted),
      labelSmall: AppText.meta.copyWith(color: colors.inkMuted),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: [colors],
      scaffoldBackgroundColor: colors.ground,
      canvasColor: colors.ground,
      textTheme: textTheme,
      fontFamily: Faces.ui,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.ground,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppText.display.copyWith(color: colors.ink, fontSize: 22),
      ),
      iconTheme: IconThemeData(color: colors.ink, size: 22),
      dividerTheme: DividerThemeData(
        color: colors.hairline,
        thickness: Stroke.hairline,
        space: Stroke.hairline,
      ),
      cardTheme: CardThemeData(
        color: colors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: BorderSide(color: colors.hairline),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: colors.hairline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(Radii.sheet),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: brightness == Brightness.light
            ? colors.ink
            : colors.card,
        contentTextStyle: AppText.ui.copyWith(
          color: brightness == Brightness.light ? colors.ground : colors.ink,
        ),
        actionTextColor: colors.accent,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.small + 4),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.accent,
        selectionColor: colors.accentWash,
        selectionHandleColor: colors.accent,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.accent,
          textStyle: AppText.uiStrong,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          textStyle: AppText.uiStrong,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.bar),
          ),
          minimumSize: const Size(0, 48),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        side: BorderSide(color: colors.inkMuted, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.accent
              : Colors.transparent,
        ),
        checkColor: WidgetStateProperty.all(colors.onAccent),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.small + 4),
          side: BorderSide(color: colors.hairline),
        ),
        textStyle: AppText.ui.copyWith(color: colors.ink),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.card),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.small + 4),
              side: BorderSide(color: colors.hairline),
            ),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.sheet),
          side: BorderSide(color: colors.hairline),
        ),
        titleTextStyle: AppText.display.copyWith(
          color: colors.ink,
          fontSize: 22,
        ),
        contentTextStyle: AppText.noteBody.copyWith(color: colors.inkMuted),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: colors.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.ink,
          borderRadius: BorderRadius.circular(Radii.small),
        ),
        textStyle: AppText.ui.copyWith(color: colors.ground),
      ),
    );
  }
}
