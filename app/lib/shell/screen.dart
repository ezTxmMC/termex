import 'package:flutter/material.dart';
import 'package:termex/shell/panel.dart';
import 'package:termex/shell/session.dart';
import 'package:termex/shell/theme.dart';
import 'package:termex/ui/settings_page.dart';
import 'package:termex/ui/vault_page.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final List<TerminalSession> _sessions = [];
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    _addTab();
  }

  @override
  void dispose() {
    for (final s in _sessions) {
      s.dispose();
    }
    super.dispose();
  }

  void _addTab() {
    final session = TerminalSession(title: 'shell ${_sessions.length + 1}');
    session.start();
    setState(() {
      _sessions.add(session);
      _activeIndex = _sessions.length - 1;
    });
  }

  void _closeTab(int index) {
    if (_sessions.length == 1) return;
    _sessions[index].dispose();
    setState(() {
      _sessions.removeAt(index);
      _activeIndex = (_activeIndex >= _sessions.length)
          ? _sessions.length - 1
          : _activeIndex;
    });
  }

  void _showMenu() {
    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(100, 100, 0, 0),
      items: [
        PopupMenuItem(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VaultPage()),
            );
          },
          child: const Text('Vault'),
        ),
        PopupMenuItem(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            );
          },
          child: const Text('Settings'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Column(
        children: [
          _TabBar(
            sessions: _sessions,
            activeIndex: _activeIndex,
            onSelect: (i) => setState(() => _activeIndex = i),
            onClose: _closeTab,
            onNew: _addTab,
            onMenu: _showMenu,
          ),
          Expanded(
            child: IndexedStack(
              index: _activeIndex,
              children: [
                for (int i = 0; i < _sessions.length; i++)
                  TerminalPanel(
                    session: _sessions[i],
                    title: '${_sessions[i].title} — zsh',
                    theme: TerminalColorThemes.dark,
                    borderRadius: BorderRadius.zero,
                    onClose: () => _closeTab(i),
                    onMaximize: () {},
                    onMinimize: () {},
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.sessions,
    required this.activeIndex,
    required this.onSelect,
    required this.onClose,
    required this.onNew,
    required this.onMenu,
  });

  final List<TerminalSession> sessions;
  final int activeIndex;
  final void Function(int) onSelect;
  final void Function(int) onClose;
  final VoidCallback onNew;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: const Color(0xFF161B22),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: sessions.length,
              itemBuilder: (_, i) => _Tab(
                label: sessions[i].title,
                active: i == activeIndex,
                onTap: () => onSelect(i),
                onClose: sessions.length > 1 ? () => onClose(i) : null,
              ),
            ),
          ),
          _NewTabButton(onTap: onNew),
          GestureDetector(
            onTap: onMenu,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              child: const Icon(Icons.more_vert, size: 18, color: Color(0xFF8B949E)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.active,
    required this.onTap,
    this.onClose,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF0D1117) : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: active ? const Color(0xFF3FB950) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 12,
                color: active
                    ? const Color(0xFFE6EDF3)
                    : const Color(0xFF8B949E),
              ),
            ),
            if (onClose != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onClose,
                child: const Icon(
                  Icons.close,
                  size: 13,
                  color: Color(0xFF8B949E),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NewTabButton extends StatelessWidget {
  const _NewTabButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        child: const Icon(Icons.add, size: 18, color: Color(0xFF8B949E)),
      ),
    );
  }
}
