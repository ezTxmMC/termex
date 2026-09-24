import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';

import 'host.dart';
import 'theme.dart';
import 'ui.dart';
import 'vault.dart';

/// An authenticated SSH connection, including the jump hosts it was
/// tunnelled through and the port forwards it runs.
class SshConnection {
  final Host host;
  final SSHClient client;
  final List<SshConnection> _jumps;
  final List<ActiveForward> forwards = [];

  SshConnection._(this.host, this.client, this._jumps);

  static Future<SshConnection> open(
    Host h,
    Vault vault, {
    void Function(String)? log,
    int depth = 0,
  }) async {
    log ??= (_) {};
    final jumps = <SshConnection>[];
    SSHSocket socket;
    try {
      if (h.jumpId.isNotEmpty) {
        final jump = vault.byId(h.jumpId);
        if (jump == null) throw 'Jump host of "${h.label}" no longer exists';
        if (depth > 8) throw 'Jump host chain is too long (loop?)';
        final j = await open(jump, vault, log: log, depth: depth + 1);
        jumps
          ..add(j)
          ..addAll(j._jumps);
        log('Tunnelling to ${h.host}:${h.port} via ${jump.label}…');
        socket = await j.client.forwardLocal(h.host, h.port);
      } else {
        log('Connecting to ${h.host}:${h.port}…');
        socket = await _TcpSocket.connect(h.host, h.port);
      }

      final identities = await _identities(h);
      final client = SSHClient(
        socket,
        username: h.username,
        identities: identities,
        keepAliveInterval: const Duration(seconds: 15),
        agentHandler: h.agentForward && identities != null
            ? SSHKeyPairAgent(identities)
            : null,
        onVerifyHostKey: (type, fp) => _verifyHostKey(h, vault, type, fp),
        onPasswordRequest: () async => h.password.isNotEmpty
            ? h.password
            : await prompt(
                'Password for ${h.address}',
                label: 'Password',
                obscure: true,
                ok: 'Log in',
              ),
        onUserInfoRequest: (req) => _keyboardInteractive(
          h,
          req.name,
          req.instruction,
          [for (final p in req.prompts) (p.promptText, p.echo)],
        ),
        onUserauthBanner: (b) => log!(b.trimRight()),
      );
      log('Authenticating as ${h.username}…');
      await client.authenticated;
      return SshConnection._(h, client, jumps);
    } catch (_) {
      for (final j in jumps) {
        j.close();
      }
      rethrow;
    }
  }

  static Future<List<SSHKeyPair>?> _identities(Host h) async {
    if (h.keyPem.trim().isEmpty) return null;
    var phrase = h.passphrase;
    if (SSHKeyPair.isEncryptedPem(h.keyPem) && phrase.isEmpty) {
      phrase =
          await prompt(
            'Passphrase for the key of ${h.label}',
            label: 'Key passphrase',
            obscure: true,
          ) ??
          '';
    }
    return SSHKeyPair.fromPem(h.keyPem, phrase.isEmpty ? null : phrase);
  }

  static Future<bool> _verifyHostKey(
    Host h,
    Vault vault,
    String type,
    List<int> md5,
  ) async {
    final key = '${h.host}:${h.port}';
    final fp =
        '$type ${md5.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':')}';
    final known = vault.knownHosts[key];
    if (known == fp) return true;
    final ok = known == null
        ? await confirm(
            'Unknown host',
            'The authenticity of $key cannot be established.\n\n'
                'Fingerprint (MD5):\n$fp\n\nTrust this host and continue?',
            ok: 'Trust & connect',
          )
        : await confirm(
            'Host key changed!',
            'The host key of $key is different from the one you trusted '
                'before. Someone could be intercepting the connection.\n\n'
                'Trusted:\n$known\n\nNow:\n$fp\n\nOnly accept if you know why '
                'the key changed.',
            ok: 'Accept new key',
            danger: true,
          );
    if (ok && vault.unlocked) await vault.trustHostKey(key, fp);
    return ok;
  }

