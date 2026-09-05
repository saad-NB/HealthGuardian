import 'package:flutter/material.dart';

import '../../../triage/danger_signs.dart';
import '../../../triage/models.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/question_scaffold.dart';
import '../../widgets/segmented_yes_no.dart';

/// Section A — "Does the patient have ANY of these right now?"
/// (UI/UX plan §7.3). Any Yes shows a sticky warning and jumps to the P1
/// result via [onResult]. No keeps the list open; Continue moves on.
class DangerSignsStep extends StatefulWidget {
  const DangerSignsStep({
    super.key,
    required this.answers,
    required this.progress,
    required this.steps,
    required this.onContinue,
    required this.onResult,
    required this.onBack,
    required this.onRestart,
  });

  final TriageAnswers answers;
  final int progress;
  final int steps;
  final VoidCallback onContinue;
  final VoidCallback onResult;
  final VoidCallback? onBack;
  final VoidCallback onRestart;

  @override
  State<DangerSignsStep> createState() => _DangerSignsStepState();
}

class _DangerSignsStepState extends State<DangerSignsStep> {
  void _set(String id, bool value) {
    setState(() {
      if (value) {
        widget.answers.dangerSigns.add(id);
        widget.onResult();
      } else {
        widget.answers.dangerSigns.remove(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final anyDanger = widget.answers.dangerSigns.isNotEmpty;
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
            'Does the patient have ANY of these right now?',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'If any of these is true, get emergency help immediately.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (anyDanger) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.tierP1.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.tierP1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.dangerous, color: AppColors.tierP1),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'A danger sign was selected - treated as an '
                      'emergency.',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: widget.onResult,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('See result now'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.tierP1,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(56),
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          for (final d in dangerSigns) ...[
            _dangerRow(d),
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

  Widget _dangerRow(DangerSignDefinition d) {
    final value = widget.answers.dangerSigns.contains(d.id);
    return Container(
      key: ValueKey('danger-${d.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  d.text,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => showDangerExplain(context, d),
                tooltip: 'Explain',
                icon: const Icon(Icons.help_outline),
                color: AppColors.textSubdued,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedYesNo(
            value: value,
            onChanged: (v) => _set(d.id, v),
          ),
        ],
      ),
    );
  }
}

void showDangerExplain(BuildContext context, DangerSignDefinition d) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppMetrics.margin),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                d.text,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                d.explain,
                style: const TextStyle(
                  fontSize: 18,
                  height: 1.5,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}