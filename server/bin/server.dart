import 'dart:convert';
import 'dart:io';

// ignore_for_file: avoid_print, unintended_html_in_doc_comment

/// Termex sync server. Stores each vault as an opaque encrypted JSON file.
///
///   GET /vaults/<id>/salt   public: {salt, iterations} (needed to derive keys)
///   GET /vaults/<id>        needs X-Auth: the stored vault JSON
///   PUT /vaults/<id>        needs X-Auth (first PUT registers the token)
///
/// Env: PORT (8080), HOST (0.0.0.0), DATA_DIR (./data).
/// Run behind a TLS reverse proxy (caddy/nginx) when exposed to the internet.
final _idPattern = RegExp(r'^[A-Za-z0-9-]{8,64}$');
const _maxBody = 5 * 1024 * 1024;

Future<void> main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final host = Platform.environment['HOST'] ?? '0.0.0.0';
  final dir = Directory(Platform.environment['DATA_DIR'] ?? 'data')
    ..createSync(recursive: true);

  final server = await HttpServer.bind(host, port);
  print('Termex server listening on $host:$port (data: ${dir.path})');
  await for (final req in server) {
    _handle(req, dir).catchError((Object e) {
      try {
        _send(req, 500, {'error': 'internal error'});
      } catch (_) {}
    });
  }
}

void _send(HttpRequest req, int code, Map<String, dynamic> body) {
  req.response
    ..statusCode = code
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  req.response.close();
}

bool _sameToken(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

Future<void> _handle(HttpRequest req, Directory dir) async {
  final seg = req.uri.pathSegments;
  if (seg.length < 2 || seg[0] != 'vaults' || !_idPattern.hasMatch(seg[1])) {
    return _send(req, 404, {'error': 'not found'});
  }
  final id = seg[1];
  final file = File('${dir.path}/$id.json');
  final token = req.headers.value('X-Auth') ?? '';

  Map<String, dynamic>? stored;
  if (await file.exists()) {
    stored = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  if (seg.length == 3 && seg[2] == 'salt' && req.method == 'GET') {
    if (stored == null) return _send(req, 404, {'error': 'unknown vault'});
    return _send(req, 200, {
      'salt': stored['vault']['salt'],
      'iterations': stored['vault']['iterations'],
    });
  }
  if (seg.length != 2) return _send(req, 404, {'error': 'not found'});

  if (stored != null && !_sameToken(stored['token'] as String, token)) {
    return _send(req, 401, {'error': 'unauthorized'});
  }

  switch (req.method) {
    case 'GET':
      if (stored == null) return _send(req, 404, {'error': 'unknown vault'});
      return _send(req, 200, stored['vault'] as Map<String, dynamic>);
    case 'PUT':
      if (token.isEmpty) return _send(req, 401, {'error': 'missing token'});
      final bytes = <int>[];
      await for (final chunk in req) {
        bytes.addAll(chunk);
        if (bytes.length > _maxBody) {
          return _send(req, 413, {'error': 'too large'});
        }
      }
      final vault = jsonDecode(utf8.decode(bytes));
      if (vault is! Map<String, dynamic> ||
          vault['salt'] is! String ||
          vault['cipher'] is! String ||
          vault['updatedAt'] is! int) {
        return _send(req, 400, {'error': 'invalid vault'});
      }
      // Never keep the client's server URL; it is meaningless here.
      vault.remove('serverUrl');
      await file.writeAsString(jsonEncode({'token': token, 'vault': vault}));
      return _send(req, 200, {'ok': true});
    default:
      return _send(req, 405, {'error': 'method not allowed'});
  }
}
