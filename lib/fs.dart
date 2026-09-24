import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

class Entry {
  final String name, path;
  final bool isDir, isLink;
  final int size;
  final DateTime? modified;

  /// Permission bits (0o777), or null if unknown.
  final int? mode;

  const Entry({
    required this.name,
    required this.path,
    required this.isDir,
    this.isLink = false,
    this.size = 0,
    this.modified,
    this.mode,
  });

  String get perms {
    final m = mode;
    if (m == null) return '';
    const c = 'rwxrwxrwx';
    return (isDir ? 'd' : '-') +
        [
          for (var i = 0; i < 9; i++) (m >> (8 - i)) & 1 == 1 ? c[i] : '-',
        ].join();
  }
}

/// Minimal filesystem interface shared by the local and the remote pane.
abstract class Fs {
  String get label;
  String get sep;
  Future<String> home();
  Future<List<Entry>> list(String dir);
  Future<Entry> stat(String path);
  Future<void> mkdir(String path);
  Future<void> rename(String from, String to);
  Future<void> delete(Entry e);
  Future<void> chmod(String path, int mode);
  Future<Uint8List> readBytes(String path);
  Future<void> writeBytes(String path, Uint8List data);

  String join(String dir, String name) =>
      dir.endsWith(sep) ? '$dir$name' : '$dir$sep$name';

  String parent(String path) {
    final i = path.lastIndexOf(sep);
    if (i <= 0) return sep == '/' ? '/' : path;
    final p = path.substring(0, i);
    return p.endsWith(':') ? '$p$sep' : p;
  }
}

class LocalFs extends Fs {
  @override
  String get label => 'Local';
  @override
  String get sep => Platform.pathSeparator;

  @override
  Future<String> home() async =>
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.current.path;

  Entry _entry(FileSystemEntity e, FileStat s) => Entry(
    name: e.uri.pathSegments.lastWhere(
      (x) => x.isNotEmpty,
      orElse: () => e.path,
    ),
    path: e.path,
    isDir: s.type == FileSystemEntityType.directory,
    isLink: e is Link,
    size: s.size,
    modified: s.modified,
    mode: s.mode & 0x1ff,
  );

  @override
  Future<List<Entry>> list(String dir) async {
    final out = <Entry>[];
    await for (final e in Directory(dir).list(followLinks: false)) {
      try {
        out.add(_entry(e, await FileStat.stat(e.path)));
      } catch (_) {}
    }
    return out;
  }

  @override
  Future<Entry> stat(String path) async =>
      _entry(File(path), await FileStat.stat(path));

  @override
  Future<void> mkdir(String path) => Directory(path).create(recursive: true);

  @override
  Future<void> rename(String from, String to) async {
    await (await FileSystemEntity.isDirectory(from)
            ? Directory(from)
            : File(from))
        .rename(to);
  }

  @override
  Future<void> delete(Entry e) async {
    if (e.isLink) {
      await Link(e.path).delete();
      return;
    }
    await (e.isDir ? Directory(e.path) : File(e.path)).delete(recursive: true);
  }

  @override
  Future<void> chmod(String path, int mode) async {
    final r = await Process.run('chmod', [mode.toRadixString(8), path]);
    if (r.exitCode != 0) throw '${r.stderr}'.trim();
  }

  @override
  Future<Uint8List> readBytes(String path) => File(path).readAsBytes();

  @override
  Future<void> writeBytes(String path, Uint8List data) =>
      File(path).writeAsBytes(data);
}

class RemoteFs extends Fs {
  final SftpClient sftp;
  final String name;
  RemoteFs(this.sftp, this.name);

  @override
  String get label => name;
  @override
  String get sep => '/';

  @override
  Future<String> home() => sftp.absolute('.');

  Entry _entry(String dir, String name, SftpFileAttrs a) => Entry(
    name: name,
    path: join(dir, name),
    isDir: a.isDirectory,
    isLink: a.isSymbolicLink,
    size: a.size ?? 0,
    modified: a.modifyTime == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(a.modifyTime! * 1000),
    mode: a.mode == null ? null : a.mode!.value & 0x1ff,
  );

  @override
  Future<List<Entry>> list(String dir) async {
    final out = <Entry>[];
    for (final n in await sftp.listdir(dir)) {
      if (n.filename == '.' || n.filename == '..') continue;
      var attr = n.attr;
      // Follow symlinks so linked directories can be opened.
      if (attr.isSymbolicLink) {
        try {
          final t = await sftp.stat(join(dir, n.filename));
          out.add(
            Entry(
              name: n.filename,
              path: join(dir, n.filename),
              isDir: t.isDirectory,
              isLink: true,
              size: t.size ?? 0,
              modified: _entry(dir, n.filename, t).modified,
              mode: _entry(dir, n.filename, t).mode,
            ),
          );
          continue;
        } catch (_) {}
      }
      out.add(_entry(dir, n.filename, attr));
    }
    return out;
  }

  @override
  Future<Entry> stat(String path) async {
    final a = await sftp.stat(path);
    final i = path.lastIndexOf('/');
    return _entry(
      i <= 0 ? '/' : path.substring(0, i),
      path.substring(i + 1),
      a,
    );
  }

  @override
  Future<void> mkdir(String path) => sftp.mkdir(path);

  /// `mkdir -p`
  Future<void> mkdirs(String path) async {
    try {
      if ((await sftp.stat(path)).isDirectory) return;
    } catch (_) {}
    final p = parent(path);
    if (p != path) await mkdirs(p);
    await sftp.mkdir(path);
  }

  @override
  Future<void> rename(String from, String to) => sftp.rename(from, to);

