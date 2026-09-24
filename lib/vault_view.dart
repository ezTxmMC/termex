import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';
import 'ui.dart';
import 'vault.dart';

/// Full-screen lock: create, unlock or join a vault.
class LockScreen extends StatefulWidget {
  final Vault vault;
  const LockScreen(this.vault, {super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  final _url = TextEditingController(text: 'https://');
  final _id = TextEditingController();
  bool _busy = false;
  bool _joining = false;
  String? _error;

  Future<void> _submit() async {
    final v = widget.vault;
    if (_pass.text.isEmpty) return;
    if (!v.exists && !_joining && _pass.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_joining) {
        await v.join(_url.text, _id.text, _pass.text);
      } else if (v.exists) {
        await v.unlock(_pass.text);
      } else {
        await v.create(_pass.text);
      }
      _pass.clear();
      _confirm.clear();
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final exists = widget.vault.exists;
    final (title, sub, action) = _joining
        ? (
            'Join vault',
            'Connect this device to a vault on your sync server.',
            'Join',
          )
        : exists
        ? ('Unlock vault', 'Enter your master password.', 'Unlock')
        : (
            'Create vault',
            'Hosts, keys and passwords are encrypted with this password. '
                'It cannot be recovered.',
            'Create',
          );
    return Container(
      color: L.bg,
      alignment: Alignment.center,
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: L.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: L.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: L.accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(L.radius),
              ),
              child: const Icon(Icons.lock_outline, color: L.accent, size: 22),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              sub,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                color: L.muted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            if (_joining) ...[
              Field(_url, 'Server URL'),
              Field(_id, 'Vault ID', mono: true),
            ],
            Field(
              _pass,
              'Master password',
              obscure: true,
              autofocus: true,
              onSubmitted: (_) => _submit(),
            ),
            if (!exists && !_joining)
              Field(
                _confirm,
                'Confirm password',
                obscure: true,
                onSubmitted: (_) => _submit(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _error!,
                  style: const TextStyle(fontSize: 12, color: L.danger),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: Btn(
                label: _busy ? 'Please wait…' : action,
                variant: BtnVariant.solid,
                onTap: _busy ? null : _submit,
              ),
            ),
            if (!exists) ...[
              const SizedBox(height: 8),
              Btn(
                small: true,
                label: _joining
                    ? 'Create a new vault instead'
                    : 'Join an existing vault from a server',
                onTap: _busy
                    ? null
                    : () => setState(() {
                        _joining = !_joining;
                        _error = null;
                      }),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sidebar view: vault status and sync server settings.
class SyncView extends StatefulWidget {
  final Vault vault;
  const SyncView(this.vault, {super.key});

  @override
  State<SyncView> createState() => _SyncViewState();
}

class _SyncViewState extends State<SyncView> {
  late final _url = TextEditingController(text: widget.vault.serverUrl ?? '');
  bool _busy = false;

  Future<void> _do(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      toast('$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.vault,
    builder: (context, _) {
      final v = widget.vault;
      const label = TextStyle(fontSize: 12, color: L.muted);
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          const Caption('Vault'),
          const SizedBox(height: 8),
          Text(
            '${v.hosts.length} hosts · ${v.knownHosts.length} trusted host keys',
            style: label,
          ),
          const SizedBox(height: 6),
          const Text('Vault ID', style: label),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  v.id,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: L.mono,
                    color: L.subtle,
                  ),
                ),
              ),
              Btn(
                small: true,
                icon: const Icon(Icons.content_copy),
                tooltip: 'Copy',
                onTap: () => Clipboard.setData(ClipboardData(text: v.id)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Btn(
            variant: BtnVariant.outline,
            icon: const Icon(Icons.lock_outline),
            label: 'Lock vault',
            onTap: v.lock,
          ),
          const Divider(height: 32),
          const Caption('Sync server'),
          const SizedBox(height: 8),
          Field(_url, 'Server URL', hint: 'empty = this device only'),
          Row(
            children: [
              Btn(
                variant: BtnVariant.solid,
                label: 'Save',
                onTap: _busy ? null : () => _do(() => v.setServer(_url.text)),
              ),
              const SizedBox(width: 6),
              Btn(
                variant: BtnVariant.outline,
                icon: const Icon(Icons.sync),
                label: 'Sync now',
                onTap: _busy || v.serverUrl == null
                    ? null
                    : () => _do(() async => toast(await v.sync())),
              ),
            ],
          ),
          if (v.syncStatus != null) ...[
            const SizedBox(height: 10),
            Text(
              v.syncStatus!,
              style: TextStyle(
                fontSize: 11.5,
                color: v.syncStatus!.startsWith('Sync failed')
                    ? L.danger
                    : L.subtle,
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            'Everything is encrypted on this device before upload. To use the '
            'vault on another device, choose "Join an existing vault" there '
            'and enter the server URL, the vault ID and your master password.',
            style: TextStyle(fontSize: 11.5, color: L.subtle, height: 1.5),
          ),
          const Divider(height: 32),
          const Caption('Trusted host keys'),
          const SizedBox(height: 6),
          if (v.knownHosts.isEmpty) const Text('None yet.', style: label),
          for (final e in v.knownHosts.entries)
            HoverRow(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.key, style: const TextStyle(fontSize: 12)),
                        Text(
                          e.value,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            fontFamily: L.mono,
                            color: L.subtle,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Btn(
                    small: true,
                    variant: BtnVariant.danger,
                    icon: const Icon(Icons.close),
                    tooltip: 'Forget',
                    onTap: () => _do(() {
                      v.knownHosts.remove(e.key);
                      return v.save();
                    }),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
