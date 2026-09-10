import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../triage/record.dart';
import 'chat_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import 'start_screen.dart';

/// App shell (UI/UX plan §5.1): Start / History / Settings + the "Ask AI"
/// chat (ADR-014). IndexedStack keeps flow state alive across tab switches.
class RootShell extends StatefulWidget {
  const RootShell({super.key, required this.app});

  final AppState app;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _tab = 0;

  /// Context/title for the Ask AI session opened from History.
  String? _chatContext;
  String? _chatTitle;

  void _openChat({required String title, required String context}) {
    setState(() {
      _chatTitle = title;
      _chatContext = context;
      _tab = 3;
    });
  }

  String _shortTimestamp(DateTime ts) {
    final local = ts.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}-${two(local.month)}-${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          StartScreen(app: widget.app),
          HistoryScreen(
            onAskAi: (record) {
              final name = record.patientName.isNotEmpty
                  ? record.patientName
                  : record.finalTier.shortLabel;
              _openChat(
                title: '$name · ${_shortTimestamp(record.timestamp)}',
                context: buildRecordContext(record),
              );
            },
          ),
          SettingsScreen(app: widget.app),
          ChatScreen(
            app: widget.app,
            patientContext: _chatContext,
            attachedTitle: _chatTitle,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        height: 80,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.medical_services_outlined),
            selectedIcon: Icon(Icons.medical_services),
            label: 'Start',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
          NavigationDestination(
            icon: Icon(Icons.smart_toy_outlined),
            selectedIcon: Icon(Icons.smart_toy),
            label: 'Ask AI',
          ),
        ],
      ),
    );
  }
}