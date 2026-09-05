import 'package:flutter/material.dart';

import 'state/app_state.dart';
import 'ui/screens/root_shell.dart';
import 'ui/theme/app_theme.dart';

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
      theme: buildAppTheme(),
      home: RootShell(app: _app),
    );
  }
}