import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../triage/engine.dart';
import '../../../triage/models.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/big_button.dart';
import '../../widgets/review_banner.dart';
import '../../widgets/tier_banner.dart';

/// Result screen (UI/UX plan §9): tier banner, "why" reasons, next steps,
/// review banner for missing vitals, and edit/restart affordances.
class ResultStep extends StatelessWidget {
  const ResultStep({
    super.key,
    required this.answers,
    required this.onEditVitals,
    required this.onEditDanger,
    required this.onRestart,
    required this.jumpedFromDanger,
  });

  final TriageAnswers answers;
  final VoidCallback? onEditVitals;
  final VoidCallback onEditDanger;
  final VoidCallback onRestart;
  final bool jumpedFromDanger;

  Future<void> _share(BuildContext context, TriageResult result) async {
    final lines = <String>[
      'Sehat Nigraan triage result',
      '${result.tier.label} - action ${result.tier.response}.',
      'NEWS2 score: ${result.aggregate?.toString() ?? 'n/a'}',
      if (result.vitalReviewRequired)
        'NOTE: some vital signs were missing - clinical review required.',
      'Why:', ...result.reasons,
      'Next steps:', ...result.tier.actionSteps,
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Summary copied - paste it into SMS or WhatsApp.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = TriageEngine.compute(answers);
    final isAdult = answers.ageGroup?.usesNews2 ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppMetrics.margin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TierBanner(tier: result.tier, onShare: () => _share(context, result)),
          const SizedBox(height: 16),
          if (result.vitalReviewRequired) ...[
            const ReviewBanner(
              message:
                  'Some readings were missing or unclear - a clinician '
                  'should still review the patient.',
            ),
            const SizedBox(height: 16),
          ],
          if (jumpedFromDanger) ...[
            Text(
              'A danger sign triggered this result before vital signs were '
              'entered.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          Text('Next steps', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (var i = 0; i < result.tier.actionSteps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${i + 1}.  ',
                      style: Theme.of(context).textTheme.bodyLarge),
                  Expanded(
                    child: Text(
                      result.tier.actionSteps[i],
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text('Why this result', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final reason in result.reasons) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: AppColors.textSubdued, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      reason,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (isAdult)
            Text(
              'NEWS2 (vitals early-warning) score: '
              '${result.aggregate?.toString() ?? 'n/a'}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          const SizedBox(height: 24),
          if (onEditVitals != null)
            BigButton(
              label: jumpedFromDanger ? 'Add vital signs' : 'Edit vital signs',
              icon: Icons.edit,
              onPressed: onEditVitals,
            ),
          const SizedBox(height: 10),
          BigButton(
            label: 'Edit danger signs',
            icon: Icons.warning_amber,
            backgroundColor: AppColors.surface,
            onPressed: onEditDanger,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRestart,
            icon: const Icon(Icons.refresh),
            label: const Text('Start over'),
          ),
          const SizedBox(height: 16),
          Text(
            'This is decision support, not a diagnosis.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}