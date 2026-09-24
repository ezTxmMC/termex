import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

class SSHHandler {
  Future<SSHClient> createClient(
    String host,
    int port,
    String username,
    String password,
  ) async {
    try {
      debugPrint('[SSH] Attempting socket connection to $host:$port');
      final socket = await SSHSocket.connect(
        host,
        port,
        timeout: const Duration(seconds: 30),
      );
      debugPrint('[SSH] Socket connected, creating SSH client');

      final client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password,
      );

      debugPrint('[SSH] Client created and authenticated');
      return client;
    } on SocketException catch (e) {
      debugPrint(
        '[SSH] SocketException: ${e.message} (OS Error: ${e.osError})',
      );
      throw SocketException(
        'Failed to connect to $host:$port - ${e.message}',
        osError: e.osError,
        address: e.address,
        port: e.port,
      );
    } catch (e) {
      debugPrint('[SSH] Connection error: $e');
      throw Exception('SSH connection error: $e');
    }
  }

  Future<String> runCommand(SSHClient client, String command) async {
    return utf8.decode(await client.run(command));
  }
}
