import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'host.dart';
import 'hosts.dart';
import 'sftp.dart';
import 'terminals.dart';
import 'theme.dart';
import 'ui.dart';
import 'vault.dart';
import 'vault_view.dart';

final _desktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_desktop) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: 'Termex',
        size: Size(1280, 800),
        minimumSize: Size(760, 480),
        center: true,
        backgroundColor: L.bg,
        titleBarStyle: TitleBarStyle.hidden,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  await loadZoom();
  runApp(const TermexApp());
}

/// UI zoom like Lumen's (Ctrl+= / Ctrl+- / Ctrl+0), persisted per device.
final zoom = ValueNotifier<double>(_defaultZoom);
const _defaultZoom = 1.05;

Future<File> _settingsFile() async =>
    File('${(await getApplicationSupportDirectory()).path}/settings.json');

Future<void> loadZoom() async {
  try {
    final j = jsonDecode(await (await _settingsFile()).readAsString());
    zoom.value = (j['zoom'] as num).toDouble();
  } catch (_) {}
}

void setZoom(double z) {
  zoom.value = double.parse(z.clamp(0.7, 2.0).toStringAsFixed(2));
  _settingsFile()
      .then((f) async {
        await f.parent.create(recursive: true);
        await f.writeAsString(jsonEncode({'zoom': zoom.value}));
      })
      .catchError((_) {});
}

