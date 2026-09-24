import 'dart:convert';
import 'dart:io';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

class TerminalSession {
  TerminalSession({
    String? shell,
    this.title = 'terminal',
    int maxLines = 10000,
  }) : terminal = Terminal(maxLines: maxLines),
       _shell = shell ?? _defaultShell();

  final Terminal terminal;
  final String title;
  final String _shell;

  Pty? _pty;
  bool _disposed = false;

  static String _defaultShell() {
    if (Platform.isMacOS || Platform.isLinux) {
      return Platform.environment['SHELL'] ?? '/bin/bash';
    }
    if (Platform.isWindows) return 'cmd.exe';
    return '/bin/sh';
  }

  void start({int columns = 80, int rows = 24}) {
    _pty = Pty.start(
      _shell,
      arguments: ['-i', '-l'],
      columns: columns,
      rows: rows,
      environment: {
        ...Platform.environment,
        'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
      },
    );

    _pty!.output.cast<List<int>>().listen(
      (data) => terminal.write(String.fromCharCodes(data)),
    );

    terminal.onOutput = (data) => _pty!.write(utf8.encode(data));

    _pty!.exitCode.then((_) {
      if (!_disposed) terminal.write('\r\n[process exited]\r\n');
    });
  }

  void resize(int columns, int rows) => _pty?.resize(columns, rows);

  void dispose() {
    _disposed = true;
    _pty?.kill();
  }
}
