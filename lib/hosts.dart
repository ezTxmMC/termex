import 'dart:io';

import 'package:flutter/material.dart';

import 'host.dart';
import 'theme.dart';
import 'ui.dart';
import 'vault.dart';

/// Sidebar view listing the vault's hosts, grouped and searchable.
class HostsView extends StatefulWidget {
  final Vault vault;
  final void Function(Host) onSsh;
  final void Function(Host) onSftp;
  const HostsView({
    super.key,
    required this.vault,
    required this.onSsh,
    required this.onSftp,
  });

  @override
  State<HostsView> createState() => _HostsViewState();
}

class _HostsViewState extends State<HostsView> {
  final _search = TextEditingController();
  final Set<String> _collapsed = {};
  String? _selected;

  Vault get vault => widget.vault;

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      toast('$e');
    }
  }

  void _menu(Offset pos, Host h) => showContextMenu(context, pos, [
    MenuEntry(
      'Connect (SSH)',
      () => widget.onSsh(h),
      icon: Icons.terminal,
      hint: 'Enter',
    ),
    MenuEntry('Open SFTP', () => widget.onSftp(h), icon: Icons.folder_outlined),
    null,
    MenuEntry('Edit…', () => editHost(vault, h), icon: Icons.edit_outlined),
    MenuEntry('Duplicate', () {
      final j = h.toJson()
        ..remove('id')
        ..['label'] = '${h.label} (copy)';
      _guard(() => vault.upsert(Host.fromJson({...j, 'id': null})));
    }, icon: Icons.copy),
    null,
    MenuEntry(
      'Delete',
      () async {
        if (await confirm(
          'Delete ${h.label}?',
          'The host and its saved credentials are removed from the vault.',
          ok: 'Delete',
          danger: true,
        )) {
          await _guard(() => vault.remove(h));
        }
      },
      icon: Icons.delete_outline,
      danger: true,
    ),
  ]);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vault,
    builder: (context, _) {
      final q = _search.text.toLowerCase();
      final hosts =
          vault.hosts
              .where(
                (h) =>
                    q.isEmpty ||
                    '${h.label} ${h.host} ${h.username} ${h.group}'
                        .toLowerCase()
                        .contains(q),
              )
              .toList()
            ..sort(
              (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
            );
      final groups = <String, List<Host>>{};
      for (final h in hosts) {
        groups.putIfAbsent(h.group, () => []).add(h);
      }
      final names = groups.keys.toList()
        ..sort(
          (a, b) => a.isEmpty
              ? 1
              : b.isEmpty
              ? -1
              : a.compareTo(b),
        );
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: SizedBox(
              height: 28,
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 12.5),
                decoration: const InputDecoration(
                  hintText: 'Filter hosts',
                  hintStyle: TextStyle(fontSize: 12.5, color: L.subtle),
                  prefixIcon: Icon(Icons.search, size: 14, color: L.subtle),
                  prefixIconConstraints: BoxConstraints(minWidth: 28),
                  contentPadding: EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
          ),
          Expanded(
            child: hosts.isEmpty
                ? EmptyState(
                    icon: Icons.dns_outlined,
                    title: vault.hosts.isEmpty ? 'No hosts yet' : 'No matches',
                    hint: vault.hosts.isEmpty
                        ? 'Add a host or import your ~/.ssh/config.'
                        : null,
                    action: vault.hosts.isEmpty
                        ? Column(
                            children: [
                              Btn(
                                label: 'Add host',
                                variant: BtnVariant.solid,
                                icon: const Icon(Icons.add),
                                onTap: () => editHost(vault),
                              ),
                              const SizedBox(height: 6),
                              Btn(
                                label: 'Import ~/.ssh/config',
                                variant: BtnVariant.outline,
                                onTap: () => importSshConfig(vault),
                              ),
                            ],
                          )
                        : null,
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                    children: [
                      for (final g in names) ...[
                        if (names.length > 1 || g.isNotEmpty)
                          HoverRow(
                            padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
                            onTap: () => setState(
                              () => _collapsed.contains(g)
                                  ? _collapsed.remove(g)
                                  : _collapsed.add(g),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _collapsed.contains(g)
                                      ? Icons.chevron_right
                                      : Icons.expand_more,
                                  size: 14,
                                  color: L.subtle,
                                ),
                                const SizedBox(width: 2),
                                Caption(g.isEmpty ? 'Ungrouped' : g),
                                const SizedBox(width: 6),
                                Text(
                                  '${groups[g]!.length}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: L.subtle,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (!_collapsed.contains(g))
                          for (final h in groups[g]!) _row(h),
                      ],
                    ],
                  ),
          ),
        ],
      );
    },
  );

  Widget _row(Host h) => HoverRow(
    selected: _selected == h.id,
    onTap: () => setState(() => _selected = h.id),
    onDoubleTap: () => widget.onSsh(h),
    onContextMenu: (p) => _menu(p, h),
    child: Row(
      children: [
        Icon(
          h.keyPem.isEmpty ? Icons.dns_outlined : Icons.vpn_key_outlined,
          size: 15,
          color: _selected == h.id ? L.accent : L.muted,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                h.label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5),
              ),
              Text(
                h.address,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: L.subtle,
                  fontFamily: L.mono,
                ),
              ),
            ],
          ),
        ),
        Btn(
          small: true,
          icon: const Icon(Icons.terminal),
          tooltip: 'SSH',
          onTap: () => widget.onSsh(h),
        ),
        Btn(
          small: true,
          icon: const Icon(Icons.folder_outlined),
          tooltip: 'SFTP',
          onTap: () => widget.onSftp(h),
        ),
      ],
    ),
  );
}

