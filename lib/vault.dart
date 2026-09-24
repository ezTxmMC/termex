import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'host.dart';

const _iterations = 150000;
final _aes = AesGcm.with256bits();

/// Password-protected vault. Everything is encrypted client-side with a key
/// derived from the master password (PBKDF2 -> 32 byte AES key + 32 byte
/// server auth token), so a sync server only ever sees ciphertext.
class Vault extends ChangeNotifier {
  String id = '';
  String? serverUrl;
  int updatedAt = 0;
  List<Host> hosts = [];

  /// Trusted host keys: `host:port` -> `type fingerprint`.
  Map<String, String> knownHosts = {};
  String? syncStatus;

  List<int> _salt = [];
  List<int> _encKey = [];
  List<int> _authToken = [];
  bool _exists = false;
  bool _unlocked = false;

  bool get exists => _exists;
  bool get unlocked => _unlocked;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}/vault.json');
  }

  Future<void> init() async {
    final f = await _file();
    if (await f.exists()) {
      final j = jsonDecode(await f.readAsString());
      id = j['id'];
      serverUrl = j['serverUrl'];
      _exists = true;
    }
    notifyListeners();
  }

  Future<void> _derive(String password) async {
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _iterations,
      bits: 512,
    ).deriveKeyFromPassword(password: password, nonce: _salt);
    final bytes = await key.extractBytes();
    _encKey = bytes.sublist(0, 32);
    _authToken = bytes.sublist(32);
  }

  Future<void> create(String password) async {
    id = const Uuid().v4();
    _salt = List.generate(16, (_) => SecureRandom.defaultRandom.nextInt(256));
    hosts = [];
    await _derive(password);
    _exists = _unlocked = true;
    await save();
  }

  Future<void> unlock(String password) async {
    final j = jsonDecode(await (await _file()).readAsString());
    _salt = base64Decode(j['salt']);
    await _derive(password);
    try {
      await _decrypt(j);
    } on SecretBoxAuthenticationError {
      throw 'Wrong password';
    }
    id = j['id'];
    serverUrl = j['serverUrl'];
    updatedAt = j['updatedAt'];
    _unlocked = true;
    notifyListeners();
    if (serverUrl != null) sync();
  }

  void lock() {
    _encKey = _authToken = [];
    hosts = [];
    knownHosts = {};
    _unlocked = false;
    notifyListeners();
  }

  Future<Map<String, dynamic>> _encode() async {
    final box = await _aes.encrypt(
      utf8.encode(
        jsonEncode({
          'hosts': hosts.map((h) => h.toJson()).toList(),
          'knownHosts': knownHosts,
        }),
      ),
      secretKey: SecretKey(_encKey),
    );
    return {
      'id': id,
      'serverUrl': serverUrl,
      'salt': base64Encode(_salt),
      'iterations': _iterations,
      'updatedAt': updatedAt,
      'nonce': base64Encode(box.nonce),
      'cipher': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
  }

  Future<void> _decrypt(Map<String, dynamic> j) async {
    final clear = await _aes.decrypt(
      SecretBox(
        base64Decode(j['cipher']),
        nonce: base64Decode(j['nonce']),
        mac: Mac(base64Decode(j['mac'])),
      ),
      secretKey: SecretKey(_encKey),
    );
    final data = jsonDecode(utf8.decode(clear));
    // Older vaults stored just the host list.
    final list = data is List ? data : data['hosts'] as List;
    hosts = [for (final e in list) Host.fromJson(e as Map<String, dynamic>)];
    knownHosts = data is Map
        ? Map<String, String>.from(data['knownHosts'] ?? {})
        : {};
  }

  Future<void> _write() async {
    await (await _file()).writeAsString(jsonEncode(await _encode()));
  }

  /// Persist locally and push to the server (best effort).
  Future<void> save() async {
    updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _write();
    notifyListeners();
    if (serverUrl != null) sync();
  }

  Future<void> upsert(Host h) {
    final i = hosts.indexWhere((e) => e.id == h.id);
    i >= 0 ? hosts[i] = h : hosts.add(h);
    return save();
  }

  Host? byId(String id) {
    for (final h in hosts) {
      if (h.id == id) return h;
    }
    return null;
  }

  Future<void> trustHostKey(String key, String fingerprint) {
    knownHosts[key] = fingerprint;
    return save();
  }

  Future<void> remove(Host h) {
    hosts.removeWhere((e) => e.id == h.id);
    return save();
  }

  Future<void> setServer(String? url) async {
    serverUrl = url == null || url.trim().isEmpty
        ? null
        : url.trim().replaceAll(RegExp(r'/+$'), '');
    await _write();
    notifyListeners();
    if (serverUrl != null) await sync();
  }

  // ---- sync ----

  Future<(int, Map<String, dynamic>?)> _http(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await c.openUrl(method, Uri.parse('$serverUrl$path'));
      if (auth) req.headers.set('X-Auth', base64Encode(_authToken));
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close();
      final text = await utf8.decoder.bind(res).join();
      Map<String, dynamic>? json;
      try {
        json = jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {}
      return (res.statusCode, json);
    } finally {
      c.close(force: true);
    }
  }

  bool _syncing = false;

  /// Two-way sync, newest `updatedAt` wins. Returns a status message.
  Future<String> sync() async {
    if (serverUrl == null || !_unlocked || _syncing) {
      return 'Sync not available';
    }
    _syncing = true;
    try {
      final (code, remote) = await _http('GET', '/vaults/$id');
      String msg;
      if (code == 404) {
        await _push();
        msg = 'Uploaded to server';
      } else if (code == 200 && remote != null) {
        final ru = remote['updatedAt'] as int;
        if (ru > updatedAt) {
          await _decrypt(remote);
          updatedAt = ru;
          await _write();
          msg = 'Downloaded from server';
        } else if (ru < updatedAt) {
          await _push();
          msg = 'Uploaded to server';
        } else {
          msg = 'Up to date';
        }
      } else if (code == 401) {
        throw 'Server rejected the vault password';
      } else {
        throw 'Server error ($code)';
      }
      return syncStatus = msg;
    } catch (e) {
      syncStatus = 'Sync failed: $e';
      return syncStatus!;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> _push() async {
    final (code, _) = await _http('PUT', '/vaults/$id', body: await _encode());
    if (code != 200) throw 'Server error ($code)';
  }

  /// Set up this device from a vault that already lives on a server.
  Future<void> join(String url, String vaultId, String password) async {
    serverUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    id = vaultId.trim();
    final (code, meta) = await _http('GET', '/vaults/$id/salt', auth: false);
    if (code != 200 || meta == null) throw 'Vault not found on server ($code)';
    _salt = base64Decode(meta['salt']);
    await _derive(password);
    final (c2, remote) = await _http('GET', '/vaults/$id');
    if (c2 == 401) throw 'Wrong password';
    if (c2 != 200 || remote == null) throw 'Server error ($c2)';
    try {
      await _decrypt(remote);
    } on SecretBoxAuthenticationError {
      throw 'Wrong password';
    }
    updatedAt = remote['updatedAt'];
    _exists = _unlocked = true;
    await _write();
    notifyListeners();
  }
}
