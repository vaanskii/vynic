import 'package:flutter/material.dart';
import 'package:vynic/core/ui/vynic_floor_tokens.dart';
import 'package:vynic/core/ui/vynic_touch_targets.dart';

/// The POS root theme. Manager keeps its separate application theme.
/// Use the bundled Georgian font on the terminal as well as in visual fixtures.
abstract final class PosTheme {
  static const fontFamily = 'NotoSansGeorgian';
  static const controlSize = Size(
    VynicTouchTargets.posDesktop,
    VynicTouchTargets.posDesktop,
  );
  static const _controlStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(controlSize),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    ),
    elevation: WidgetStatePropertyAll(0),
  );

  static final light = ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: VynicFloorTokens.accentStrong,
          brightness: Brightness.light,
        ).copyWith(
          primary: VynicFloorTokens.accentStrong,
          onPrimary: VynicFloorTokens.panel,
          primaryContainer: VynicFloorTokens.accentSoft,
          onPrimaryContainer: VynicFloorTokens.accentText,
          secondary: VynicFloorTokens.accentText,
          surface: VynicFloorTokens.panel,
          onSurface: VynicFloorTokens.text,
          onSurfaceVariant: VynicFloorTokens.textMuted,
          outline: VynicFloorTokens.tileBorderHover,
          outlineVariant: VynicFloorTokens.panelBorder,
          error: VynicFloorTokens.dangerText,
          onError: VynicFloorTokens.panel,
        ),
    scaffoldBackgroundColor: VynicFloorTokens.page,
    dividerColor: VynicFloorTokens.divider,
    filledButtonTheme: const FilledButtonThemeData(style: _controlStyle),
    elevatedButtonTheme: const ElevatedButtonThemeData(style: _controlStyle),
    outlinedButtonTheme: const OutlinedButtonThemeData(style: _controlStyle),
    textButtonTheme: const TextButtonThemeData(style: _controlStyle),
    iconButtonTheme: const IconButtonThemeData(style: _controlStyle),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VynicFloorTokens.canvas,
      contentPadding: const EdgeInsets.all(16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: VynicFloorTokens.panelBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: VynicFloorTokens.panelBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          color: VynicFloorTokens.accentStrong,
          width: 2,
        ),
      ),
      errorMaxLines: 3,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: VynicFloorTokens.accentStrong,
      selectionColor: VynicFloorTokens.accentSoft,
      selectionHandleColor: VynicFloorTokens.accentStrong,
    ),
  );
}
