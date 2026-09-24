import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import 'host.dart';
import 'ssh.dart';
import 'theme.dart';
import 'ui.dart';
import 'vault.dart';

/// Terminal view with Lumen colours, Ctrl+Shift+C/V and a context menu.
class TerminalPane extends StatefulWidget {
  final Terminal terminal;
  const TerminalPane(this.terminal, {super.key});

  @override
  State<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<TerminalPane> {
  final _controller = TerminalController();

  Future<void> _copy() async {
    final sel = _controller.selection;
    if (sel == null) return;
    await Clipboard.setData(
      ClipboardData(text: widget.terminal.buffer.getText(sel)),
    );
    _controller.clearSelection();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) widget.terminal.paste(data!.text!);
  }

  @override
  Widget build(BuildContext context) => TerminalView(
    widget.terminal,
    controller: _controller,
    autofocus: true,
    theme: L.terminal,
    textStyle: L.terminalStyle,
    padding: const EdgeInsets.all(8),
    onKeyEvent: (_, e) => handleAppShortcut(e),
    shortcuts: {
      const SingleActivator(
        LogicalKeyboardKey.keyC,
        control: true,
        shift: true,
      ): CopySelectionTextIntent.copy,
      const SingleActivator(
        LogicalKeyboardKey.keyV,
        control: true,
        shift: true,
      ): const PasteTextIntent(
        SelectionChangedCause.keyboard,
      ),
    },
    onSecondaryTapDown: (d, _) => showContextMenu(context, d.globalPosition, [
      MenuEntry(
        'Copy',
        _controller.selection == null ? null : _copy,
        icon: Icons.copy,
        hint: 'Ctrl+Shift+C',
      ),
      MenuEntry('Paste', _paste, icon: Icons.paste, hint: 'Ctrl+Shift+V'),
      null,
      MenuEntry('Clear', () {
        widget.terminal.buffer.clear();
        widget.terminal.buffer.setCursor(0, 0);
        widget.terminal.textInput('\x0c');
      }, icon: Icons.clear_all),
    ]),
  );
}

/// Local shell running in a pty.
class LocalTerminal extends StatefulWidget {
  const LocalTerminal({super.key});

  @override
  State<LocalTerminal> createState() => _LocalTerminalState();
}

class _LocalTerminalState extends State<LocalTerminal>
    with AutomaticKeepAliveClientMixin {
  final terminal = Terminal(maxLines: 10000);
  Pty? pty;
  StreamSubscription? _sub;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final shell =
        Platform.environment['SHELL'] ??
        (Platform.isWindows ? 'powershell.exe' : 'bash');
    final p = pty = Pty.start(
      shell,
      columns: terminal.viewWidth,
      rows: terminal.viewHeight,
      workingDirectory: Platform.environment['HOME'],
      environment: {...Platform.environment, 'TERM': 'xterm-256color'},
    );
    _sub = p.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(terminal.write);
    p.exitCode.then((c) => terminal.write('\r\n[process exited with code $c]'));
    terminal.onOutput = (d) => p.write(const Utf8Encoder().convert(d));
    terminal.onResize = (w, h, pw, ph) => p.resize(h, w);
  }

  @override
  void dispose() {
    _sub?.cancel();
    pty?.kill();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return TerminalPane(terminal);
  }
}

enum ConnState { connecting, connected, closed, failed }

/// Interactive SSH shell with reconnect, port forwards and SFTP shortcut.
class SshTerminal extends StatefulWidget {
  final Host host;
  final Vault vault;
  final void Function(Host) onOpenSftp;
  const SshTerminal({
    super.key,
    required this.host,
    required this.vault,
    required this.onOpenSftp,
  });

  @override
  State<SshTerminal> createState() => _SshTerminalState();
}

class _SshTerminalState extends State<SshTerminal>
    with AutomaticKeepAliveClientMixin {
  final terminal = Terminal(maxLines: 10000);
  SshConnection? _conn;
  SSHSession? _session;
  ConnState _state = ConnState.connecting;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _log(String m) => terminal.write(
    '\x1b[90m$m\x1b[0m\r\n'.replaceAll('\n', '\r\n').replaceAll('\r\r', '\r'),
  );

  Future<void> _connect() async {
    _disconnect();
    setState(() => _state = ConnState.connecting);
    final h = widget.host;
    try {
      final conn = _conn = await SshConnection.open(h, widget.vault, log: _log);
      await conn.startForwards(_log);
      final session = _session = await conn.client.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: terminal.viewWidth,
          height: terminal.viewHeight,
        ),
      );
      final decoder = const Utf8Decoder(allowMalformed: true);
      session.stdout
          .cast<List<int>>()
          .transform(decoder)
          .listen(terminal.write);
      session.stderr
          .cast<List<int>>()
          .transform(decoder)
          .listen(terminal.write);
      terminal.onOutput = (d) => session.write(const Utf8Encoder().convert(d));
      terminal.onResize = (w, hh, pw, ph) => session.resizeTerminal(w, hh);
      if (h.startup.isNotEmpty) {
        session.write(const Utf8Encoder().convert('${h.startup}\n'));
      }
      if (mounted) setState(() => _state = ConnState.connected);
      session.done.then((_) {
        if (_session != session) return;
        _log('\nConnection closed.');
        if (mounted) setState(() => _state = ConnState.closed);
      });
    } catch (e) {
      _log('\x1b[31mError: $e');
      if (mounted) setState(() => _state = ConnState.failed);
    }
  }

  void _disconnect() {
    terminal.onOutput = null;
    _session?.close();
    _session = null;
    _conn?.close();
    _conn = null;
  }

  @override
  void dispose() {
    _disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final (color, label) = switch (_state) {
      ConnState.connecting => (L.warn, 'Connecting'),
      ConnState.connected => (L.ok, 'Connected'),
      ConnState.closed => (L.subtle, 'Disconnected'),
      ConnState.failed => (L.danger, 'Failed'),
    };
    final forwards = _conn?.forwards ?? [];
    return Column(
      children: [
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: const BoxDecoration(
            color: L.surface,
            border: Border(bottom: BorderSide(color: L.border)),
          ),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(fontSize: 11.5, color: L.muted),
              ),
              const SizedBox(width: 10),
              Text(
                widget.host.address,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: L.subtle,
                  fontFamily: L.mono,
                ),
              ),
              if (forwards.isNotEmpty) ...[
                const SizedBox(width: 10),
                Tooltip(
                  message: forwards.map((f) => '${f.spec}').join('\n'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: L.accent.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(L.radiusSm),
                    ),
                    child: Text(
                      '${forwards.length} forward(s)',
                      style: const TextStyle(fontSize: 10.5, color: L.accent),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Btn(
                small: true,
                icon: const Icon(Icons.folder_outlined),
                label: 'SFTP',
                onTap: () => widget.onOpenSftp(widget.host),
              ),
              Btn(
                small: true,
                icon: const Icon(Icons.refresh),
                label: 'Reconnect',
                onTap: _state == ConnState.connecting ? null : _connect,
              ),
              Btn(
                small: true,
                variant: BtnVariant.danger,
                icon: const Icon(Icons.power_settings_new),
                tooltip: 'Disconnect',
                onTap: _state == ConnState.connected
                    ? () {
                        _disconnect();
                        _log('\nDisconnected.');
                        setState(() => _state = ConnState.closed);
                      }
                    : null,
              ),
            ],
          ),
        ),
        Expanded(child: TerminalPane(terminal)),
      ],
    );
  }
}