  @override
  Future<void> delete(Entry e) async {
    if (e.isDir && !e.isLink) {
      for (final c in await list(e.path)) {
        await delete(c);
      }
      await sftp.rmdir(e.path);
    } else {
      await sftp.remove(e.path);
    }
  }

  @override
  Future<void> chmod(String path, int mode) =>
      sftp.setStat(path, SftpFileAttrs(mode: SftpFileMode.value(mode)));

  @override
  Future<Uint8List> readBytes(String path) async {
    final f = await sftp.open(path);
    try {
      return await f.readBytes();
    } finally {
      await f.close();
    }
  }

  @override
  Future<void> writeBytes(String path, Uint8List data) async {
    final f = await sftp.open(
      path,
      mode:
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate |
          SftpFileOpenMode.write,
    );
    try {
      await f.writeBytes(data);
    } finally {
      await f.close();
    }
  }
}

enum TransferState { queued, running, done, failed, cancelled }

/// One upload or download (a file or a whole directory tree).
class Transfer extends ChangeNotifier {
  final bool upload;
  final Entry source;
  final String targetDir;
  TransferState state = TransferState.queued;
  int total = 0, done = 0;
  String current = '';
  String? error;
  final _started = DateTime.now();
  Future<void> Function()? _abort;
  bool _cancelled = false;

  Transfer(this.upload, this.source, this.targetDir);

  double get progress => total == 0 ? 0 : done / total;
  double get speed {
    final s = DateTime.now().difference(_started).inMilliseconds / 1000;
    return s <= 0 ? 0 : done / s;
  }

  void cancel() {
    _cancelled = true;
    _abort?.call();
    if (state == TransferState.queued) {
      state = TransferState.cancelled;
      notifyListeners();
    }
  }

  void _tick() => notifyListeners();
}

/// Runs transfers one after another.
class TransferQueue extends ChangeNotifier {
  final LocalFs local;
  final RemoteFs remote;
  final List<Transfer> items = [];
  bool _running = false;
  void Function(Transfer)? onFinished;

  TransferQueue(this.local, this.remote);

  void add(Transfer t) {
    items.insert(0, t);
    notifyListeners();
    _pump();
  }

  void clearFinished() {
    items.removeWhere(
      (t) =>
          t.state != TransferState.queued && t.state != TransferState.running,
    );
    notifyListeners();
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    while (true) {
      // Oldest queued first; new items are inserted at the front.
      Transfer? next;
      for (final t in items.reversed) {
        if (t.state == TransferState.queued) {
          next = t;
          break;
        }
      }
      if (next == null) break;
      next.state = TransferState.running;
      notifyListeners();
      try {
        next.total = next.upload
            ? await _localSize(next.source)
            : await _remoteSize(next.source);
        next._tick();
        next.upload
            ? await _upload(next, next.source, next.targetDir)
            : await _download(next, next.source, next.targetDir);
        next.state = next._cancelled
            ? TransferState.cancelled
            : TransferState.done;
      } catch (e) {
        next.state = next._cancelled
            ? TransferState.cancelled
            : TransferState.failed;
        next.error = '$e';
      }
      next._tick();
      notifyListeners();
      onFinished?.call(next);
    }
    _running = false;
  }

  Future<int> _localSize(Entry e) async {
    if (!e.isDir) return e.size;
    var n = 0;
    await for (final f in Directory(e.path).list(recursive: true)) {
      if (f is File) n += await f.length();
    }
    return n;
  }

  Future<int> _remoteSize(Entry e) async {
    if (!e.isDir) return e.size;
    var n = 0;
    for (final c in await remote.list(e.path)) {
      n += await _remoteSize(c);
    }
    return n;
  }

  Future<void> _upload(Transfer t, Entry e, String dir) async {
    if (t._cancelled) return;
    final target = remote.join(dir, e.name);
    if (e.isDir) {
      await remote.mkdirs(target);
      for (final c in await local.list(e.path)) {
        await _upload(t, c, target);
      }
      return;
    }
    t.current = e.name;
    final f = await remote.sftp.open(
      target,
      mode:
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate |
          SftpFileOpenMode.write,
    );
    final base = t.done;
    try {
      final writer = f.write(
        File(
          e.path,
        ).openRead().map((c) => c is Uint8List ? c : Uint8List.fromList(c)),
        onProgress: (n) {
          t.done = base + n;
          t._tick();
        },
      );
      t._abort = writer.abort;
      await writer.done;
      t._abort = null;
    } finally {
      await f.close();
    }
    if (e.mode != null) {
      try {
        await remote.chmod(target, e.mode!);
      } catch (_) {}
    }
  }

  Future<void> _download(Transfer t, Entry e, String dir) async {
    if (t._cancelled) return;
    final target = local.join(dir, e.name);
    if (e.isDir) {
      await Directory(target).create(recursive: true);
      for (final c in await remote.list(e.path)) {
        await _download(t, c, target);
      }
      return;
    }
    t.current = e.name;
    final f = await remote.sftp.open(e.path);
    final sink = File(target).openWrite();
    try {
      await for (final chunk in f.read()) {
        if (t._cancelled) break;
        sink.add(chunk);
        t.done += chunk.length;
        t._tick();
      }
    } finally {
      await sink.close();
      await f.close();
    }
    if (e.mode != null && !Platform.isWindows) {
      try {
        await local.chmod(target, e.mode!);
      } catch (_) {}
    }
  }
}

/// Best-effort check whether bytes are text we can edit.
String? decodeText(Uint8List bytes) {
  if (bytes.take(8000).contains(0)) return null;
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return null;
  }
}
