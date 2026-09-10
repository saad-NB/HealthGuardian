import 'package:flutter/material.dart';

import '../../screens/files_screen.dart';
import '../../state/app_state.dart';
import '../theme/app_tokens.dart';

/// Settings tab (replaces the old Models tab). Model management lives here so
/// the bottom navigation stays focused on triage; future settings sections
/// slot in above the model downloads list.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppMetrics.margin,
              8,
              AppMetrics.margin,
              4,
            ),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.smart_toy_outlined),
              title: const Text('AI models & downloads'),
              subtitle: const Text(
                'Download MedGemma so Ask AI runs on this phone (about 2.3 GB). '
                'Triage works on Tier 1 even without a model.',
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(child: FilesScreen(app: app)),
        ],
      ),
    );
  }
}