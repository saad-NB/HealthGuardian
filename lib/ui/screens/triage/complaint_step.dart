import 'package:flutter/material.dart';

import '../../../triage/models.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/answer_chip.dart';
import '../../widgets/question_scaffold.dart';

/// Section D1 — chief complaint chip grid (spec §7, UI/UX plan §7.5).
/// Selecting a chip immediately advances to the next step.
class ComplaintStep extends StatelessWidget {
  const ComplaintStep({
    super.key,
    required this.answers,
    required this.progress,
    required this.steps,
    required this.onAdvance,
    required this.onBack,
    required this.onRestart,
  });

  final TriageAnswers answers;
  final int progress;
  final int steps;
  final VoidCallback onAdvance;
  final VoidCallback? onBack;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return QuestionScaffold(
      progress: progress + 1,
      steps: steps,
      onBack: onBack,
      onUndo: onBack ?? () {},
      onRestart: onRestart,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'What is the main problem?',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Choose the one that best matches.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          for (final c in ChiefComplaint.values) ...[
            _chip(c),
            const SizedBox(height: AppMetrics.answerGap),
          ],
        ],
      ),
    );
  }

  Widget _chip(ChiefComplaint c) {
    return AnswerChip(
      label: c.label,
      selected: answers.chiefComplaint == c,
      icon: _iconFor(c),
      onSelected: () {
        answers.chiefComplaint = c;
        answers.probeAnswers.clear();
        onAdvance();
      },
    );
  }

  IconData _iconFor(ChiefComplaint c) => switch (c) {
        ChiefComplaint.fever => Icons.thermostat,
        ChiefComplaint.breathing => Icons.air,
        ChiefComplaint.chest => Icons.favorite,
        ChiefComplaint.abdo => Icons.abc,
        ChiefComplaint.gastrointestinal => Icons.sick,
        ChiefComplaint.throat => Icons.volume_off,
        ChiefComplaint.ear => Icons.hearing,
        ChiefComplaint.eye => Icons.remove_red_eye,
        ChiefComplaint.skin => Icons.brush,
        ChiefComplaint.wound => Icons.content_cut,
        ChiefComplaint.headache => Icons.psychology,
        ChiefComplaint.weakness => Icons.back_hand,
        ChiefComplaint.urinary => Icons.water_drop,
        ChiefComplaint.pregnancy => Icons.pregnant_woman,
        ChiefComplaint.injury => Icons.warning,
        ChiefComplaint.poisoning => Icons.science,
        ChiefComplaint.mentalHealth => Icons.psychology_alt,
        ChiefComplaint.other => Icons.help_outline,
      };
}