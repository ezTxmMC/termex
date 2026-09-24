import 'dart:convert';
import 'package:termex/models/server_login.dart';
import 'package:termex/services/local_storage.dart';

class VaultService {
  static const String _vaultKey = 'termex_vault';
  static List<ServerLogin>? _cachedLogins;

  Future<void> saveServerLogin(ServerLogin login) async {
    final logins = await getAllServerLogins();
    final index = logins.indexWhere((l) => l.id == login.id);

    if (index >= 0) {
      logins[index] = login;
    } else {
      logins.add(login);
    }

    _cachedLogins = logins;
    final vault = jsonEncode(logins.map((l) => l.toJson()).toList());
    await LocalStorage.write(_vaultKey, vault);
  }

  Future<List<ServerLogin>> getAllServerLogins() async {
    if (_cachedLogins != null) return _cachedLogins!;

    final vaultJson = await LocalStorage.read(_vaultKey);
    if (vaultJson == null) {
      _cachedLogins = [];
      return [];
    }

    try {
      final List<dynamic> decoded = jsonDecode(vaultJson);
      final logins = decoded
          .map((item) => ServerLogin.fromJson(item as Map<String, dynamic>))
          .toList();
      _cachedLogins = logins;
      return logins;
    } catch (e) {
      return _cachedLogins ?? [];
    }
  }

  Future<ServerLogin?> getServerLogin(String id) async {
    final logins = await getAllServerLogins();
    try {
      return logins.firstWhere((l) => l.id == id);
    } catch (e) {
      return null;
    }
  }

  Future<void> deleteServerLogin(String id) async {
    final logins = await getAllServerLogins();
    logins.removeWhere((l) => l.id == id);
    _cachedLogins = logins;

    final vault = jsonEncode(logins.map((l) => l.toJson()).toList());
    await LocalStorage.write(_vaultKey, vault);
  }

  Future<void> clearAllLogins() async {
    _cachedLogins = [];
    await LocalStorage.delete(_vaultKey);
  }
}
