class ServerLogin {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String password;
  final DateTime createdAt;

  ServerLogin({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory ServerLogin.fromJson(Map<String, dynamic> json) {
    return ServerLogin(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      port: json['port'] as int? ?? 22,
      username: json['username'] as String,
      password: json['password'] as String,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'username': username,
    'password': password,
    'createdAt': createdAt.toIso8601String(),
  };

  ServerLogin copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    DateTime? createdAt,
  }) =>
      ServerLogin(
        id: id ?? this.id,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        password: password ?? this.password,
        createdAt: createdAt ?? this.createdAt,
      );
}
