import 'dart:convert';
import 'package:termex/models/app_settings.dart';
import 'package:termex/services/local_storage.dart';

class SettingsService {
  static const String _settingsKey = 'termex_settings';
  static AppSettings? _cachedSettings;

  Future<AppSettings> loadSettings() async {
    if (_cachedSettings != null) return _cachedSettings!;

    final settingsJson = await LocalStorage.read(_settingsKey);
    final settings = settingsJson == null
        ? AppSettings()
        : AppSettings.fromJson(jsonDecode(settingsJson));
    _cachedSettings = settings;
    return settings;
  }

  Future<void> saveSettings(AppSettings settings) async {
    _cachedSettings = settings;
    final json = jsonEncode(settings.toJson());
    await LocalStorage.write(_settingsKey, json);
  }

  Future<void> updateDefaultView(DefaultView view) async {
    final settings = await loadSettings();
    await saveSettings(settings.copyWith(defaultView: view));
  }

  Future<void> updateTerminalType(TerminalType type) async {
    final settings = await loadSettings();
    await saveSettings(settings.copyWith(terminalType: type));
  }

  Future<void> resetSettings() async {
    _cachedSettings = null;
    await LocalStorage.delete(_settingsKey);
  }
}
