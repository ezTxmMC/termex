import 'package:flutter/material.dart';
import 'package:termex/models/app_settings.dart';
import 'package:termex/services/settings_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _settingsService = SettingsService();
  late AppSettings _settings;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsService.loadSettings();
    setState(() {
      _settings = settings;
      _isLoading = false;
    });
  }

  Future<void> _updateSettings(AppSettings settings) async {
    await _settingsService.saveSettings(settings);
    setState(() => _settings = settings);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color(0xFF161B22),
      ),
      backgroundColor: const Color(0xFF0D1117),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          const Text(
            'Display',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFFE6EDF3),
            ),
          ),
          const SizedBox(height: 16),
          _buildSettingsCard(
            title: 'Default View',
            subtitle: 'Choose the default view when app starts',
            child: SegmentedButton<DefaultView>(
              segments: const <ButtonSegment<DefaultView>>[
                ButtonSegment<DefaultView>(
                  value: DefaultView.local,
                  label: Text('Local Terminal'),
                ),
                ButtonSegment<DefaultView>(
                  value: DefaultView.ssh,
                  label: Text('SSH Connections'),
                ),
              ],
              selected: <DefaultView>{_settings.defaultView},
              onSelectionChanged: (Set<DefaultView> newSelection) {
                _updateSettings(
                  _settings.copyWith(defaultView: newSelection.first),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          const SizedBox(height: 8),
          const Text(
            'Terminal',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFFE6EDF3),
            ),
          ),
          const SizedBox(height: 16),
          _buildSettingsCard(
            title: 'Shell Type',
            subtitle: 'Default shell for local terminal',
            child: SegmentedButton<TerminalType>(
              segments: const <ButtonSegment<TerminalType>>[
                ButtonSegment<TerminalType>(
                  value: TerminalType.bash,
                  label: Text('Bash'),
                ),
                ButtonSegment<TerminalType>(
                  value: TerminalType.zsh,
                  label: Text('Zsh'),
                ),
                ButtonSegment<TerminalType>(
                  value: TerminalType.fish,
                  label: Text('Fish'),
                ),
              ],
              selected: <TerminalType>{_settings.terminalType},
              onSelectionChanged: (Set<TerminalType> newSelection) {
                _updateSettings(
                  _settings.copyWith(terminalType: newSelection.first),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          _buildSettingsCard(
            title: 'Remember Last Tab',
            subtitle: 'Restore active tab on app restart',
            child: Switch(
              value: _settings.rememberLastTab,
              onChanged: (value) {
                _updateSettings(
                  _settings.copyWith(rememberLastTab: value),
                );
              },
              activeThumbColor: const Color(0xFF3FB950),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFFE6EDF3),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF8B949E),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
