import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import 'settings_screen.dart';

/// Top-left gear that opens Settings (ADR-017). Settings is no longer a nav
/// destination, so every primary tab carries this leading action instead and
/// the user can only reach model management by actively choosing it.
class SettingsAction extends StatelessWidget {
  const SettingsAction({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings_outlined),
      selectedIcon: const Icon(Icons.settings),
      tooltip: 'Settings',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => SettingsScreen(app: app)),
      ),
    );
  }
}