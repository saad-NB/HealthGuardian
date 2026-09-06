import 'package:flutter/material.dart';

import '../../../triage/danger_signs.dart';
import '../../../triage/models.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/question_scaffold.dart';
import '../../widgets/segmented_yes_no.dart';

/// Section A — "Does the patient have ANY of these right now?"
/// (UI/UX plan §7.3). Any Yes marks that row inline (so the user sees exactly
/// which danger was selected, without the list jumping) and Continue then
/// routes to the P1 result via [onDangerResult].
class DangerSignsStep extends StatefulWidget {
  const DangerSignsStep({
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
  State<DangerSignsStep> createState() => _DangerSignsStepState();
}

class _DangerSignsStepState extends State<DangerSignsStep> {
  void _set(String id, bool value) {
    setState(() {
      if (value) {
        widget.answers.dangerSigns.add(id);
        widget.answers.dangerNo.remove(id);
      } else {
        widget.answers.dangerSigns.remove(id);
        widget.answers.dangerNo.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
            'If any of these is true, get emergency help immediately. '
            'Selected dangers will be collected here; you review them all '
            'before continuing.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
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
    final bool? value;
    if (widget.answers.dangerSigns.contains(d.id)) {
      value = true;
    } else if (widget.answers.dangerNo.contains(d.id)) {
      value = false;
    } else {
      value = null;
    }
    final isDanger = widget.answers.dangerSigns.contains(d.id);
    return Container(
      key: ValueKey('danger-${d.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDanger
            ? AppColors.tierP1.withValues(alpha: 0.10)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDanger
              ? AppColors.tierP1.withValues(alpha: 0.8)
              : Colors.white.withValues(alpha: 0.10),
        ),
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
          if (isDanger) ...[
            const SizedBox(height: 10),
            const Row(
              children: [
                Icon(Icons.dangerous, color: AppColors.tierP1, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Selected as an emergency danger signal - this will '
                    'route to the P1 result on Continue.',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ],
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