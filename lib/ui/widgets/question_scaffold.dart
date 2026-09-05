import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Steady-state questionnaire skeleton (UI/UX plan §6.2):
/// progress header, overflow menu (Undo/Start over), question body, back bar.
class QuestionScaffold extends StatelessWidget {
  const QuestionScaffold({
    super.key,
    required this.progress,
    required this.steps,
    required this.child,
    required this.onBack,
    required this.onUndo,
    required this.onRestart,
  });

  final int progress;
  final int steps;
  final Widget child;
  final VoidCallback? onBack;
  final VoidCallback onUndo;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppMetrics.margin,
            8,
            AppMetrics.margin,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Question $progress of $steps',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSubdued,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (value) {
                  if (value == 'undo') onUndo();
                  if (value == 'restart') onRestart();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'undo', child: Text('Undo last')),
                  PopupMenuItem(value: 'restart', child: Text('Start over')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress / steps,
            minHeight: 8,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppMetrics.margin),
            child: child,
          ),
        ),
        if (onBack != null)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppMetrics.margin,
                0,
                AppMetrics.margin,
                12,
              ),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}