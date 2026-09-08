import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/tier2_service.dart';
import '../../../state/app_state.dart';
import '../../../triage/engine.dart';
import '../../../triage/models.dart';
import '../../../triage/tier2.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/big_button.dart';
import '../../widgets/review_banner.dart';
import '../../widgets/tier_banner.dart';
import '../chat_screen.dart';

/// Result screen (UI/UX plan §9, ADR-014): Tier 1 banner first, then the AI
/// analysis card with its flag + description, then edit/restart affordances.
///
/// When [tier2Service] is present and the model is available, a "Generate AI
/// summary" button runs Tier 2 (MedGemma). The AI is advisory: it can only
/// raise urgency; [finalTier] shown by the Tier 1 banner stays authoritative.
class ResultStep extends StatefulWidget {
  const ResultStep({
    super.key,
    required this.answers,
    required this.onEditVitals,
    required this.onEditDanger,
    required this.onRestart,
    required this.jumpedFromDanger,
    this.app,
    this.tier2Service,
    this.onTier2Complete,
  });

  final TriageAnswers answers;
  final VoidCallback? onEditVitals;
  final VoidCallback onEditDanger;
  final VoidCallback onRestart;
  final bool jumpedFromDanger;

  /// Needed to open the post-triage chat (Ask AI). Null hides AI features.
  final AppState? app;

  /// Injected Tier 2 service; null hides AI features (e.g. in headless tests).
  final Tier2Service? tier2Service;

  /// Called after a Tier 2 summary completes so the flow can persist it.
  final ValueChanged<Tier2Assessment>? onTier2Complete;

  @override
  State<ResultStep> createState() => _ResultStepState();
}

class _ResultStepState extends State<ResultStep> {
  Tier2Assessment? _ai;
  bool _generating = false;
  bool _genError = false;

  bool get _aiEnabled => widget.tier2Service?.available == true;

  TriageResult get _result => TriageEngine.compute(widget.answers);

  Future<void> _onGenerate() async {
    final service = widget.tier2Service;
    if (service == null) return;

    setState(() {
      _generating = true;
      _genError = false;
      _ai = null;
    });

    final assessment = await service.generateSummary(
      Tier2Payload.from(widget.answers, _result),
    );

    if (!mounted) return;
    setState(() {
      _generating = false;
      _genError = false;
      _ai = assessment;
    });
    widget.onTier2Complete?.call(assessment);
  }

  void _onAsk() {
    final contextText = buildPatientContext(widget.answers, _result);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          app: widget.app ?? AppState(),
          service: widget.tier2Service,
          patientContext: contextText,
        ),
      ),
    );
  }

  Future<void> _share(BuildContext context) async {
    final result = _result;
    final lines = <String>[
      'Sehat Nigraan triage result',
      '${result.tier.label} - action ${result.tier.response}.',
      if (result.scale != null)
        '${result.scale!.label} score: ${result.aggregate?.toString() ?? 'n/a'}',
      if (result.vitalReviewRequired)
        'NOTE: some vital signs were missing - clinical review required.',
      'Why:', ...result.reasons,
      'Next steps:', ...result.tier.actionSteps,
      if (_ai != null) ...[
        '',
        'AI analysis (MedGemma):',
        'Suggestion: ${_ai!.suggestion?.label ?? 'No change to Tier 1'}',
        if (_ai!.summary.isNotEmpty) _ai!.summary,
        'Clinician verification required.',
      ],
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
    final result = _result;
    final scale = result.scale;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppMetrics.margin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TierBanner(tier: result.tier, onShare: () => _share(context)),
          const SizedBox(height: 16),
          if (result.vitalReviewRequired) ...[
            const ReviewBanner(
              message:
                  'Some readings were missing or unclear - a clinician '
                  'should still review the patient.',
            ),
            const SizedBox(height: 16),
          ],
          if (widget.jumpedFromDanger) ...[
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
          if (scale != null)
            Text(
              '${scale.label} (vitals early-warning) score: '
              '${result.aggregate?.toString() ?? 'n/a'}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          const SizedBox(height: 16),

          // Tier 2: AI flag + description, always below the Tier 1 flag.
          if (_aiEnabled) ...[
            if (_ai != null) ...[
              _aiCard(context, result),
              const SizedBox(height: 10),
              BigButton(
                label: 'Ask about this result',
                icon: Icons.chat_bubble_outline,
                backgroundColor: AppColors.surface,
                onPressed: _onAsk,
              ),
            ] else if (_generating) ...[
              _loadingCard(),
            ] else ...[
              BigButton(
                label: 'Generate AI summary (Tier 2)',
                icon: Icons.smart_toy_outlined,
                backgroundColor: AppColors.surface,
                onPressed: _onGenerate,
              ),
              if (_genError)
                Text(
                  'AI generation failed. Tier 1 result is still valid.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ],
          const SizedBox(height: 16),
          if (widget.onEditVitals != null)
            BigButton(
              label: widget.jumpedFromDanger
                  ? 'Add vital signs'
                  : 'Edit vital signs',
              icon: Icons.edit,
              onPressed: widget.onEditVitals,
            ),
          const SizedBox(height: 10),
          BigButton(
            label: 'Edit danger signs',
            icon: Icons.warning_amber,
            backgroundColor: AppColors.surface,
            onPressed: widget.onEditDanger,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: widget.onRestart,
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

  Widget _loadingCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Loading MedGemma locally… first run can take about 30 seconds.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiCard(BuildContext context, TriageResult result) {
    final ai = _ai!;
    final escalated = ai.escalatedFrom(result.tier);
    final finalTier = escalated ? ai.suggestion! : result.tier;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.smart_toy_outlined,
                  color: AppColors.textSubdued),
              const SizedBox(width: 8),
              Text('AI analysis (MedGemma)',
                  style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              _aiChip(ai, result),
            ],
          ),
          if (escalated) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: finalTier.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'AI flags higher urgency: '
                'Tier 1 ${result.tier.name.toUpperCase()} · '
                'AI ${ai.suggestion!.name.toUpperCase()} → '
                'final ${finalTier.name.toUpperCase()}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: finalTier.color,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            ai.summary.isEmpty ? 'No summary returned.' : ai.summary,
            style: const TextStyle(fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 8),
          Text(
            'Clinician verification required. The AI is advisory — Tier 1 '
            'stands unless the AI raised urgency.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _aiChip(Tier2Assessment ai, TriageResult result) {
    final tier = ai.suggestion ?? result.tier;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tier.color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        ai.hasSuggestion ? tier.name.toUpperCase() : 'AGREE',
        style: TextStyle(
          color: tier.useDarkText ? Colors.black87 : Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}