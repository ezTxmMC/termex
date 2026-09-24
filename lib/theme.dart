import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// Lumen IDE dark palette.
class L {
  static const bg = Color(0xFF0E1013);
  static const surface = Color(0xFF14171C);
  static const overlay = Color(0xFF1A1E25);
  static const input = Color(0xFF1B1F26);
  static const hover = Color(0xFF1E232B);
  static const active = Color(0xFF262C36);
  static const border = Color(0xFF232830);
  static const borderStrong = Color(0xFF333A45);
  static const text = Color(0xFFE4E7EC);
  static const muted = Color(0xFF9AA3B0);
  static const subtle = Color(0xFF646D7A);
  static const accent = Color(0xFF7C8CFF);
  static const onAccent = Color(0xFF0B0D10);
  static const danger = Color(0xFFF87171);
  static const ok = Color(0xFF4ADE80);
  static const warn = Color(0xFFFBBF24);
  static const selection = Color(0xFF2D3550);

  static const radius = 10.0;
  static const radiusSm = 6.0;
  static const mono = 'JetBrains Mono';

  static final terminal = TerminalTheme(
    cursor: accent,
    selection: selection,
    foreground: text,
    background: bg,
    black: Color(0xFF14171C),
    red: danger,
    green: Color(0xFF4ADE80),
    yellow: Color(0xFFFBBF24),
    blue: accent,
    magenta: Color(0xFFC084FC),
    cyan: Color(0xFF22D3EE),
    white: text,
    brightBlack: subtle,
    brightRed: Color(0xFFFCA5A5),
    brightGreen: Color(0xFF86EFAC),
    brightYellow: Color(0xFFFCD34D),
    brightBlue: Color(0xFFA5B0FF),
    brightMagenta: Color(0xFFD8B4FE),
    brightCyan: Color(0xFF67E8F9),
    brightWhite: Colors.white,
    searchHitBackground: Color(0xFFFBBF24),
    searchHitBackgroundCurrent: Color(0xFF4ADE80),
    searchHitForeground: onAccent,
  );

  static const terminalStyle = TerminalStyle(
    fontSize: 13,
    fontFamily: mono,
    fontFamilyFallback: ['monospace', 'DejaVu Sans Mono', 'Noto Sans Mono'],
  );

  static ThemeData get data {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusSm),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      dividerColor: border,
      hoverColor: hover,
      splashFactory: NoSplash.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.linux: _NoTransition(),
          TargetPlatform.windows: _NoTransition(),
          TargetPlatform.macOS: _NoTransition(),
          TargetPlatform.android: _NoTransition(),
          TargetPlatform.iOS: _NoTransition(),
        },
      ),
      highlightColor: Colors.transparent,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        onPrimary: onAccent,
        surface: surface,
        onSurface: text,
        error: danger,
        outline: border,
      ),
      textTheme: ThemeData.dark().textTheme.apply(
        bodyColor: text,
        displayColor: text,
        fontFamilyFallback: const ['Source Sans 3', 'Noto Sans'],
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: overlay,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: borderStrong),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: input,
        isDense: true,
        labelStyle: const TextStyle(color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: accent),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          shape: shape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: muted, shape: shape),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: onAccent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        shape: shape,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      bannerTheme: const MaterialBannerThemeData(backgroundColor: overlay),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        textStyle: const TextStyle(fontSize: 11.5, color: text),
        decoration: BoxDecoration(
          color: overlay,
          borderRadius: BorderRadius.circular(radiusSm),
          border: Border.all(color: border),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: const WidgetStatePropertyAll(borderStrong),
        radius: const Radius.circular(4),
        thickness: const WidgetStatePropertyAll(6),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: overlay,
        contentTextStyle: const TextStyle(color: text, fontSize: 12.5),
        width: 420,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: border),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        side: const BorderSide(color: borderStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }
}

class _NoTransition extends PageTransitionsBuilder {
  const _NoTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
