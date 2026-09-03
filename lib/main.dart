import 'package:flutter/material.dart';

import 'screens/chat_screen.dart';
import 'screens/files_screen.dart';
import 'state/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HealthGuardianApp());
}

class HealthGuardianApp extends StatefulWidget {
  const HealthGuardianApp({super.key});

  @override
  State<HealthGuardianApp> createState() => _HealthGuardianAppState();
}

class _HealthGuardianAppState extends State<HealthGuardianApp> {
  final AppState _app = AppState();
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _app.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sehat Nigraan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D7377),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: Text(_tab == 0 ? 'Sehat Nigraan' : 'Model Files'),
          centerTitle: true,
        ),
        body: IndexedStack(
          index: _tab,
          children: [
            ChatScreen(app: _app),
            FilesScreen(app: _app),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.medical_services_outlined),
              selectedIcon: Icon(Icons.medical_services),
              label: 'Triage',
            ),
            NavigationDestination(
              icon: Icon(Icons.save_outlined),
              selectedIcon: Icon(Icons.save),
              label: 'Models',
            ),
          ],
        ),
      ),
    );
  }
}
