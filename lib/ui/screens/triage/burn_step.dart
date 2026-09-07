import 'package:flutter/material.dart';

import '../../../triage/burn_profile.dart';
import '../../../triage/models.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/answer_chip.dart';
import '../../widgets/burn_body_map.dart';
import '../../widgets/question_scaffold.dart';
import '../../widgets/segmented_yes_no.dart';
import '../../widgets/stepper_tiles.dart';

/// Section H — burn module (spec §11 H1–H8, operative §22), Phase 1/3 scope.
///
/// A single scrollable step collecting the simplified H1–H8 set: cause, time
/// since injury, a tap-to-fill Lund-Browder body figure (H3/H4 replacement),
/// depth, airway signs, circumferential, and chemical/electrical critical
/// site. A collapsed "enter % manually" fallback is kept for measured values.
class BurnStep extends StatefulWidget {
  const BurnStep({
    super.key,
    required this.answers,
    required this.progress,
    required this.steps,
    required this.onAdvanced,
    required this.onRefresh,
    required this.onBack,
    required this.onRestart,
  });

  final TriageAnswers answers;
  final int progress;
  final int steps;
  final VoidCallback onAdvanced;
  final VoidCallback onRefresh;
  final VoidCallback? onBack;
  final VoidCallback onRestart;

  @override
  State<BurnStep> createState() => _BurnStepState();
}

class _BurnStepState extends State<BurnStep> {
  double? _manualPercent;

  BurnProfile get _profile =>
      BurnProfile.forAge(widget.answers.ageGroup);

  void _toggleRegion(Set<(BodySide, BurnRegion)> next) {
    setState(() {
      _manualPercent = null;
      widget.answers.burn.shaded
        ..clear()
        ..addAll(next);
      widget.answers.burn.syncFromShaded(_profile);
    });
    widget.onRefresh();
  }

  void _setManualPercent(double v) {
    setState(() {
      widget.answers.burn.clearShaded(_profile);
      widget.answers.burn.tbsaPercent = v;
    });
    widget.onRefresh();
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
            'Wound or burn details',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Tap the body diagram to shade burned skin — the app sums the '
            'area automatically. Answer the rest as well as you can.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          _title(context, 'What caused it?'),
          for (final c in BurnCause.values) ...[
            AnswerChip(
              label: c.label,
              detail: c.detail,
              icon: _causeIcon(c),
              selected: widget.answers.burn.cause == c,
              onSelected: () => _set(() => widget.answers.burn.cause = c),
            ),
            const SizedBox(height: AppMetrics.answerGap),
          ],
          const SizedBox(height: 12),
          _title(context, 'When did it happen?'),
          for (final t in BurnTimeframe.values) ...[
            AnswerChip(
              label: t.label,
              selected: widget.answers.burn.timeSinceInjury == t,
              icon: Icons.schedule,
              onSelected: () =>
                  _set(() => widget.answers.burn.timeSinceInjury = t),
            ),
            const SizedBox(height: AppMetrics.answerGap),
          ],
          const SizedBox(height: 12),
          _title(context, 'Which areas are burned?'),
          BurnBodyMap(
            profile: _profile,
            shaded: widget.answers.burn.shaded,
            onChanged: _toggleRegion,
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            shape: const Border(),
            collapsedShape: const Border(),
            title: const Text('Prefer entering the % by hand?'),
            children: [
              Text(
                'Tap to measure, or pick from the palm-size quick values.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              _tbsa(),
            ],
          ),
          const SizedBox(height: 16),
          _title(context, 'How deep is the burn?'),
          for (final d in BurnDepth.values) ...[
            AnswerChip(
              label: d.label,
              detail: d.detail,
              icon: switch (d) {
                BurnDepth.superficial => Icons.local_fire_department,
                BurnDepth.partial => Icons.water_damage,
                BurnDepth.deepPartial => Icons.invert_colors,
                BurnDepth.full => Icons.bolt,
                BurnDepth.unsure => Icons.help_outline,
              },
              selected: widget.answers.burn.depth == d,
              onSelected: () => _set(() => widget.answers.burn.depth = d),
            ),
            const SizedBox(height: AppMetrics.answerGap),
          ],
          const SizedBox(height: 12),
          _title(context, 'Any breathing or airway concern?'),
          _yesNo(widget.answers.burn.airwaySigns,
              (v) => _set(() => widget.answers.burn.airwaySigns = v ?? false)),
          const SizedBox(height: 16),
          _title(context,
              'Is the burn all around a limb or the chest (circumferential)?'),
          _yesNo(widget.answers.burn.circumferential,
              (v) => _set(() => widget.answers.burn.circumferential =
                  v ?? false)),
          if (widget.answers.burn.cause?.isChemicalOrElectrical ??
              false) ...[
            const SizedBox(height: 16),
            _title(context, 'Does it involve the eyes, mouth, or perineum?'),
            _yesNo(
                widget.answers.burn.chemicalElectricalCriticalSite,
                (v) => _set(() => widget.answers.burn
                        .chemicalElectricalCriticalSite =
                    v ?? false)),
          ],
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: widget.onAdvanced,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Widget _title(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _yesNo(bool? value, ValueChanged<bool?> onChanged) {
    return SegmentedYesNo(
      value: value,
      onChanged: (v) {
        onChanged(v);
        widget.onRefresh();
      },
    );
  }

  void _set(void Function() mutate) {
    mutate();
    widget.onRefresh();
    setState(() {});
  }

  IconData _causeIcon(BurnCause c) => switch (c) {
        BurnCause.flame => Icons.local_fire_department,
        BurnCause.scald => Icons.water,
        BurnCause.chemical => Icons.science,
        BurnCause.electrical => Icons.bolt,
        BurnCause.contact => Icons.touch_app,
        BurnCause.other => Icons.help_outline,
      };

  Widget _tbsa() {
    final value = _manualPercent ?? (widget.answers.burn.tbsaPercent > 0
        ? widget.answers.burn.tbsaPercent
        : 1);
    return StepperTiles(
      value: value,
      onChanged: (v) => _setManualPercent(v),
      min: 1,
      max: 100,
      step: 1,
      decimals: value != value.roundToDouble() ? 1 : 0,
      unit: '%',
      quickValues: const [1, 2, 5, 10],
      manualMin: 1,
      manualMax: 100,
    );
  }
}