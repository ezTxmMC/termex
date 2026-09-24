import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fs.dart';
import 'host.dart';
import 'ssh.dart';
import 'theme.dart';
import 'ui.dart';
import 'vault.dart';

typedef OpenTab = void Function(String title, IconData icon, Widget child);

/// Two-pane file manager: local on the left, the server on the right.
class SftpView extends StatefulWidget {
  final Host host;
  final Vault vault;
  final OpenTab openTab;
  final void Function(Host host, String dir) openTerminal;
  const SftpView({
    super.key,
    required this.host,
    required this.vault,
    required this.openTab,
    required this.openTerminal,
  });

  @override
  State<SftpView> createState() => _SftpViewState();
}

class _SftpViewState extends State<SftpView>
    with AutomaticKeepAliveClientMixin {
  SshConnection? _conn;
  RemoteFs? _remote;
  TransferQueue? _queue;
  final _local = LocalFs();
  final _localKey = GlobalKey<FilePaneState>();
  final _remoteKey = GlobalKey<FilePaneState>();
  final _log = <String>[];
  String? _error;
  bool _showTransfers = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    _close();
    setState(() {
      _error = null;
      _log.clear();
    });
    try {
      final conn = await SshConnection.open(
        widget.host,
        widget.vault,
        log: (m) => mounted ? setState(() => _log.add(m)) : null,
      );
      final sftp = await conn.sftp();
      final remote = RemoteFs(sftp, widget.host.label);
      final queue = TransferQueue(_local, remote)
        ..onFinished = (t) {
          (t.upload ? _remoteKey : _localKey).currentState?.refresh();
          if (t.state == TransferState.failed) {
            toast('Transfer of ${t.source.name} failed: ${t.error}');
          }
        };
      if (!mounted) return conn.close();
      setState(() {
        _conn = conn;
        _remote = remote;
        _queue = queue;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _close() {
    for (final t in _queue?.items ?? <Transfer>[]) {
      t.cancel();
    }
    _conn?.close();
    _conn = null;
    _remote = null;
    _queue = null;
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  void _transfer(bool upload, List<Entry> entries) {
    final q = _queue;
    final target = (upload ? _remoteKey : _localKey).currentState?.path;
    if (q == null || target == null) return;
    for (final e in entries) {
      q.add(Transfer(upload, e, target));
    }
    setState(() => _showTransfers = true);
  }

  void _edit(Fs fs, Entry e) {
    if (e.size > 5 * 1024 * 1024) {
      toast('${e.name} is too large to edit (${formatBytes(e.size)})');
      return;
    }
    widget.openTab(
      e.name,
      Icons.description_outlined,
      FileEditor(fs: fs, path: e.path, origin: fs.label),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final remote = _remote;
    if (remote == null) {
      return _error != null
          ? EmptyState(
              icon: Icons.error_outline,
              title: 'Could not open SFTP on ${widget.host.label}',
              hint: _error,
              action: Btn(
                label: 'Retry',
                variant: BtnVariant.outline,
                icon: const Icon(Icons.refresh),
                onTap: _connect,
              ),
            )
          : EmptyState(
              icon: Icons.sync,
              title: 'Connecting to ${widget.host.label}…',
              hint: _log.isEmpty ? null : _log.last,
            );
    }
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: FilePane(
                  key: _localKey,
                  fs: _local,
                  icon: Icons.computer,
                  sendLabel: 'Upload',
                  onSend: (e) => _transfer(true, e),
                  onEdit: (e) => _edit(_local, e),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: FilePane(
                  key: _remoteKey,
                  fs: remote,
                  icon: Icons.dns_outlined,
                  sendLabel: 'Download',
                  onSend: (e) => _transfer(false, e),
                  onEdit: (e) => _edit(remote, e),
                  onTerminal: (dir) => widget.openTerminal(widget.host, dir),
                ),
              ),
            ],
          ),
        ),
        _TransfersPanel(
          queue: _queue!,
          open: _showTransfers,
          onToggle: () => setState(() => _showTransfers = !_showTransfers),
        ),
      ],
    );
  }
}

class _Drag {
  final Fs fs;
  final List<Entry> entries;
  _Drag(this.fs, this.entries);
}

enum _Sort { name, size, modified }

