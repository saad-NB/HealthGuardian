import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../screens/files_screen.dart';
import 'history_screen.dart';
import 'start_screen.dart';

/// Three-tab app shell (UI/UX plan §5.1): Start / History / Models.
class RootShell extends StatefulWidget {
  const RootShell({super.key, required this.app});

  final AppState app;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          StartScreen(app: widget.app),
          const HistoryScreen(),
          FilesScreen(app: widget.app),
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
            icon: Icon(Icons.save_outlined),
            selectedIcon: Icon(Icons.save),
            label: 'Models',
          ),
        ],
      ),
    );
  }
}