/// Lays the app out at `size / zoom` and scales it up, so every pixel
/// value (fonts, paddings, bars) grows together.
class _Zoomed extends StatelessWidget {
  final Widget child;
  const _Zoomed(this.child);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: zoom,
    builder: (context, z, _) {
      final mq = MediaQuery.of(context);
      final size = mq.size / z;
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 0,
          minHeight: 0,
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: Transform.scale(
            scale: z,
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: size,
              child: MediaQuery(
                data: mq.copyWith(
                  size: size,
                  devicePixelRatio: mq.devicePixelRatio * z,
                  padding: mq.padding / z,
                  viewPadding: mq.viewPadding / z,
                  viewInsets: mq.viewInsets / z,
                ),
                child: child,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class TermexApp extends StatelessWidget {
  const TermexApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Termex',
    debugShowCheckedModeBanner: false,
    theme: L.data,
    themeAnimationDuration: Duration.zero,
    navigatorKey: navigatorKey,
    scaffoldMessengerKey: messengerKey,
    builder: (context, child) => _Zoomed(child!),
    home: const Workbench(),
  );
}

class _Tab {
  final String title;
  final IconData icon;
  final Widget child;
  final String? detail;
  final Key key = UniqueKey();
  _Tab(this.title, this.icon, this.child, {this.detail});
}

enum _View { hosts, sync }

class Workbench extends StatefulWidget {
  const Workbench({super.key});

  @override
  State<Workbench> createState() => _WorkbenchState();
}

class _WorkbenchState extends State<Workbench> {
  final vault = Vault();
  final List<_Tab> _tabs = [];
  int _index = 0;
  _View? _view = _View.hosts;
  double _sideWidth = 280;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    vault.init().whenComplete(() => setState(() => _ready = true));
    vault.addListener(() => setState(() {}));
    appShortcuts.addAll({
      const SingleActivator(LogicalKeyboardKey.equal, control: true): () =>
          setZoom(zoom.value + .1),
      const SingleActivator(
        LogicalKeyboardKey.equal,
        control: true,
        shift: true,
      ): () =>
          setZoom(zoom.value + .1),
      const SingleActivator(LogicalKeyboardKey.add, control: true): () =>
          setZoom(zoom.value + .1),
      const SingleActivator(LogicalKeyboardKey.minus, control: true): () =>
          setZoom(zoom.value - .1),
      const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true): () =>
          setZoom(zoom.value + .1),
      const SingleActivator(
        LogicalKeyboardKey.numpadSubtract,
        control: true,
      ): () =>
          setZoom(zoom.value - .1),
      const SingleActivator(LogicalKeyboardKey.digit0, control: true): () =>
          setZoom(_defaultZoom),
      const SingleActivator(
        LogicalKeyboardKey.keyT,
        control: true,
        shift: true,
      ): _newLocal,
      const SingleActivator(
        LogicalKeyboardKey.keyW,
        control: true,
        shift: true,
      ): () =>
          _tabs.isEmpty ? null : _close(_index),
      const SingleActivator(LogicalKeyboardKey.tab, control: true): () =>
          _select(_tabs.isEmpty ? 0 : (_index + 1) % _tabs.length),
      const SingleActivator(
        LogicalKeyboardKey.tab,
        control: true,
        shift: true,
      ): () => _select(
        _tabs.isEmpty ? 0 : (_index - 1 + _tabs.length) % _tabs.length,
      ),
      const SingleActivator(
        LogicalKeyboardKey.keyB,
        control: true,
        shift: true,
      ): () =>
          _toggleView(_View.hosts),
      const SingleActivator(
        LogicalKeyboardKey.keyN,
        control: true,
        shift: true,
      ): () =>
          vault.unlocked ? editHost(vault) : null,
      const SingleActivator(
        LogicalKeyboardKey.keyL,
        control: true,
        shift: true,
      ): () =>
          vault.unlocked ? vault.lock() : null,
    });
  }

  void _select(int i) => setState(() => _index = i);

  void _add(_Tab t) => setState(() {
    _tabs.add(t);
    _index = _tabs.length - 1;
  });

  void _close(int i) => setState(() {
    _tabs.removeAt(i);
    if (_index > i || _index >= _tabs.length) _index--;
    if (_index < 0) _index = 0;
  });

  void _toggleView(_View v) => setState(() => _view = _view == v ? null : v);

  void _newLocal() => _add(
    _Tab(
      'Local',
      Icons.terminal,
      const LocalTerminal(),
      detail: Platform.environment['SHELL'] ?? 'shell',
    ),
  );

  void _ssh(Host h) => _add(
    _Tab(
      h.label,
      Icons.terminal,
      SshTerminal(host: h, vault: vault, onOpenSftp: _sftp),
      detail: 'SSH · ${h.address}',
    ),
  );

  void _sftp(Host h) => _add(
    _Tab(
      h.label,
      Icons.folder_outlined,
      SftpView(
        host: h,
        vault: vault,
        openTab: (title, icon, child) =>
            _add(_Tab(title, icon, child, detail: 'Editor · ${h.label}')),
        openTerminal: (host, dir) => _ssh(
          Host.fromJson({
            ...host.toJson(),
            'startup': "cd '${dir.replaceAll("'", "'\\''")}'",
          }),
        ),
      ),
      detail: 'SFTP · ${h.address}',
    ),
  );

  // ---------------------------------------------------------------- layout

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, e) => handleAppShortcut(e),
        child: Column(
          children: [
            _TitleBar(
              title: [
                if (_tabs.isNotEmpty) _tabs[_index].title,
                'Termex',
              ].join(' — '),
              menus: _menus(),
              sidebarOpen: _view != null,
              onToggleSidebar: () =>
                  setState(() => _view = _view == null ? _View.hosts : null),
            ),
            Expanded(
              child: !_ready
                  ? const SizedBox()
                  : Stack(
                      children: [
                        Row(
                          children: [
                            _navStrip(),
                            if (_view != null) _sideDock(),
                            Expanded(child: _editorArea()),
                          ],
                        ),
                        if (!vault.unlocked)
                          Positioned.fill(child: LockScreen(vault)),
                      ],
                    ),
            ),
            _statusBar(),
          ],
        ),
      ),
    );
  }

  Map<String, List<MenuEntry?>> _menus() => {
    'File': [
      MenuEntry(
        'New Local Terminal',
        _newLocal,
        icon: Icons.terminal,
        hint: 'Ctrl+Shift+T',
      ),
      MenuEntry(
        'New Host…',
        vault.unlocked ? () => editHost(vault) : null,
        icon: Icons.add,
        hint: 'Ctrl+Shift+N',
      ),
      MenuEntry(
        'Import ~/.ssh/config',
        vault.unlocked ? () => importSshConfig(vault) : null,
        icon: Icons.download_outlined,
      ),
      null,
      MenuEntry(
        'Close Tab',
        _tabs.isEmpty ? null : () => _close(_index),
        hint: 'Ctrl+Shift+W',
      ),
      MenuEntry(
        'Close All Tabs',
        _tabs.isEmpty ? null : () => setState(_tabs.clear),
      ),
      null,
      MenuEntry('Quit', () => exit(0)),
    ],
    'View': [
      MenuEntry(
        'Zoom In',
        () => setZoom(zoom.value + .1),
        icon: Icons.zoom_in,
        hint: 'Ctrl+=',
      ),
      MenuEntry(
        'Zoom Out',
        () => setZoom(zoom.value - .1),
        icon: Icons.zoom_out,
        hint: 'Ctrl+-',
      ),
      MenuEntry('Reset Zoom', () => setZoom(_defaultZoom), hint: 'Ctrl+0'),
      null,
      MenuEntry(
        'Hosts',
        () => _toggleView(_View.hosts),
        icon: Icons.dns_outlined,
        hint: 'Ctrl+Shift+B',
      ),
      MenuEntry(
        'Vault & Sync',
        () => _toggleView(_View.sync),
        icon: Icons.cloud_outlined,
      ),
      null,
      MenuEntry(
        'Next Tab',
        _tabs.length < 2 ? null : () => _select((_index + 1) % _tabs.length),
        hint: 'Ctrl+Tab',
      ),
      MenuEntry(
        'Previous Tab',
        _tabs.length < 2
            ? null
            : () => _select((_index - 1 + _tabs.length) % _tabs.length),
        hint: 'Ctrl+Shift+Tab',
      ),
    ],
    'Vault': [
      MenuEntry(
        'Lock',
        vault.unlocked ? vault.lock : null,
        icon: Icons.lock_outline,
        hint: 'Ctrl+Shift+L',
      ),
      MenuEntry(
        'Sync Now',
        vault.unlocked && vault.serverUrl != null
            ? () async => toast(await vault.sync())
            : null,
        icon: Icons.sync,
      ),
      MenuEntry(
        'Sync Settings…',
        vault.unlocked ? () => setState(() => _view = _View.sync) : null,
        icon: Icons.cloud_outlined,
      ),
    ],
    'Help': [
      MenuEntry('Keyboard Shortcuts', _showShortcuts, icon: Icons.keyboard),
      MenuEntry(
        'About Termex',
        () => showAboutDialog(
          context: context,
          applicationName: 'Termex',
          applicationVersion: '0.2.0',
          applicationLegalese: 'SSH & SFTP client with encrypted vault sync',
        ),
        icon: Icons.info_outline,
      ),
    ],
  };

  void _showShortcuts() => showDialog(
    animationStyle: AnimationStyle.noAnimation,
    context: context,
    builder: (ctx) => LDialog(
      title: 'Keyboard shortcuts',
      width: 420,
      child: Column(
        children: [
          for (final (k, v) in const [
            ('Ctrl+Shift+T', 'New local terminal'),
            ('Ctrl+Shift+W', 'Close tab'),
            ('Ctrl+Tab / Ctrl+Shift+Tab', 'Next / previous tab'),
            ('Ctrl+Shift+B', 'Toggle hosts sidebar'),
            ('Ctrl+Shift+N', 'New host'),
            ('Ctrl+Shift+L', 'Lock vault'),
            ('Ctrl+Shift+C / V', 'Copy / paste in terminal'),
            ('Ctrl+S', 'Save file in editor'),
            (
              'Del · F2 · F5 · Enter · Backspace',
              'Delete · rename · refresh · open · up (SFTP)',
            ),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      v,
                      style: const TextStyle(fontSize: 12.5, color: L.muted),
                    ),
                  ),
                  Text(
                    k,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontFamily: L.mono,
                      color: L.text,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Widget _navStrip() {
    Widget item(IconData icon, String tip, bool active, VoidCallback onTap) =>
        _NavButton(icon: icon, tooltip: tip, active: active, onTap: onTap);
    return Container(
      width: 44,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        color: L.surface,
        border: Border(right: BorderSide(color: L.border)),
      ),
      child: Column(
        children: [
          item(
            Icons.dns_outlined,
            'Hosts',
            _view == _View.hosts,
            () => _toggleView(_View.hosts),
          ),
          item(
            Icons.cloud_outlined,
            'Vault & Sync',
            _view == _View.sync,
            () => _toggleView(_View.sync),
          ),
          const Spacer(),
          item(Icons.terminal, 'New local terminal', false, _newLocal),
          item(Icons.lock_outline, 'Lock vault', false, vault.lock),
        ],
      ),
    );
  }

  Widget _sideDock() {
    final (title, actions, child) = switch (_view!) {
      _View.hosts => (
        'Hosts',
        [
          Btn(
            small: true,
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Import ~/.ssh/config',
            onTap: () => importSshConfig(vault),
          ),
          Btn(
            small: true,
            icon: const Icon(Icons.add),
            tooltip: 'New host (Ctrl+Shift+N)',
            onTap: () => editHost(vault),
          ),
        ],
        HostsView(vault: vault, onSsh: _ssh, onSftp: _sftp) as Widget,
      ),
      _View.sync => ('Vault & Sync', <Widget>[], SyncView(vault)),
    };
    return Row(
      children: [
        Container(
          width: _sideWidth,
          color: L.surface,
          child: Column(
            children: [
              SizedBox(
                height: 32,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  child: Row(
                    children: [
                      Expanded(child: Caption(title)),
                      ...actions,
                    ],
                  ),
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
        // Resize handle
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => setState(
              () => _sideWidth = (_sideWidth + d.delta.dx).clamp(200.0, 520.0),
            ),
            child: Container(
              width: 4,
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: L.border)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _editorArea() {
    if (_tabs.isEmpty) return _welcome();
    return Column(
      children: [
        Container(
          height: 36,
          decoration: const BoxDecoration(
            color: L.surface,
            border: Border(bottom: BorderSide(color: L.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < _tabs.length; i++)
                      _TabButton(
                        tab: _tabs[i],
                        active: i == _index,
                        onTap: () => _select(i),
                        onClose: () => _close(i),
                        onMenu: (p) => showContextMenu(context, p, [
                          MenuEntry(
                            'Close',
                            () => _close(i),
                            hint: 'Ctrl+Shift+W',
                          ),
                          MenuEntry(
                            'Close Others',
                            _tabs.length < 2
                                ? null
                                : () => setState(() {
                                    final keep = _tabs[i];
                                    _tabs
                                      ..clear()
                                      ..add(keep);
                                    _index = 0;
                                  }),
                          ),
                          MenuEntry('Close All', () => setState(_tabs.clear)),
                        ]),
                      ),
                  ],
                ),
              ),
              Btn(
                small: true,
                icon: const Icon(Icons.add),
                tooltip: 'New local terminal (Ctrl+Shift+T)',
                onTap: _newLocal,
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _index,
            children: [
              for (final t in _tabs) KeyedSubtree(key: t.key, child: t.child),
            ],
          ),
        ),
      ],
    );
  }

  Widget _welcome() => Center(
    child: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.terminal, size: 40, color: L.accent),
          const SizedBox(height: 12),
          const Text(
            'Termex',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            'SSH & SFTP with an encrypted, synced vault',
            style: TextStyle(fontSize: 12.5, color: L.muted),
          ),
          const SizedBox(height: 24),
          for (final (icon, label, hint, onTap) in [
            (Icons.terminal, 'New local terminal', 'Ctrl+Shift+T', _newLocal),
            (Icons.add, 'Add a host', 'Ctrl+Shift+N', () => editHost(vault)),
            (
              Icons.download_outlined,
              'Import ~/.ssh/config',
              '',
              () => importSshConfig(vault),
            ),
            (
              Icons.cloud_outlined,
              'Set up sync',
              '',
              () => setState(() => _view = _View.sync),
            ),
          ])
            HoverRow(
              onTap: onTap,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: L.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(label, style: const TextStyle(fontSize: 13)),
                  ),
                  Text(
                    hint,
                    style: const TextStyle(fontSize: 11, color: L.subtle),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Widget _statusBar() {
    final tab = _tabs.isEmpty ? null : _tabs[_index];
    const style = TextStyle(fontSize: 11, color: L.subtle);
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: L.surface,
        border: Border(top: BorderSide(color: L.border)),
      ),
      child: Row(
        children: [
          Icon(
            vault.unlocked ? Icons.lock_open : Icons.lock_outline,
            size: 11,
            color: vault.unlocked ? L.ok : L.subtle,
          ),
          const SizedBox(width: 4),
          Text(
            vault.unlocked ? 'Vault unlocked' : 'Vault locked',
            style: style,
          ),
          if (vault.unlocked) ...[
            const SizedBox(width: 12),
            Text('${vault.hosts.length} hosts', style: style),
          ],
          if (vault.serverUrl != null) ...[
            const SizedBox(width: 12),
            const Icon(Icons.cloud_outlined, size: 11, color: L.subtle),
            const SizedBox(width: 4),
            Text(vault.syncStatus ?? 'Sync configured', style: style),
          ],
          const Spacer(),
          if (tab?.detail != null) Text(tab!.detail!, style: style),
          const SizedBox(width: 12),
          Text(
            '${_tabs.length} tab${_tabs.length == 1 ? '' : 's'}',
            style: style,
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;
  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.tooltip,
    preferBelow: false,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          height: 38,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (widget.active)
                Positioned(
                  left: 0,
                  child: Container(
                    width: 2,
                    height: 16,
                    decoration: BoxDecoration(
                      color: L.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _hover && !widget.active ? L.hover : null,
                  borderRadius: BorderRadius.circular(L.radius),
                ),
                child: Icon(
                  widget.icon,
                  size: 18,
                  color: widget.active
                      ? L.accent
                      : (_hover ? L.text : L.subtle),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TabButton extends StatefulWidget {
  final _Tab tab;
  final bool active;
  final VoidCallback onTap, onClose;
  final void Function(Offset) onMenu;
  const _TabButton({
    required this.tab,
    required this.active,
    required this.onTap,
    required this.onClose,
    required this.onMenu,
  });

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.active;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        // Middle click closes, like in Lumen.
        onPointerDown: (e) {
          if (e.buttons == kMiddleMouseButton) widget.onClose();
        },
        child: GestureDetector(
          onTap: widget.onTap,
          onSecondaryTapDown: (d) => widget.onMenu(d.globalPosition),
          child: Container(
            constraints: const BoxConstraints(minWidth: 110, maxWidth: 220),
            padding: const EdgeInsets.only(left: 12, right: 6),
            margin: const EdgeInsets.only(right: 1),
            decoration: BoxDecoration(
              color: a ? L.bg : (_hover ? L.hover : null),
              border: Border(
                top: BorderSide(
                  width: 2,
                  color: a ? L.accent : Colors.transparent,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.tab.icon, size: 13, color: a ? L.accent : L.subtle),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    widget.tab.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: a ? L.text : (_hover ? L.muted : L.subtle),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Opacity(
                  opacity: a || _hover ? 1 : 0,
                  child: Btn(
                    small: true,
                    icon: const Icon(Icons.close, size: 12),
                    onTap: widget.onClose,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lumen title bar: menu bar left, title centre, window buttons right.
class _TitleBar extends StatelessWidget {
  final String title;
  final Map<String, List<MenuEntry?>> menus;
  final bool sidebarOpen;
  final VoidCallback onToggleSidebar;
  const _TitleBar({
    required this.title,
    required this.menus,
    required this.sidebarOpen,
    required this.onToggleSidebar,
  });

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: L.surface,
        border: Border(bottom: BorderSide(color: L.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.terminal, size: 16, color: L.accent),
          const SizedBox(width: 6),
          for (final m in menus.entries) _MenuButton(m.key, m.value),
          Container(
            width: 1,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            color: L.border,
          ),
          Expanded(
            child: Center(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: L.subtle),
              ),
            ),
          ),
          Btn(
            small: true,
            active: sidebarOpen,
            icon: const Icon(Icons.view_sidebar_outlined),
            tooltip: 'Toggle sidebar (Ctrl+Shift+B)',
            onTap: onToggleSidebar,
          ),
          if (_desktop) ...[
            const SizedBox(width: 4),
            _WindowButton(Icons.remove, 'Minimize', windowManager.minimize),
            _WindowButton(Icons.crop_square, 'Maximize', () async {
              await windowManager.isMaximized()
                  ? windowManager.unmaximize()
                  : windowManager.maximize();
            }),
            _WindowButton(
              Icons.close,
              'Close',
              windowManager.close,
              danger: true,
            ),
          ],
        ],
      ),
    );
    return _desktop ? DragToMoveArea(child: bar) : bar;
  }
}

class _MenuButton extends StatelessWidget {
  final String label;
  final List<MenuEntry?> entries;
  const _MenuButton(this.label, this.entries);

  @override
  Widget build(BuildContext context) => Builder(
    builder: (ctx) => HoverRow(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      onTap: () {
        final box = ctx.findRenderObject() as RenderBox;
        showContextMenu(
          ctx,
          box.localToGlobal(Offset(0, box.size.height + 4)),
          entries,
        );
      },
      child: Text(label, style: const TextStyle(fontSize: 12, color: L.muted)),
    ),
  );
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  const _WindowButton(this.icon, this.label, this.onTap, {this.danger = false});

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: Tooltip(
        message: widget.label,
        child: Container(
          width: 40,
          height: 28,
          decoration: BoxDecoration(
            color: _hover
                ? (widget.danger ? L.danger : L.hover)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(L.radiusSm),
          ),
          child: Icon(
            widget.icon,
            size: 14,
            color: _hover ? (widget.danger ? Colors.white : L.text) : L.muted,
          ),
        ),
      ),
    ),
  );
}
