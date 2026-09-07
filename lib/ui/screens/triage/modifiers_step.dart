import 'package:flutter/material.dart';

import '../../../triage/models.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/answer_chip.dart';
import '../../widgets/question_scaffold.dart';
import '../../widgets/segmented_yes_no.dart';
import '../../widgets/stepper_tiles.dart';

/// Section I — modifiers (spec §12 I1–I7). Optional risk factors that apply
/// a single bump-after-merge (§13 step 10) when any qualifying modifier is on.
///
/// I5 (MUAC) is shown only for children under 5; I6 (CFS) only for older
/// adults (≥65); I2 (sex) only gates I3 (pregnancy).
class ModifiersStep extends StatelessWidget {
  const ModifiersStep({
    super.key,
    required this.answers,
    required this.progress,
    required this.steps,
    required this.onAdvance,
    required this.onRefresh,
    required this.onBack,
    required this.onRestart,
  });

  final TriageAnswers answers;
  final int progress;
  final int steps;
  final VoidCallback onAdvance;
  final VoidCallback onRefresh;
  final VoidCallback? onBack;
  final VoidCallback onRestart;

  bool get _under5 {
    final years = answers.modifiers.ageYears;
    if (years != null) return years < 5;
    return answers.ageGroup?.isUnderFive ?? false;
  }

  bool get _is65Plus {
    final years = answers.modifiers.ageYears;
    if (years != null) return years >= 65;
    return answers.ageGroup?.isOlderAdult ?? false;
  }

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
            'Any extra risk factors?',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Optional — these can raise how urgently the patient needs to '
            'be seen. Choose "Not sure" if you cannot tell.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),

          // I1 — age (explicit, overrides the bracket for the engine bump).
          // Only meaningful on the NEWS2 track: children/neonates already
          // pick an age-bracketed peds scale (ADR-013), so no extra bump.
          if (answers.ageGroup?.scale == VitalScale.news2) ...[
            _title(context, 'Age (if known, in years)'),
            StepperTiles(
              value: (answers.modifiers.ageYears ?? 30).toDouble(),
              onChanged: (v) {
                answers.modifiers.ageYears = v.round();
                onRefresh();
              },
              min: 0,
              max: 120,
              step: 1,
              unit: 'y',
              quickValues: const [65, 70, 85],
              canBeMissing: true,
              missing: answers.modifiers.ageYears == null,
              onMissing: () {
                answers.modifiers.ageYears = null;
                onRefresh();
              },
            ),
            Text(
              '65 years and older raises urgency.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
          ],

          // I2 — sex (only gates pregnancy).
          _title(context, 'Biological sex (if relevant)'),
          for (final s in const [('male', 'Male'), ('female', 'Female')]) ...[
            AnswerChip(
              label: s.$2,
              icon: s.$1 == 'male' ? Icons.male : Icons.female,
              selected: answers.modifiers.sex == s.$1,
              onSelected: () {
                answers.modifiers.sex = s.$1;
                onRefresh();
              },
            ),
            const SizedBox(height: AppMetrics.answerGap),
          ],
          if (answers.modifiers.sex == null) ...[
            TextButton(
              onPressed: () {
                answers.modifiers.sex = 'female';
                onRefresh();
              },
              child: const Text('Prefer not to say / skip'),
            ),
          ],

          // I3 — pregnancy (only when sex is female).
          if (answers.modifiers.sex == 'female') ...[
            const SizedBox(height: 8),
            _title(context, 'Pregnant?'),
            _yesNo(
              value: answers.modifiers.pregnant,
              onChanged: (v) => answers.modifiers.pregnant = v,
            ),
          ],

          // I4 — immunocompromised.
          const SizedBox(height: 16),
          _title(context, 'Immunocompromised?'),
          Text(
            'e.g. HIV/AIDS, chemotherapy, long-term steroids, transplant.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          _yesNo(
            value: answers.modifiers.immunocompromised,
            onChanged: (v) => answers.modifiers.immunocompromised = v,
          ),

          // I5 — MUAC (children under 5).
          if (_under5) ...[
            const SizedBox(height: 16),
            _title(context, 'Mid-upper arm circumference (MUAC) in cm'),
            StepperTiles(
              value: answers.modifiers.muacCm ?? 12,
              onChanged: (v) {
                answers.modifiers.muacCm = v;
                onRefresh();
              },
              min: 5,
              max: 20,
              step: 0.5,
              decimals: 1,
              unit: 'cm',
              quickValues: const [11.5, 12.5, 13.5],
              manualMin: 1,
              manualMax: 40,
            ),
            Text(
              'Below 11.5 cm means severe malnutrition.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],

          // I6 — Clinical Frailty Scale (65+).
          if (_is65Plus) ...[
            const SizedBox(height: 16),
            _title(context, 'Clinical Frailty Scale (1–7)'),
            for (final level in CfsLevel.values) ...[
              AnswerChip(
                label: level.label,
                detail: level.detail,
                icon: Icons.elderly,
                selected: answers.modifiers.cfsLevel == level.value,
                onSelected: () {
                  answers.modifiers.cfsLevel = level.value;
                  onRefresh();
                },
              ),
              const SizedBox(height: AppMetrics.answerGap),
            ],
          ],

          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: onAdvance,
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

  Widget _yesNo({required bool? value, required ValueChanged<bool?> onChanged}) {
    return SegmentedYesNo(
      value: value,
      onChanged: (v) {
        onChanged(v);
        onRefresh();
      },
    );
  }
}

/// Clinical frailty scale helper (1–7), spec §12 I6.
enum CfsLevel {
  veryFit(1, 'Very fit', 'Exercises regularly, most energetic people'),
  well(2, 'Well', 'No active symptoms, but less fit than category 1'),
  managingWell(3, 'Managing well', 'Good health, medical problems are controlled'),
  vulnerable(4, 'Vulnerable', 'Not dependent but symptoms limit activity'),
  mildlyFrail(5, 'Mildly frail', 'Slowed up, dependent for higher-order IADLs'),
  moderatelyFrail(6, 'Moderately frail', 'Needs help with outdoor activities'),
  severelyFrail(7, 'Severely frail', 'Completely dependent for personal care');

  const CfsLevel(this.value, this.label, this.detail);

  final int value;
  final String label;
  final String detail;
}