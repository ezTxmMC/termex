import 'dart:io';
import 'package:path_provider/path_provider.dart';

class LocalStorage {
  static Future<File> _getStorageFile(String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final appDir = Directory('${dir.path}/termex');
    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }
    return File('${appDir.path}/$filename');
  }

  static Future<String?> read(String key) async {
    try {
      final file = await _getStorageFile('$key.json');
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (e) {
      // Silently fail
    }
    return null;
  }

  static Future<void> write(String key, String value) async {
    try {
      final file = await _getStorageFile('$key.json');
      await file.writeAsString(value);
    } catch (e) {
      // Silently fail
    }
  }

  static Future<void> delete(String key) async {
    try {
      final file = await _getStorageFile('$key.json');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Silently fail
    }
  }
}
