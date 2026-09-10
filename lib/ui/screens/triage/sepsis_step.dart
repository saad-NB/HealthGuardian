import 'package:flutter/material.dart';

import '../../../triage/models.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/question_scaffold.dart';
import '../../widgets/segmented_yes_no.dart';

/// Section F — sepsis screen (spec §9).
/// Seven tri-state Y/N questions; when F1 is suspected infection the screen
/// enables qSOFA/pedSIRS tiering in the engine.
///
/// Nothing is pre-selected: each row starts unanswered and the tapped option
/// highlights, exactly like the other question rows. The engine treats null as
/// "No" (fail-closed), so skipping the screen never fabricates a risk.
class SepsisStep extends StatefulWidget {
  const SepsisStep({
    super.key,
    required this.answers,
    required this.progress,
    required this.steps,
    required this.onContinue,
    required this.onBack,
    required this.onRestart,
  });

  final TriageAnswers answers;
  final int progress;
  final int steps;
  final VoidCallback onContinue;
  final VoidCallback? onBack;
  final VoidCallback onRestart;

  @override
  State<SepsisStep> createState() => _SepsisStepState();
}

class _SepsisStepState extends State<SepsisStep> {
  void _set(String field, bool value) {
    setState(() {
      switch (field) {
        case 'F1': widget.answers.sepsis.f1 = value;
        case 'F2': widget.answers.sepsis.f2 = value;
        case 'F3': widget.answers.sepsis.f3 = value;
        case 'F4': widget.answers.sepsis.f4 = value;
        case 'F5': widget.answers.sepsis.f5 = value;
        case 'F6': widget.answers.sepsis.f6 = value;
        case 'F7': widget.answers.sepsis.f7 = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.answers.sepsis;
    return QuestionScaffold(
      progress: widget.progress + 1,
      steps: widget.steps,
      onBack: widget.onBack,
      onUndo: widget.onBack ?? () {},
      onRestart: widget.onRestart,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Sepsis screening questions',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Sepsis is a dangerous infection response. '
            'Answer these if the patient has a fever, or if '
            'temperature and oxygen levels were not measured.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          _row('F1', 'Is there a suspected or confirmed infection?', s.f1),
          _row('F2', 'Is the patient confused, drowsy, or not themselves?', s.f2),
          _row('F3', 'Is the breathing rate fast (high for their age)?', s.f3),
          _row('F4', 'Is the blood pressure low (100 or below)?', s.f4),
          _row('F5', 'Is the patient 65 years or older?', s.f5),
          _row('F6', 'Is the patient immunocompromised (weak infection defence)?', s.f6),
          _row('F7', 'Is the temperature below 36°C or above 38.5°C?', s.f7),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: widget.onContinue,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Widget _row(String field, String text, bool? value) {
    return Container(
      key: ValueKey('sepsis-$field'),
      margin: const EdgeInsets.only(bottom: AppMetrics.answerGap),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: value != null
            ? AppColors.teal700.withValues(alpha: 0.10)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value != null
              ? AppColors.teal700.withValues(alpha: 0.8)
              : Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedYesNo(
            value: value,
            onChanged: (v) => _set(field, v),
          ),
        ],
      ),
    );
  }
}