/// Opens the host editor and saves the result into the vault.
Future<void> editHost(Vault vault, [Host? old]) async {
  final h = await showDialog<Host>(
    animationStyle: AnimationStyle.noAnimation,
    context: navigatorKey.currentContext!,
    builder: (_) => _HostDialog(vault: vault, old: old),
  );
  if (h == null) return;
  try {
    await vault.upsert(h);
  } catch (e) {
    toast('$e');
  }
}

class _HostDialog extends StatefulWidget {
  final Vault vault;
  final Host? old;
  const _HostDialog({required this.vault, this.old});

  @override
  State<_HostDialog> createState() => _HostDialogState();
}

class _HostDialogState extends State<_HostDialog> {
  late final _label = TextEditingController(text: widget.old?.label);
  late final _group = TextEditingController(text: widget.old?.group);
  late final _host = TextEditingController(text: widget.old?.host);
  late final _port = TextEditingController(text: '${widget.old?.port ?? 22}');
  late final _user = TextEditingController(text: widget.old?.username);
  late final _pass = TextEditingController(text: widget.old?.password);
  late final _key = TextEditingController(text: widget.old?.keyPem);
  late final _phrase = TextEditingController(text: widget.old?.passphrase);
  late final _startup = TextEditingController(text: widget.old?.startup);
  late String _jump = widget.old?.jumpId ?? '';
  late bool _agent = widget.old?.agentForward ?? false;
  late final List<Forward> _forwards = [...?widget.old?.forwards];
  int _tab = 0;

  Future<void> _loadKey() async {
    final p = await prompt(
      'Load private key',
      label: 'Path to key file',
      initial: '~/.ssh/id_ed25519',
      ok: 'Load',
    );
    if (p == null || p.trim().isEmpty) return;
    try {
      final path = p.trim().replaceFirst(
        RegExp(r'^~'),
        Platform.environment['HOME'] ?? '~',
      );
      final text = (await File(path).readAsString()).trim();
      if (!text.contains('PRIVATE KEY')) throw 'Not a private key file';
      setState(() => _key.text = text);
    } catch (e) {
      toast('Cannot read key: $e');
    }
  }

  Future<void> _addForward() async {
    final f = await showDialog<Forward>(
      animationStyle: AnimationStyle.noAnimation,
      context: context,
      builder: (_) => const _ForwardDialog(),
    );
    if (f != null) setState(() => _forwards.add(f));
  }

  void _submit() {
    if (_host.text.trim().isEmpty || _user.text.trim().isEmpty) {
      setState(() => _tab = 0);
      toast('Host and username are required');
      return;
    }
    Navigator.pop(
      context,
      Host(
        id: widget.old?.id,
        label: _label.text.trim().isEmpty
            ? _host.text.trim()
            : _label.text.trim(),
        group: _group.text.trim(),
        host: _host.text.trim(),
        port: int.tryParse(_port.text) ?? 22,
        username: _user.text.trim(),
        password: _pass.text,
        keyPem: _key.text.trim(),
        passphrase: _phrase.text,
        jumpId: _jump,
        startup: _startup.text,
        agentForward: _agent,
        forwards: _forwards,
      ),
    );
  }

  Widget _tabButton(int i, String label) => Btn(
    small: true,
    label: label,
    active: _tab == i,
    variant: BtnVariant.ghost,
    onTap: () => setState(() => _tab = i),
  );

