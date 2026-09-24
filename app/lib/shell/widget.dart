import 'package:flutter/material.dart';
import 'package:termex/shell/session.dart';
import 'package:termex/shell/theme.dart';
import 'package:xterm/xterm.dart';

class TerminalWidget extends StatefulWidget {
  const TerminalWidget({
    super.key,
    required this.session,
    this.theme = TerminalColorThemes.dark,
    this.padding = const EdgeInsets.all(0),
    this.autoStart = false,
    this.textStyle,
    this.onResize,
  });

  final TerminalSession session;
  final TerminalTheme theme;
  final EdgeInsets padding;

  final bool autoStart;

  final TerminalStyle? textStyle;

  final void Function(int columns, int rows)? onResize;

  @override
  State<TerminalWidget> createState() => _TerminalWidgetState();
}

class _TerminalWidgetState extends State<TerminalWidget> {
  late final TerminalController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TerminalController();
    _focusNode = FocusNode();
    if (widget.autoStart) widget.session.start();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    if (widget.autoStart) widget.session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding,
      child: TerminalView(
        widget.session.terminal,
        controller: _controller,
        theme: widget.theme,
        textStyle:
            widget.textStyle ??
            const TerminalStyle(fontFamily: 'JetBrains Mono', fontSize: 13),
        autofocus: true,
        focusNode: _focusNode,
      ),
    );
  }
}