  static Future<List<String>?> _keyboardInteractive(
    Host h,
    String name,
    String instruction,
    List<(String, bool)> prompts,
  ) async {
    if (prompts.isEmpty) return [];
    // Answer a lone password prompt automatically.
    if (prompts.length == 1 &&
        !prompts.first.$2 &&
        prompts.first.$1.toLowerCase().contains('password') &&
        h.password.isNotEmpty) {
      return [h.password];
    }
    final controllers = [for (final _ in prompts) TextEditingController()];
    return showDialog<List<String>>(
      animationStyle: AnimationStyle.noAnimation,
      context: navigatorKey.currentContext!,
      builder: (ctx) => LDialog(
        title: name.isEmpty ? 'Authentication for ${h.address}' : name,
        actions: [
          Btn(label: 'Cancel', onTap: () => Navigator.pop(ctx)),
          Btn(
            label: 'Continue',
            variant: BtnVariant.solid,
            onTap: () =>
                Navigator.pop(ctx, [for (final c in controllers) c.text]),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (instruction.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  instruction,
                  style: const TextStyle(fontSize: 12.5, color: L.muted),
                ),
              ),
            for (var i = 0; i < prompts.length; i++)
              Field(
                controllers[i],
                prompts[i].$1.trim(),
                obscure: !prompts[i].$2,
                autofocus: i == 0,
              ),
          ],
        ),
      ),
    );
  }

  /// Starts all port forwards configured for the host. Failures are
  /// reported through [log] and do not abort the connection.
  Future<void> startForwards(void Function(String) log) async {
    for (final f in host.forwards) {
      try {
        forwards.add(await ActiveForward.start(client, f));
        log('Forward active: $f');
      } catch (e) {
        log('Forward failed ($f): $e');
      }
    }
  }

  Future<SftpClient> sftp() => client.sftp();

  void close() {
    for (final f in forwards) {
      f.close();
    }
    forwards.clear();
    client.close();
    for (final j in _jumps) {
      j.client.close();
    }
  }
}

/// A running `-L`, `-R` or `-D` forward.
class ActiveForward {
  final Forward spec;
  final Future<void> Function() _close;
  ActiveForward._(this.spec, this._close);

  static Future<ActiveForward> start(SSHClient client, Forward f) async {
    switch (f.type) {
      case ForwardType.local:
        final server = await ServerSocket.bind(f.bindHost, f.bindPort);
        server.listen((socket) async {
          try {
            final ch = await client.forwardLocal(f.destHost, f.destPort);
            _pipe(socket, ch);
          } catch (_) {
            socket.destroy();
          }
        });
        return ActiveForward._(f, server.close);
      case ForwardType.remote:
        final rf = await client.forwardRemote(
          host: f.bindHost,
          port: f.bindPort,
        );
        if (rf == null) throw 'server refused the remote forward';
        rf.connections.listen((ch) async {
          try {
            final socket = await Socket.connect(f.destHost, f.destPort);
            _pipe(socket, ch);
          } catch (_) {
            ch.destroy();
          }
        });
        // rf.close() cancels the forward in an unawaited future that throws
        // when the connection is already gone.
        return ActiveForward._(
          f,
          () async => runZonedGuarded(rf.close, (_, _) {}),
        );
      case ForwardType.dynamic:
        final df = await client.forwardDynamic(
          bindHost: f.bindHost,
          bindPort: f.bindPort,
        );
        return ActiveForward._(f, df.close);
    }
  }

  static void _pipe(Socket socket, SSHForwardChannel ch) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    ch.stream.cast<List<int>>().pipe(socket).catchError((_) {});
    socket.cast<List<int>>().pipe(ch.sink).catchError((_) {});
  }

  void close() => _close().catchError((_) {});
}

/// Plain TCP transport with Nagle's algorithm disabled. dartssh2's default
/// socket leaves it on, which holds back single keystrokes for up to
/// ~40–200 ms while earlier packets wait for their ACK.
class _TcpSocket implements SSHSocket {
  final Socket _socket;
  _TcpSocket(this._socket);

  static Future<_TcpSocket> connect(String host, int port) async {
    final s = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 15),
    );
    s.setOption(SocketOption.tcpNoDelay, true);
    return _TcpSocket(s);
  }

  @override
  Stream<Uint8List> get stream => _socket;

  @override
  StreamSink<List<int>> get sink => _socket;

  @override
  Future<void> close() => _socket.close();

  @override
  Future<void> get done => _socket.done;

  @override
  void destroy() => _socket.destroy();
}