  @override
  Widget build(BuildContext context) {
    final jumpHosts = widget.vault.hosts
        .where((h) => h.id != widget.old?.id)
        .toList();
    final pages = [
      Column(
        children: [
          Field(_label, 'Label', hint: 'My server', autofocus: true),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Field(_host, 'Host', hint: 'example.com'),
              ),
              const SizedBox(width: 10),
              Expanded(child: Field(_port, 'Port')),
            ],
          ),
          Field(_user, 'Username', hint: 'root'),
          Field(_group, 'Group', hint: 'optional, e.g. Production'),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Field(
            _pass,
            'Password',
            obscure: true,
            hint: 'empty = ask when needed',
          ),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Private key (PEM / OpenSSH)',
                  style: TextStyle(fontSize: 12, color: L.muted),
                ),
              ),
              Btn(
                small: true,
                icon: const Icon(Icons.file_open_outlined),
                label: 'Load file…',
                onTap: _loadKey,
              ),
              if (_key.text.isNotEmpty)
                Btn(
                  small: true,
                  variant: BtnVariant.danger,
                  label: 'Remove',
                  onTap: () => setState(_key.clear),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Field(
            _key,
            '',
            lines: 5,
            mono: true,
            hint: '-----BEGIN OPENSSH PRIVATE KEY-----',
          ),
          Field(
            _phrase,
            'Key passphrase',
            obscure: true,
            hint: 'empty = ask when needed',
          ),
          const Text(
            'Keys, passwords and passphrases are stored encrypted in the vault '
            'and synced with it.',
            style: TextStyle(fontSize: 11.5, color: L.subtle),
          ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Jump host (ProxyJump)',
            style: TextStyle(fontSize: 12, color: L.muted),
          ),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            initialValue: jumpHosts.any((h) => h.id == _jump) ? _jump : '',
            isDense: true,
            dropdownColor: L.overlay,
            style: const TextStyle(fontSize: 12.5, color: L.text),
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('None – connect directly'),
              ),
              for (final h in jumpHosts)
                DropdownMenuItem(
                  value: h.id,
                  child: Text('${h.label}  (${h.address})'),
                ),
            ],
            onChanged: (v) => setState(() => _jump = v ?? ''),
          ),
          const SizedBox(height: 10),
          Field(
            _startup,
            'Startup command',
            hint: 'e.g. tmux attach || tmux',
            mono: true,
          ),
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Agent forwarding', style: TextStyle(fontSize: 13)),
                    Text(
                      'Lets the server use this host\'s key for onward SSH hops.',
                      style: TextStyle(fontSize: 11.5, color: L.subtle),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _agent,
                onChanged: (v) => setState(() => _agent = v),
              ),
            ],
          ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Caption('Port forwards')),
              Btn(
                small: true,
                icon: const Icon(Icons.add),
                label: 'Add',
                onTap: _addForward,
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_forwards.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No forwards. They start automatically with every SSH session.',
                style: TextStyle(fontSize: 12, color: L.subtle),
              ),
            ),
          for (final (i, f) in _forwards.indexed)
            HoverRow(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$f',
                      style: const TextStyle(fontSize: 12, fontFamily: L.mono),
                    ),
                  ),
                  Btn(
                    small: true,
                    variant: BtnVariant.danger,
                    icon: const Icon(Icons.close),
                    onTap: () => setState(() => _forwards.removeAt(i)),
                  ),
                ],
              ),
            ),
        ],
      ),
    ];
    return LDialog(
      title: widget.old == null ? 'New host' : 'Edit ${widget.old!.label}',
      width: 520,
      actions: [
        Btn(label: 'Cancel', onTap: () => Navigator.pop(context)),
        Btn(label: 'Save', variant: BtnVariant.solid, onTap: _submit),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _tabButton(0, 'General'),
              _tabButton(1, 'Authentication'),
              _tabButton(2, 'Advanced'),
              _tabButton(
                3,
                'Forwards${_forwards.isEmpty ? '' : ' (${_forwards.length})'}',
              ),
            ],
          ),
          const Divider(height: 20),
          pages[_tab],
        ],
      ),
    );
  }
}

class _ForwardDialog extends StatefulWidget {
  const _ForwardDialog();

  @override
  State<_ForwardDialog> createState() => _ForwardDialogState();
}