class FilePane extends StatefulWidget {
  final Fs fs;
  final IconData icon;
  final String sendLabel;
  final void Function(List<Entry>) onSend;
  final void Function(Entry) onEdit;
  final void Function(String dir)? onTerminal;

  const FilePane({
    super.key,
    required this.fs,
    required this.icon,
    required this.sendLabel,
    required this.onSend,
    required this.onEdit,
    this.onTerminal,
  });

  @override
  State<FilePane> createState() => FilePaneState();
}

class FilePaneState extends State<FilePane> {
  String path = '';
  List<Entry> _entries = [];
  final Set<String> _selected = {};
  int? _anchor;
  bool _loading = true;
  String? _error;
  bool _hidden = false;
  _Sort _sort = _Sort.name;
  bool _asc = true;
  bool _dropHover = false;
  final _pathCtl = TextEditingController();
  final _focus = FocusNode();

  Fs get fs => widget.fs;

  @override
  void initState() {
    super.initState();
    fs.home().then(_go).catchError((Object e) => _go(fs.sep));
  }

  List<Entry> get _visible {
    final list = _entries
        .where((e) => _hidden || !e.name.startsWith('.'))
        .toList();
    int cmp(Entry a, Entry b) => switch (_sort) {
      _Sort.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      _Sort.size => a.size.compareTo(b.size),
      _Sort.modified => (a.modified ?? DateTime(0)).compareTo(
        b.modified ?? DateTime(0),
      ),
    };
    list.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return _asc ? cmp(a, b) : cmp(b, a);
    });
    return list;
  }

  List<Entry> get selection =>
      _visible.where((e) => _selected.contains(e.path)).toList();

  Future<void> _go(String dir) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await fs.list(dir);
      if (!mounted) return;
      setState(() {
        path = dir;
        _pathCtl.text = dir;
        _entries = list;
        _selected.clear();
        _anchor = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _pathCtl.text = path;
      });
    }
  }

  Future<void> refresh() => _go(path);

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      toast('$e');
    }
    await refresh();
  }

  void _open(Entry e) => e.isDir ? _go(e.path) : widget.onEdit(e);

  void _click(int i, List<Entry> list) {
    final keys = HardwareKeyboard.instance;
    final e = list[i];
    setState(() {
      if (keys.isShiftPressed && _anchor != null) {
        final a = _anchor!.clamp(0, list.length - 1);
        _selected
          ..clear()
          ..addAll([
            for (var j = a < i ? a : i; j <= (a < i ? i : a); j++) list[j].path,
          ]);
      } else if (keys.isControlPressed || keys.isMetaPressed) {
        _selected.contains(e.path)
            ? _selected.remove(e.path)
            : _selected.add(e.path);
        _anchor = i;
      } else {
        _selected
          ..clear()
          ..add(e.path);
        _anchor = i;
      }
    });
    _focus.requestFocus();
  }

  Future<void> _newFolder() async {
    final n = await prompt('New folder', label: 'Name', ok: 'Create');
    if (n == null || n.trim().isEmpty) return;
    await _run(() => fs.mkdir(fs.join(path, n.trim())));
  }

  Future<void> _newFile() async {
    final n = await prompt('New file', label: 'Name', ok: 'Create');
    if (n == null || n.trim().isEmpty) return;
    final p = fs.join(path, n.trim());
    await _run(() => fs.writeBytes(p, Uint8List(0)));
    widget.onEdit(Entry(name: n.trim(), path: p, isDir: false));
  }

  Future<void> _rename(Entry e) async {
    final n = await prompt(
      'Rename',
      label: 'New name',
      initial: e.name,
      ok: 'Rename',
    );
    if (n == null || n.trim().isEmpty || n == e.name) return;
    await _run(() => fs.rename(e.path, fs.join(path, n.trim())));
  }

  Future<void> _delete(List<Entry> list) async {
    if (list.isEmpty) return;
    final what = list.length == 1
        ? '"${list.first.name}"'
        : '${list.length} items';
    final hasDir = list.any((e) => e.isDir && !e.isLink);
    if (!await confirm(
      'Delete $what?',
      'This cannot be undone.${hasDir ? '\nFolders are deleted with all their contents.' : ''}',
      ok: 'Delete',
      danger: true,
    )) {
      return;
    }
    await _run(() async {
      for (final e in list) {
        await fs.delete(e);
      }
    });
  }

  Future<void> _chmod(Entry e) async {
    final m = await showDialog<int>(
      animationStyle: AnimationStyle.noAnimation,
      context: context,
      builder: (_) => _ChmodDialog(entry: e),
    );
    if (m != null) await _run(() => fs.chmod(e.path, m));
  }

  void _menu(Offset pos, Entry? e) {
    final sel = selection;
    showContextMenu(context, pos, [
      if (e != null) ...[
        MenuEntry(
          e.isDir ? 'Open' : 'Edit',
          () => _open(e),
          icon: e.isDir ? Icons.folder_open : Icons.edit_outlined,
          hint: 'Enter',
        ),
        MenuEntry(
          '${widget.sendLabel}${sel.length > 1 ? ' ${sel.length} items' : ''}',
          () => widget.onSend(sel),
          icon: widget.sendLabel == 'Upload'
              ? Icons.upload_outlined
              : Icons.download_outlined,
        ),
        null,
        MenuEntry(
          'Rename…',
          sel.length == 1 ? () => _rename(e) : null,
          icon: Icons.drive_file_rename_outline,
          hint: 'F2',
        ),
        MenuEntry(
          'Permissions…',
          e.mode == null ? null : () => _chmod(e),
          icon: Icons.lock_outline,
        ),
        MenuEntry(
          'Copy path',
          () => Clipboard.setData(ClipboardData(text: e.path)),
          icon: Icons.content_copy,
        ),
        if (widget.onTerminal != null)
          MenuEntry(
            'Open terminal here',
            () => widget.onTerminal!(e.isDir ? e.path : path),
            icon: Icons.terminal,
          ),
        null,
        MenuEntry(
          'Delete',
          () => _delete(sel),
          icon: Icons.delete_outline,
          hint: 'Del',
          danger: true,
        ),
        null,
      ],
      MenuEntry(
        'New folder…',
        _newFolder,
        icon: Icons.create_new_folder_outlined,
      ),
      MenuEntry('New file…', _newFile, icon: Icons.note_add_outlined),
      MenuEntry('Refresh', refresh, icon: Icons.refresh, hint: 'F5'),
      if (e == null && widget.onTerminal != null)
        MenuEntry(
          'Open terminal here',
          () => widget.onTerminal!(path),
          icon: Icons.terminal,
        ),
    ]);
  }

  Widget _header(String label, _Sort? s, {double? width, bool right = false}) {
    final active = s != null && _sort == s;
    final text = Row(
      mainAxisAlignment: right
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        Flexible(child: Caption(label)),
        if (active)
          Icon(
            _asc ? Icons.arrow_upward : Icons.arrow_downward,
            size: 11,
            color: L.subtle,
          ),
      ],
    );
    final cell = GestureDetector(
      onTap: s == null
          ? null
          : () => setState(() {
              _asc = _sort == s ? !_asc : true;
              _sort = s;
            }),
      child: MouseRegion(
        cursor: s == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: text,
      ),
    );
    return width == null
        ? Expanded(child: cell)
        : SizedBox(width: width, child: cell);
  }

  Widget _row(Entry e, int i, List<Entry> list) {
    final selected = _selected.contains(e.path);
    final icon = e.isDir
        ? (e.isLink ? Icons.folder_special_outlined : Icons.folder)
        : (e.isLink ? Icons.link : Icons.insert_drive_file_outlined);
    const small = TextStyle(fontSize: 11.5, color: L.subtle);
    final row = HoverRow(
      selected: selected,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      radius: 4,
      onTap: () => _click(i, list),
      onDoubleTap: () => _open(e),
      onContextMenu: (p) {
        if (!selected) _click(i, list);
        _menu(p, e);
      },
      child: Row(
        children: [
          Icon(icon, size: 15, color: e.isDir ? L.accent : L.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              e.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: e.name.startsWith('.') ? L.muted : L.text,
              ),
            ),
          ),
          SizedBox(
            width: 72,
            child: Text(
              e.isDir ? '' : formatBytes(e.size),
              textAlign: TextAlign.right,
              style: small,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(width: 116, child: Text(_date(e.modified), style: small)),
          SizedBox(
            width: 82,
            child: Text(
              e.perms,
              style: small.copyWith(fontFamily: L.mono, fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
    return Draggable<_Drag>(
      data: _Drag(fs, selected ? selection : [e]),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () {
        if (!selected) _click(i, list);
      },
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: L.overlay,
            borderRadius: BorderRadius.circular(L.radiusSm),
            border: Border.all(color: L.accent),
          ),
          child: Text(
            selected && _selected.length > 1
                ? '${_selected.length} items'
                : e.name,
            style: const TextStyle(fontSize: 12, color: L.text),
          ),
        ),
      ),
      child: row,
    );
  }

  static String _date(DateTime? d) {
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final list = _visible;
    return DragTarget<_Drag>(
      onWillAcceptWithDetails: (d) {
        final ok = d.data.fs != fs;
        if (ok) setState(() => _dropHover = true);
        return ok;
      },
      onLeave: (_) => setState(() => _dropHover = false),
      onAcceptWithDetails: (d) {
        setState(() => _dropHover = false);
        // The other pane sends its entries here.
        (context.findAncestorStateOfType<_SftpViewState>())?._transfer(
          fs is RemoteFs,
          d.data.entries,
        );
      },
      builder: (context, _, _) => Container(
        foregroundDecoration: _dropHover
            ? BoxDecoration(
                color: L.accent.withValues(alpha: .08),
                border: Border.all(color: L.accent, width: 2),
                borderRadius: BorderRadius.circular(L.radius),
              )
            : null,
        child: Column(
          children: [
            // Toolbar
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: const BoxDecoration(
                color: L.surface,
                border: Border(bottom: BorderSide(color: L.border)),
              ),
              child: Row(
                children: [
                  Icon(widget.icon, size: 14, color: L.accent),
                  const SizedBox(width: 6),
                  Text(
                    fs.label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Btn(
                    small: true,
                    icon: const Icon(Icons.arrow_upward),
                    tooltip: 'Parent folder (Backspace)',
                    onTap: () => _go(fs.parent(path)),
                  ),
                  Btn(
                    small: true,
                    icon: const Icon(Icons.home_outlined),
                    tooltip: 'Home',
                    onTap: () async => _go(await fs.home()),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: SizedBox(
                      height: 26,
                      child: TextField(
                        controller: _pathCtl,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: L.mono,
                        ),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                        ),
                        onSubmitted: (p) => _go(p.trim()),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Btn(
                    small: true,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    tooltip: 'New folder',
                    onTap: _newFolder,
                  ),
                  Btn(
                    small: true,
                    icon: Icon(
                      _hidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    active: _hidden,
                    tooltip: 'Show hidden files',
                    onTap: () => setState(() => _hidden = !_hidden),
                  ),
                  Btn(
                    small: true,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh (F5)',
                    onTap: refresh,
                  ),
                  Btn(
                    small: true,
                    icon: Icon(
                      widget.sendLabel == 'Upload'
                          ? Icons.upload_outlined
                          : Icons.download_outlined,
                    ),
                    label: widget.sendLabel,
                    onTap: _selected.isEmpty
                        ? null
                        : () => widget.onSend(selection),
                  ),
                ],
              ),
            ),
            // Column headers
            Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: L.border)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 23),
                  _header('Name', _Sort.name),
                  _header('Size', _Sort.size, width: 72, right: true),
                  const SizedBox(width: 12),
                  _header('Modified', _Sort.modified, width: 116),
                  _header('Mode', null, width: 82),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _error != null
                  ? EmptyState(
                      icon: Icons.error_outline,
                      title: 'Cannot open this folder',
                      hint: _error,
                      action: Btn(
                        label: 'Back',
                        variant: BtnVariant.outline,
                        onTap: () => _go(path.isEmpty ? fs.sep : path),
                      ),
                    )
                  : CallbackShortcuts(
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.delete): () =>
                            _delete(selection),
                        const SingleActivator(LogicalKeyboardKey.f2): () {
                          if (selection.length == 1) _rename(selection.first);
                        },
                        const SingleActivator(LogicalKeyboardKey.f5): refresh,
                        const SingleActivator(LogicalKeyboardKey.enter): () {
                          if (selection.length == 1) _open(selection.first);
                        },
                        const SingleActivator(
                          LogicalKeyboardKey.backspace,
                        ): () =>
                            _go(fs.parent(path)),
                        const SingleActivator(
                          LogicalKeyboardKey.keyA,
                          control: true,
                        ): () => setState(
                          () => _selected
                            ..clear()
                            ..addAll(list.map((e) => e.path)),
                        ),
                      },
                      child: Focus(
                        focusNode: _focus,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            setState(_selected.clear);
                            _focus.requestFocus();
                          },
                          onSecondaryTapDown: (d) =>
                              _menu(d.globalPosition, null),
                          child: list.isEmpty
                              ? const EmptyState(
                                  icon: Icons.folder_open,
                                  title: 'This folder is empty',
                                  hint: 'Drop files here to transfer them.',
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.all(6),
                                  itemCount: list.length,
                                  itemExtent: 27,
                                  itemBuilder: (_, i) => _row(list[i], i, list),
                                ),
                        ),
                      ),
                    ),
            ),
            Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.centerLeft,
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: L.border)),
              ),
              child: Text(
                '${list.length} items'
                '${_selected.isEmpty ? '' : ' · ${_selected.length} selected · '
                          '${formatBytes(selection.fold<int>(0, (s, e) => s + (e.isDir ? 0 : e.size)))}'}',
                style: const TextStyle(fontSize: 11, color: L.subtle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChmodDialog extends StatefulWidget {
  final Entry entry;
  const _ChmodDialog({required this.entry});

  @override
  State<_ChmodDialog> createState() => _ChmodDialogState();
}

class _ChmodDialogState extends State<_ChmodDialog> {
  late int _mode = widget.entry.mode ?? 0x1a4;
  late final _octal = TextEditingController(text: _mode.toRadixString(8));

  void _set(int m) => setState(() {
    _mode = m;
    _octal.text = m.toRadixString(8).padLeft(3, '0');
  });

  @override
  Widget build(BuildContext context) {
    Widget cell(int bit) => Checkbox(
      value: _mode & (1 << bit) != 0,
      onChanged: (v) => _set(v! ? _mode | (1 << bit) : _mode & ~(1 << bit)),
    );
    const style = TextStyle(fontSize: 12.5, color: L.muted);
    return LDialog(
      title: 'Permissions of ${widget.entry.name}',
      width: 380,
      actions: [
        Btn(label: 'Cancel', onTap: () => Navigator.pop(context)),
        Btn(
          label: 'Apply',
          variant: BtnVariant.solid,
          onTap: () => Navigator.pop(context, _mode),
        ),
      ],
      child: Column(
        children: [
          Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              const TableRow(
                children: [
                  SizedBox(),
                  Center(child: Caption('Read')),
                  Center(child: Caption('Write')),
                  Center(child: Caption('Exec')),
                ],
              ),
              for (final (i, who) in ['Owner', 'Group', 'Others'].indexed)
                TableRow(
                  children: [
                    Text(who, style: style),
                    cell(8 - i * 3),
                    cell(7 - i * 3),
                    cell(6 - i * 3),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _octal,
            style: const TextStyle(fontFamily: L.mono, fontSize: 12.5),
            decoration: const InputDecoration(labelText: 'Octal'),
            onChanged: (v) {
              final m = int.tryParse(v, radix: 8);
              if (m != null && m <= 0x1ff) setState(() => _mode = m);
            },
          ),
        ],
      ),
    );
  }
}

class _TransfersPanel extends StatelessWidget {
  final TransferQueue queue;
  final bool open;
  final VoidCallback onToggle;
  const _TransfersPanel({
    required this.queue,
    required this.open,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: queue,
    builder: (_, _) {
      final active = queue.items
          .where(
            (t) =>
                t.state == TransferState.running ||
                t.state == TransferState.queued,
          )
          .length;
      return Container(
        decoration: const BoxDecoration(
          color: L.surface,
          border: Border(top: BorderSide(color: L.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 30,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Btn(
                    small: true,
                    icon: Icon(open ? Icons.expand_more : Icons.expand_less),
                    onTap: onToggle,
                  ),
                  const Caption('Transfers'),
                  if (active > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '$active active',
                      style: const TextStyle(fontSize: 11, color: L.accent),
                    ),
                  ],
                  const Spacer(),
                  Btn(
                    small: true,
                    label: 'Clear finished',
                    onTap: queue.items.length > active
                        ? queue.clearFinished
                        : null,
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
            if (open)
              SizedBox(
                height: 140,
                child: queue.items.isEmpty
                    ? const Center(
                        child: Text(
                          'No transfers. Drag files between the panes or use Upload / Download.',
                          style: TextStyle(fontSize: 11.5, color: L.subtle),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        children: [
                          for (final t in queue.items) _TransferRow(t),
                        ],
                      ),
              ),
          ],
        ),
      );
    },
  );
}

class _TransferRow extends StatelessWidget {
  final Transfer t;
  const _TransferRow(this.t);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: t,
    builder: (_, _) {
      final (color, status) = switch (t.state) {
        TransferState.queued => (L.subtle, 'Queued'),
        TransferState.running => (
          L.accent,
          '${formatBytes(t.done)} / ${formatBytes(t.total)} · '
              '${formatBytes(t.speed)}/s',
        ),
        TransferState.done => (L.ok, 'Done · ${formatBytes(t.total)}'),
        TransferState.failed => (L.danger, 'Failed: ${t.error}'),
        TransferState.cancelled => (L.subtle, 'Cancelled'),
      };
      final running =
          t.state == TransferState.running || t.state == TransferState.queued;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(
              t.upload ? Icons.upload : Icons.download,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 220,
              child: Text(
                t.source.name +
                    (t.state == TransferState.running &&
                            t.source.isDir &&
                            t.current.isNotEmpty
                        ? '  (${t.current})'
                        : ''),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: t.state == TransferState.done ? 1 : t.progress,
                  minHeight: 3,
                  color: color,
                  backgroundColor: L.border,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 230,
              child: Text(
                status,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: color),
              ),
            ),
            Btn(
              small: true,
              icon: const Icon(Icons.close),
              tooltip: 'Cancel',
              onTap: running ? t.cancel : null,
            ),
          ],
        ),
      );
    },
  );
}

/// Plain-text editor for a local or remote file.
class FileEditor extends StatefulWidget {
  final Fs fs;
  final String path;
  final String origin;
  const FileEditor({
    super.key,
    required this.fs,
    required this.path,
    required this.origin,
  });

  @override
  State<FileEditor> createState() => _FileEditorState();
}

class _FileEditorState extends State<FileEditor>
    with AutomaticKeepAliveClientMixin {
  final _ctl = TextEditingController();
  final _scroll = ScrollController();
  String _saved = '';
  String? _error;
  bool _loading = true, _saving = false;

  @override
  bool get wantKeepAlive => true;

  bool get _dirty => _ctl.text != _saved;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final text = decodeText(await widget.fs.readBytes(widget.path));
      if (text == null) throw 'This looks like a binary file.';
      _saved = text;
      _ctl.text = text;
      _error = null;
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.fs.writeBytes(
        widget.path,
        Uint8List.fromList(utf8.encode(_ctl.text)),
      );
      _saved = _ctl.text;
      toast('Saved ${widget.path}');
    } catch (e) {
      toast('Save failed: $e');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Cannot open ${widget.path}',
        hint: _error,
      );
    }
    final lines = '\n'.allMatches(_ctl.text).length + 1;
    const style = TextStyle(
      fontFamily: L.mono,
      fontSize: 13,
      height: 1.5,
      color: L.text,
    );
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
              Text(
                widget.origin,
                style: const TextStyle(fontSize: 11.5, color: L.accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.path,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: L.subtle,
                    fontFamily: L.mono,
                  ),
                ),
              ),
              if (_dirty)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Text(
                    '● unsaved',
                    style: TextStyle(fontSize: 11, color: L.accent),
                  ),
                ),
              Btn(
                small: true,
                icon: const Icon(Icons.refresh),
                label: 'Reload',
                onTap: _saving ? null : _load,
              ),
              Btn(
                small: true,
                variant: BtnVariant.solid,
                icon: const Icon(Icons.save_outlined),
                label: _saving ? 'Saving…' : 'Save',
                tooltip: 'Ctrl+S',
                onTap: _dirty && !_saving ? _save : null,
              ),
            ],
          ),
        ),
        Expanded(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(
                LogicalKeyboardKey.keyS,
                control: true,
              ): () {
                if (_dirty) _save();
              },
            },
            child: SingleChildScrollView(
              controller: _scroll,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    padding: const EdgeInsets.only(top: 10, right: 10),
                    child: Text(
                      [for (var i = 1; i <= lines; i++) '$i'].join('\n'),
                      textAlign: TextAlign.right,
                      style: style.copyWith(color: L.subtle),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _ctl,
                      maxLines: null,
                      style: style,
                      autofocus: true,
                      decoration: const InputDecoration(
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.fromLTRB(0, 10, 10, 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
