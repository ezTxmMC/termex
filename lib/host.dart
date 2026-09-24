import 'package:uuid/uuid.dart';

enum ForwardType { local, remote, dynamic }

/// A port forward, like `-L`, `-R` and `-D` of OpenSSH.
class Forward {
  final ForwardType type;
  final String bindHost;
  final int bindPort;
  final String destHost;
  final int destPort;

  const Forward({
    required this.type,
    this.bindHost = '127.0.0.1',
    required this.bindPort,
    this.destHost = '',
    this.destPort = 0,
  });

  Forward.fromJson(Map<String, dynamic> j)
    : type = ForwardType.values.byName(j['type']),
      bindHost = j['bindHost'] ?? '127.0.0.1',
      bindPort = j['bindPort'],
      destHost = j['destHost'] ?? '',
      destPort = j['destPort'] ?? 0;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'bindHost': bindHost,
    'bindPort': bindPort,
    'destHost': destHost,
    'destPort': destPort,
  };

  @override
  String toString() => switch (type) {
    ForwardType.local => 'L $bindHost:$bindPort → $destHost:$destPort',
    ForwardType.remote => 'R $bindHost:$bindPort → $destHost:$destPort',
    ForwardType.dynamic => 'D $bindHost:$bindPort (SOCKS)',
  };
}

class Host {
  final String id, label, group, host, username;
  final int port;
  final String password;

  /// PEM-encoded private key (empty = no key auth).
  final String keyPem, passphrase;

  /// Id of another host to tunnel through (ProxyJump), or empty.
  final String jumpId;

  /// Command sent to the shell right after login.
  final String startup;
  final bool agentForward;
  final List<Forward> forwards;

  Host({
    String? id,
    required this.label,
    this.group = '',
    required this.host,
    this.port = 22,
    required this.username,
    this.password = '',
    this.keyPem = '',
    this.passphrase = '',
    this.jumpId = '',
    this.startup = '',
    this.agentForward = false,
    this.forwards = const [],
  }) : id = id ?? const Uuid().v4();

  Host.fromJson(Map<String, dynamic> j)
    : id = (j['id'] as String?) ?? const Uuid().v4(),
      label = j['label'],
      group = j['group'] ?? '',
      host = j['host'],
      port = j['port'] ?? 22,
      username = j['username'],
      password = j['password'] ?? '',
      keyPem = j['keyPem'] ?? '',
      passphrase = j['passphrase'] ?? '',
      jumpId = j['jumpId'] ?? '',
      startup = j['startup'] ?? '',
      agentForward = j['agentForward'] ?? false,
      forwards = [
        for (final f in (j['forwards'] as List? ?? []))
          Forward.fromJson(f as Map<String, dynamic>),
      ];

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'group': group,
    'host': host,
    'port': port,
    'username': username,
    'password': password,
    'keyPem': keyPem,
    'passphrase': passphrase,
    'jumpId': jumpId,
    'startup': startup,
    'agentForward': agentForward,
    'forwards': forwards.map((f) => f.toJson()).toList(),
  };

  String get address => '$username@$host${port == 22 ? '' : ':$port'}';
}