class _ForwardDialogState extends State<_ForwardDialog> {
  ForwardType _type = ForwardType.local;
  final _bindHost = TextEditingController(text: '127.0.0.1');
  final _bindPort = TextEditingController();
  final _destHost = TextEditingController(text: 'localhost');
  final _destPort = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final help = switch (_type) {
      ForwardType.local =>
        'Local (-L): a port on this computer reaches a host/port through the server.',
      ForwardType.remote =>
        'Remote (-R): a port on the server reaches a host/port from this computer.',
      ForwardType.dynamic =>
        'Dynamic (-D): a local SOCKS5 proxy that tunnels through the server.',
    };
    return LDialog(
      title: 'Add port forward',
      width: 440,
      actions: [
        Btn(label: 'Cancel', onTap: () => Navigator.pop(context)),
        Btn(
          label: 'Add',
          variant: BtnVariant.solid,
          onTap: () {
            final bp = int.tryParse(_bindPort.text);
            final dp = int.tryParse(_destPort.text) ?? 0;
            if (bp == null ||
                (_type != ForwardType.dynamic &&
                    (dp == 0 || _destHost.text.trim().isEmpty))) {
              toast('Please fill in all ports');
              return;
            }
            Navigator.pop(
              context,
              Forward(
                type: _type,
                bindHost: _bindHost.text.trim(),
                bindPort: bp,
                destHost: _destHost.text.trim(),
                destPort: dp,
              ),
            );
          },
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<ForwardType>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: L.active,
              selectedForegroundColor: L.accent,
              side: const BorderSide(color: L.border),
              textStyle: const TextStyle(fontSize: 12),
            ),
            segments: const [
              ButtonSegment(value: ForwardType.local, label: Text('Local')),
              ButtonSegment(value: ForwardType.remote, label: Text('Remote')),
              ButtonSegment(value: ForwardType.dynamic, label: Text('SOCKS')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 8),
          Text(help, style: const TextStyle(fontSize: 11.5, color: L.subtle)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Field(
                  _bindHost,
                  _type == ForwardType.remote
                      ? 'Server bind address'
                      : 'Local bind address',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Field(_bindPort, 'Port')),
            ],
          ),
          if (_type != ForwardType.dynamic)
            Row(
              children: [
                Expanded(flex: 3, child: Field(_destHost, 'Destination host')),
                const SizedBox(width: 10),
                Expanded(child: Field(_destPort, 'Port')),
              ],
            ),
        ],
      ),
    );
  }
}

/// Imports hosts from ~/.ssh/config (Host, HostName, User, Port,
/// IdentityFile, ProxyJump). Wildcard entries are skipped.
Future<void> importSshConfig(Vault vault) async {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  final file = File('$home/.ssh/config');
  if (!await file.exists()) {
    toast('No ~/.ssh/config found');
    return;
  }
  final blocks = <String, Map<String, String>>{};
  Map<String, String>? cur;
  for (final raw in await file.readAsLines()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final m = RegExp(r'^(\S+)\s*=?\s*(.*)$').firstMatch(line);
    if (m == null) continue;
    final k = m[1]!.toLowerCase(), v = m[2]!.trim();
    if (k == 'host') {
      cur = null;
      for (final alias in v.split(RegExp(r'\s+'))) {
        if (alias.contains('*') || alias.contains('?')) continue;
        cur = blocks.putIfAbsent(alias, () => {});
      }
    } else if (k == 'match') {
      cur = null;
    } else {
      cur?.putIfAbsent(k, () => v);
    }
  }
  final existing = {for (final h in vault.hosts) h.label: h};
  final ids = <String, String>{};
  var added = 0;
  final created = <String, Host>{};
  for (final e in blocks.entries) {
    if (existing.containsKey(e.key)) {
      ids[e.key] = existing[e.key]!.id;
      continue;
    }
    var pem = '';
    final idf = e.value['identityfile'];
    if (idf != null) {
      try {
        pem = (await File(
          idf.replaceFirst(RegExp(r'^~'), home ?? '~'),
        ).readAsString()).trim();
      } catch (_) {}
    }
    final h = Host(
      label: e.key,
      group: 'ssh config',
      host: e.value['hostname'] ?? e.key,
      port: int.tryParse(e.value['port'] ?? '') ?? 22,
      username: e.value['user'] ?? Platform.environment['USER'] ?? 'root',
      keyPem: pem,
    );
    ids[e.key] = h.id;
    created[e.key] = h;
  }
  for (final e in created.entries) {
    final jump = blocks[e.key]!['proxyjump']?.split(',').first.split('@').last;
    var h = e.value;
    if (jump != null && ids.containsKey(jump)) {
      h = Host.fromJson({...h.toJson(), 'jumpId': ids[jump]});
    }
    vault.hosts.add(h);
    added++;
  }
  await vault.save();
  toast(
    added == 0
        ? 'Nothing new to import'
        : 'Imported $added host${added == 1 ? '' : 's'} from ~/.ssh/config',
  );
}
