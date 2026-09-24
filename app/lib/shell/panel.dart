import 'package:flutter/material.dart';
import 'package:termex/shell/session.dart';
import 'package:termex/shell/theme.dart';
import 'package:termex/shell/widget.dart';
import 'package:xterm/xterm.dart';

class TerminalPanel extends StatelessWidget {
  const TerminalPanel({
    super.key,
    required this.session,
    this.title = 'terminal',
    this.theme = TerminalColorThemes.dark,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.onClose,
    this.onMinimize,
    this.onMaximize,
  });

  final TerminalSession session;
  final String title;
  final TerminalTheme theme;
  final BorderRadius borderRadius;
  final VoidCallback? onClose;
  final VoidCallback? onMinimize;
  final VoidCallback? onMaximize;

  // Note: title, onClose, onMinimize, onMaximize are kept for backwards compatibility
  // but are no longer used in the UI

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117),
          borderRadius: borderRadius,
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        child: TerminalWidget(
          session: session,
          theme: theme,
          padding: const EdgeInsets.all(6),
        ),
      ),
    );
  }
}
