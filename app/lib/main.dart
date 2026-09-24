import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:termex/models/app_settings.dart';
import 'package:termex/services/settings_service.dart';
import 'package:termex/shell/screen.dart';
import 'package:termex/ui/settings_page.dart';
import 'package:termex/ui/vault_page.dart';

void main() {
  runApp(const TermexApp());
}

class TermexApp extends StatelessWidget {
  const TermexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Termex',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        colorScheme: const ColorScheme.dark(
          surface: Color(0xFF161B22),
          primary: Color(0xFF3FB950),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _settingsService = SettingsService();
  late AppSettings _settings;
  bool _isLoading = true;
  late TabController _tabController;
  int _tabCount = 2; // Local Terminal + Vault
  final List<String> _connectionTabNames = [];
  final Map<int, SSHConnectionTab> _connectionTabs = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    _loadSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsService.loadSettings();
    setState(() {
      _settings = settings;
      _isLoading = false;
      // Set initial tab based on default view
      if (_settings.defaultView == DefaultView.local) {
        _tabController.index = 0;
      } else {
        _tabController.index = 1;
      }
    });
  }

  void _navigateToSettings() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
    if (result == true) {
      await _loadSettings();
    }
  }

  void addConnectionTab(String connectionName, SSHClient client) {
    setState(() {
      _connectionTabNames.add(connectionName);
      final tabIndex = _tabCount + _connectionTabNames.length - 1;
      _connectionTabs[tabIndex] = SSHConnectionTab(
        connectionName: connectionName,
        client: client,
      );
      _tabCount++;

      // Dispose old controller and create new one with updated length
      _tabController.dispose();
      _tabController = TabController(
        length: _tabCount,
        vsync: this,
        initialIndex: _tabCount - 1, // Switch to new tab
      );
    });
  }

  void removeConnectionTab(int tabIndex) {
    setState(() {
      _connectionTabNames.removeAt(tabIndex - 2);
      _connectionTabs.remove(tabIndex);
      _tabCount--;

      final newIndex = (_tabController.index >= _tabCount)
          ? _tabCount - 1
          : _tabController.index;

      _tabController.dispose();
      _tabController = TabController(
        length: _tabCount,
        vsync: this,
        initialIndex: newIndex,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: const Color(0xFF161B22),
          child: TabBar(
            controller: _tabController,
            tabs: [
              const Tab(text: 'Local Terminal'),
              const Tab(text: 'Vault'),
              // Separator
              if (_connectionTabNames.isNotEmpty)
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  color: const Color(0xFF30363D),
                ),
              // Connection tabs
              ..._connectionTabNames.asMap().entries.map((entry) {
                return Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(entry.value),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          removeConnectionTab(entry.key + 2);
                        },
                        child: const Icon(Icons.close, size: 16),
                      ),
                    ],
                  ),
                );
              }),
            ],
            isScrollable: true,
            indicatorColor: const Color(0xFF3FB950),
            labelColor: Colors.white,
            unselectedLabelColor: const Color(0xFF8B949E),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const TerminalScreen(),
          VaultPage(onConnectionOpened: addConnectionTab),
          ..._connectionTabNames.asMap().entries.map((entry) {
            final tabIndex = entry.key + 2;
            return _connectionTabs[tabIndex] ?? const SizedBox();
          }),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16, right: 16),
        child: FloatingActionButton(
          onPressed: _navigateToSettings,
          backgroundColor: const Color(0xFF3FB950),
          child: const Icon(Icons.settings),
        ),
      ),
    );
  }
}

class SSHConnectionTab extends StatefulWidget {
  final String connectionName;
  final SSHClient client;

  const SSHConnectionTab({
    super.key,
    required this.connectionName,
    required this.client,
  });

  @override
  State<SSHConnectionTab> createState() => _SSHConnectionTabState();
}

class _SSHConnectionTabState extends State<SSHConnectionTab> {
  final TextEditingController _commandController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<String> _output = [];
  bool _isExecuting = false;

  @override
  void dispose() {
    _commandController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _executeCommand(String command) async {
    if (command.trim().isEmpty) return;

    setState(() {
      _output.add('\$ $command');
      _isExecuting = true;
    });
    _scrollToBottom();

    try {
      final result = await widget.client.run(command);
      final output = String.fromCharCodes(result);

      setState(() {
        _output.add(output.isNotEmpty ? output : '(no output)');
      });
    } catch (e) {
      setState(() {
        _output.add('Error: $e');
      });
    } finally {
      setState(() {
        _isExecuting = false;
      });
      _commandController.clear();
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Column(
        children: [
          // Header
          Container(
            color: const Color(0xFF161B22),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.terminal, color: Color(0xFF3FB950)),
                const SizedBox(width: 8),
                Text(
                  widget.connectionName,
                  style: const TextStyle(color: Color(0xFF3FB950)),
                ),
                const Spacer(),
                Tooltip(
                  message: 'Disconnect',
                  child: IconButton(
                    onPressed: () {
                      try {
                        widget.client.close();
                      } catch (e) {
                        debugPrint('[SSH] Error closing connection: $e');
                      }
                      // Navigate back to Vault tab
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Disconnected'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.close),
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ),
          // Terminal Output
          Expanded(
            child: Container(
              color: const Color(0xFF0D1117),
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                controller: _scrollController,
                child: SelectableText(
                  _output.isEmpty
                      ? 'Connected to ${widget.connectionName}\nType a command and press Enter'
                      : _output.join('\n'),
                  style: const TextStyle(
                    fontFamily: 'Courier New',
                    fontSize: 12,
                    color: Color(0xFF8B949E),
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),
          // Command Input
          Container(
            color: const Color(0xFF161B22),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Text(
                  '\$ ',
                  style: TextStyle(
                    color: Color(0xFF3FB950),
                    fontFamily: 'Courier New',
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _commandController,
                    enabled: !_isExecuting,
                    style: const TextStyle(
                      color: Color(0xFFE6EDF3),
                      fontFamily: 'Courier New',
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Enter command...',
                      hintStyle: const TextStyle(color: Color(0xFF30363D)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                    ),
                    onSubmitted: (command) => _executeCommand(command),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isExecuting
                      ? null
                      : () => _executeCommand(_commandController.text),
                  icon: _isExecuting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(
                              Color(0xFF3FB950),
                            ),
                          ),
                        )
                      : const Icon(Icons.send),
                  color: const Color(0xFF3FB950),
                  tooltip: 'Execute command',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
