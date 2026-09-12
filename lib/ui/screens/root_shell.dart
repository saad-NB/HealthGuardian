import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../triage/record.dart';
import '../../vitals/monitor/monitor_screen.dart';
import '../../vitals/sessions.dart';
import 'chat_screen.dart';
import 'history_screen.dart';
import 'start_screen.dart';

/// App shell (UI/UX plan §5.1, ADR-016/017): Start / History / Monitor / Ask
/// AI. Settings is no longer a nav destination — each primary tab shows a
/// top-left gear ([SettingsAction]) and pushes Settings as a route. Ask AI is
/// a session carried by the shell; Monitor is the vitals-sensing tab.
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
            app: widget.app,
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
          MonitorScreen(app: widget.app, sessionFor: createMeasurementSession),
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
            icon: Icon(Icons.monitor_heart_outlined),
            selectedIcon: Icon(Icons.monitor_heart),
            label: 'Monitor',
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