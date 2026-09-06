import 'package:flutter/material.dart';

import '../../../triage/models.dart';
import '../../../triage/probes.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/question_scaffold.dart';
import '../../widgets/segmented_yes_no.dart';

/// Section E — scored complaint probes for a given [branch] (spec §8).
/// All questions for the branch are shown on one scrollable screen with
/// tri-state Yes/No controls; Continue advances.
class ProbesStep extends StatefulWidget {
  const ProbesStep({
    super.key,
    required this.branch,
    required this.answers,
    required this.progress,
    required this.steps,
    required this.onContinue,
    required this.onBack,
    required this.onRestart,
  });

  final ProbeBranch branch;
  final TriageAnswers answers;
  final int progress;
  final int steps;
  final VoidCallback onContinue;
  final VoidCallback? onBack;
  final VoidCallback onRestart;

  @override
  State<ProbesStep> createState() => _ProbesStepState();
}

class _ProbesStepState extends State<ProbesStep> {
  void _set(String id, bool value) {
    setState(() => widget.answers.probeAnswers[id] = value);
  }

  @override
  Widget build(BuildContext context) {
    final questions = probeQuestions(widget.branch);
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
            'Questions about ${widget.branch.stepTitle}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'For each question, answer Yes or No.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          for (final q in questions) ...[
            _row(q),
            const SizedBox(height: AppMetrics.answerGap),
          ],
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

  Widget _row(ProbeQuestion q) {
    // E-B1 ("can speak full sentences") is an inverted probe: No = concern.
    final value = widget.answers.probeAnswers[q.id];
    return Container(
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
            q.text,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedYesNo(
            value: value,
            onChanged: (v) => _set(q.id, v),
          ),
        ],
      ),
    );
  }
}