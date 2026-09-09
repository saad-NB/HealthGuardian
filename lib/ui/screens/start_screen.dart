import 'package:flutter/material.dart';

import '../../services/tier2_service.dart';
import '../../state/app_state.dart';
import '../theme/app_tokens.dart';
import '../widgets/big_button.dart';
import 'triage/triage_flow_screen.dart';

/// Home / Start tab (UI/UX plan §7.1). One big CTA; nothing to configure.
class StartScreen extends StatelessWidget {
  const StartScreen({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppMetrics.margin),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: AppColors.teal700.withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.health_and_safety,
                      size: 64,
                      color: AppColors.teal700,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Sehat Nigraan',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'صحیح انتخاب، جلد فیصلہ',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Answer a few simple questions to find out how urgently '
                  'help is needed. Works fully offline.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 40),
                BigButton(
                  label: TriageText.startTitle,
                  icon: Icons.play_arrow,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TriageFlowScreen(
                          app: app,
                          tier2Service: Tier2Service(app: app),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'This is decision support, not a diagnosis. A doctor '
                  'always makes the final call.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}