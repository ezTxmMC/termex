import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:termex/models/server_login.dart';
import 'package:termex/services/vault_service.dart';
import 'package:termex/shell/handler.dart';
import 'package:uuid/uuid.dart';

class VaultPage extends StatefulWidget {
  final Function(String, SSHClient)? onConnectionOpened;

  const VaultPage({super.key, this.onConnectionOpened});

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  final _vaultService = VaultService();
  List<ServerLogin> _logins = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogins();
  }

  Future<void> _loadLogins() async {
    final logins = await _vaultService.getAllServerLogins();
    setState(() {
      _logins = logins;
      _isLoading = false;
    });
  }

  void _showAddConnectionDialog() {
    showDialog(
      context: context,
      builder: (context) => _AddConnectionDialog(
        onSave: (login) async {
          await _vaultService.saveServerLogin(login);
          await _loadLogins();
          if (mounted && context.mounted) Navigator.pop(context);
        },
      ),
    );
  }

  void _showEditConnectionDialog(ServerLogin login) {
    showDialog(
      context: context,
      builder: (context) => _AddConnectionDialog(
        initialLogin: login,
        onSave: (updatedLogin) async {
          await _vaultService.saveServerLogin(updatedLogin);
          await _loadLogins();
          if (mounted && context.mounted) Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _deleteConnection(String id) async {
    await _vaultService.deleteServerLogin(id);
    await _loadLogins();
  }

  void _connectToServer(ServerLogin login) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final handler = SSHHandler();
      debugPrint(
        '[SSH] Connecting to ${login.host}:${login.port} as ${login.username}',
      );
      final client = await handler
          .createClient(login.host, login.port, login.username, login.password)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () =>
                throw Exception('Connection timeout after 30 seconds'),
          );
      debugPrint('[SSH] Successfully connected to ${login.host}');

      if (mounted && Navigator.canPop(context)) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Connected to ${login.name}'),
            duration: const Duration(seconds: 2),
            backgroundColor: const Color(0xFF3FB950),
          ),
        );
      }

      // Call the callback to open a new tab for this connection
      if (widget.onConnectionOpened != null) {
        widget.onConnectionOpened!(login.name, client);
      } else {
        // If no callback (standalone mode), close the connection
        client.close();
      }
    } on SocketException catch (e) {
      debugPrint('[SSH] SocketException: ${e.message}');
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection error: ${e.message}'),
            duration: const Duration(seconds: 4),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('[SSH] Error: $e');
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            duration: const Duration(seconds: 4),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vault'),
        backgroundColor: const Color(0xFF161B22),
      ),
      backgroundColor: const Color(0xFF0D1117),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _logins.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.lock_outline,
                    size: 64,
                    color: Color(0xFF30363D),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Saved Connections',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: const Color(0xFF8B949E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add one to get started',
                    style: TextStyle(color: Color(0xFF8B949E)),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _logins.length,
              itemBuilder: (context, index) {
                final login = _logins[index];
                return _ConnectionCard(
                  login: login,
                  onConnect: () => _connectToServer(login),
                  onEdit: () => _showEditConnectionDialog(login),
                  onDelete: () => _deleteConnection(login.id),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddConnectionDialog,
        backgroundColor: const Color(0xFF3FB950),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.login,
    required this.onConnect,
    required this.onEdit,
    required this.onDelete,
  });

  final ServerLogin login;
  final VoidCallback onConnect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: ListTile(
        title: Text(login.name),
        subtitle: Text('${login.username}@${login.host}:${login.port}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.login, color: Color(0xFF3FB950)),
              onPressed: onConnect,
              tooltip: 'Connect',
            ),
            PopupMenuButton(
              itemBuilder: (context) => [
                PopupMenuItem(onTap: onEdit, child: const Text('Edit')),
                PopupMenuItem(onTap: onDelete, child: const Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddConnectionDialog extends StatefulWidget {
  const _AddConnectionDialog({this.initialLogin, required this.onSave});

  final ServerLogin? initialLogin;
  final Function(ServerLogin) onSave;

  @override
  State<_AddConnectionDialog> createState() => _AddConnectionDialogState();
}

class _AddConnectionDialogState extends State<_AddConnectionDialog> {
  late TextEditingController _nameController;
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    final login = widget.initialLogin;
    _nameController = TextEditingController(text: login?.name ?? '');
    _hostController = TextEditingController(text: login?.host ?? '');
    _portController = TextEditingController(
      text: login?.port.toString() ?? '22',
    );
    _usernameController = TextEditingController(text: login?.username ?? '');
    _passwordController = TextEditingController(text: login?.password ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _save() {
    if (_nameController.text.isEmpty ||
        _hostController.text.isEmpty ||
        _usernameController.text.isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
      return;
    }

    final login = ServerLogin(
      id: widget.initialLogin?.id ?? const Uuid().v4(),
      name: _nameController.text,
      host: _hostController.text,
      port: int.tryParse(_portController.text) ?? 22,
      username: _usernameController.text,
      password: _passwordController.text,
    );

    widget.onSave(login);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF161B22),
      title: Text(
        widget.initialLogin == null ? 'Add Connection' : 'Edit Connection',
        style: const TextStyle(color: Color(0xFFE6EDF3)),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTextField('Connection Name', _nameController),
            const SizedBox(height: 12),
            _buildTextField('Host', _hostController),
            const SizedBox(height: 12),
            _buildTextField(
              'Port',
              _portController,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _buildTextField('Username', _usernameController),
            const SizedBox(height: 12),
            _buildTextField('Password', _passwordController, obscureText: true),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: const TextStyle(color: Color(0xFFE6EDF3)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF8B949E)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFF3FB950)),
        ),
      ),
    );
  }
}
