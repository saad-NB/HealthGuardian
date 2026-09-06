import 'package:flutter/material.dart';

import '../../../triage/models.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/answer_chip.dart';
import '../../widgets/question_scaffold.dart';
import '../../widgets/segmented_yes_no.dart';
import '../../widgets/stepper_tiles.dart';

/// One focused vital-sign question (UI/UX plan §6.3), selected by [field].
/// The [age] bracket drives quick values and Continue defaults so each scale
/// (NEWS2 / Peds-NEWS2 / PEWS) collects exactly its own fields.
class VitalsStep extends StatelessWidget {
  const VitalsStep({
    super.key,
    required this.field,
    required this.age,
    required this.answers,
    required this.progress,
    required this.steps,
    required this.onChanged,
    required this.onRefresh,
    required this.onBack,
    required this.onRestart,
  });

  /// One of: rr, spo2, sbp, hr, temp, onOxygen, copd, avpu, capRefill, feeding.
  final String field;

  /// The age bracket this walkthrough is running for (scale is derived).
  final AgeGroup age;
  final TriageAnswers answers;
  final int progress;
  final int steps;
  final VoidCallback onChanged;

  /// Rebuilds the current step without advancing (used by in-step toggles
  /// such as "Not available").
  final VoidCallback onRefresh;
  final VoidCallback? onBack;
  final VoidCallback onRestart;

  bool get _neonatal => age.scale == VitalScale.pews;

  String get _title {
    switch (field) {
      case 'rr':
        return 'Breaths per minute (breathing rate)';
      case 'spo2':
        return 'Oxygen level (SpO2, %)';
      case 'sbp':
        return 'Systolic blood pressure (mmHg)';
      case 'hr':
        return 'Heart rate (beats per minute)';
      case 'temp':
        return 'Temperature (°C)';
      case 'onOxygen':
        return 'Is the patient on oxygen?';
      case 'copd':
        return 'Known COPD or CO2 retention?';
      case 'capRefill':
        return 'Capillary refill time';
      case 'feeding':
        return 'How alert is the baby and how is it feeding?';
      default:
        return 'How alert is the patient?';
    }
  }

  String get _explain {
    switch (field) {
      case 'rr':
        return 'Count full breaths for 30 seconds and double it.';
      case 'spo2':
        return 'A pulse oximeter shows this number, usually 95-100%.';
      case 'sbp':
        return 'The higher number of a blood pressure reading.';
      case 'hr':
        return 'Count heartbeats for 30 seconds and double it.';
      case 'temp':
        return 'Usual is around 37 °C. Measure if a thermometer is available.';
      case 'capRefill':
        return 'Press the fingernail or toe for 5 seconds and count how long '
            'the pink colour takes to return.';
      case 'feeding':
        return 'A baby who is not feeding or not waking is an emergency '
            'warning sign.';
      case 'copd':
        return 'Known lung disease such as COPD. Changes how oxygen '
            'level is judged.';
      default:
        return '';
    }
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
          Text(_title, style: Theme.of(context).textTheme.headlineMedium),
          if (_explain.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _explain,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 28),
          switch (field) {
            'rr' => _rr(),
            'spo2' => _spo2(),
            'sbp' => _sbp(),
            'hr' => _hr(),
            'temp' => _temp(),
            'onOxygen' => _onOxygen(),
            'copd' => _copd(),
            'capRefill' => _capRefill(),
            'feeding' => _feeding(),
            _ => _avpu(),
          },
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _continue,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  /// Value controls update the current step in place; only [onChanged]
  /// (the underlying Continue button) advances to the next question.
  void _update(void Function() mutate) {
    mutate();
    onRefresh();
  }

  void _continue() {
    switch (field) {
      case 'rr':
        answers.respiratoryRate ??= _neonatal ? 48 : 16;
        break;
      case 'spo2':
        if (!answers.spo2Missing) answers.spo2 ??= _neonatal ? 97 : 96;
        break;
      case 'sbp':
        answers.systolicBp ??= _neonatal ? 70 : 120;
        break;
      case 'hr':
        answers.heartRate ??= _neonatal ? 140 : 70;
        break;
      case 'temp':
        if (!answers.tempMissing) answers.temperature ??= 37.0;
        break;
      case 'onOxygen':
        answers.onOxygen ??= false;
        break;
      case 'copd':
        answers.copdCo2Retention ??= false;
        break;
      case 'capRefill':
        answers.capillaryRefill ??= CapillaryRefill.under2;
        break;
      case 'feeding':
        answers.neonatalConsciousness ??= NeonatalConsciousness.feedingWell;
        break;
      case 'avpu':
        answers.consciousness ??= Avpu.alert;
        break;
    }
    onChanged();
  }

  Widget _rr() {
    return StepperTiles(
      value: answers.respiratoryRate ?? (_neonatal ? 48 : 16),
      onChanged: (v) => _update(() => answers.respiratoryRate = v),
      min: 4,
      max: 60,
      step: 1,
      unit: '/min',
      quickValues: _neonatal ? const [30, 45, 60] : const [12, 16, 20, 24],
      manualMax: 200,
    );
  }

  Widget _spo2() {
    final value = answers.spo2;
    final missing = answers.spo2Missing;
    return StepperTiles(
      value: value ?? (_neonatal ? 97 : 96),
      onChanged: (v) => _update(() {
        answers.spo2 = v.round().toDouble();
        answers.spo2Missing = false;
      }),
      min: 50,
      max: 100,
      step: 1,
      unit: '%',
      quickValues: const [92, 95, 98],
      canBeMissing: true,
      missing: missing,
      manualMin: 1,
      manualMax: 100,
      onMissing: () {
        if (!missing) {
          answers.spo2 = null;
          answers.spo2Missing = true;
        } else {
          answers.spo2 = _neonatal ? 97 : 96;
          answers.spo2Missing = false;
        }
        onRefresh();
      },
    );
  }

  Widget _sbp() {
    return StepperTiles(
      value: answers.systolicBp ?? (_neonatal ? 70 : 120),
      onChanged: (v) => _update(() {
        answers.systolicBp = v.round().toDouble();
      }),
      min: 60,
      max: 260,
      step: 5,
      unit: 'mmHg',
      quickValues: _neonatal ? const [70, 80, 90] : const [100, 120, 140],
      manualMin: 20,
      manualMax: 400,
    );
  }

  Widget _hr() {
    return StepperTiles(
      value: answers.heartRate ?? (_neonatal ? 140 : 70),
      onChanged: (v) => _update(() {
        answers.heartRate = v.round().toDouble();
      }),
      min: 20,
      max: 220,
      step: 1,
      unit: 'bpm',
      quickValues: _neonatal ? const [120, 140, 160] : const [60, 72, 90],
      manualMin: 1,
      manualMax: 600,
    );
  }

  Widget _temp() {
    final value = answers.temperature;
    final missing = answers.tempMissing;
    return StepperTiles(
      value: value ?? 37.0,
      onChanged: (v) => _update(() {
        answers.temperature = v;
        answers.tempMissing = false;
      }),
      min: 34.0,
      max: 43.0,
      step: 0.1,
      decimals: 1,
      unit: '°C',
      quickValues: const [36.0, 37.0, 38.0],
      canBeMissing: true,
      missing: missing,
      manualMin: 25.0,
      manualMax: 45.0,
      onMissing: () {
        if (!missing) {
          answers.temperature = null;
          answers.tempMissing = true;
        } else {
          answers.temperature = 37.0;
          answers.tempMissing = false;
        }
        onRefresh();
      },
    );
  }

  Widget _onOxygen() {
    return SegmentedYesNo(
      value: answers.onOxygen,
      onChanged: (v) => _update(() => answers.onOxygen = v),
    );
  }

  Widget _copd() {
    return SegmentedYesNo(
      value: answers.copdCo2Retention,
      onChanged: (v) => _update(() => answers.copdCo2Retention = v),
    );
  }

  Widget _capRefill() {
    return Column(
      children: [
        for (final r in CapillaryRefill.values) ...[
          AnswerChip(
            label: r.label,
            detail: r.detail,
            icon: switch (r) {
              CapillaryRefill.under2 => Icons.bolt,
              CapillaryRefill.twoTo3 => Icons.schedule,
              CapillaryRefill.over3 => Icons.timer_off,
            },
            selected: answers.capillaryRefill == r,
            onSelected: () => _update(() => answers.capillaryRefill = r),
          ),
          const SizedBox(height: AppMetrics.answerGap),
        ],
      ],
    );
  }

  Widget _feeding() {
    return Column(
      children: [
        for (final c in NeonatalConsciousness.values) ...[
          AnswerChip(
            label: c.label,
            detail: c.detail,
            icon: switch (c) {
              NeonatalConsciousness.feedingWell => Icons.sentiment_satisfied,
              NeonatalConsciousness.drowsyPoor => Icons.sentiment_neutral,
              NeonatalConsciousness.unresponsiveNoFeed => Icons.sentiment_dissatisfied,
            },
            selected: answers.neonatalConsciousness == c,
            onSelected: () => _update(() => answers.neonatalConsciousness = c),
          ),
          const SizedBox(height: AppMetrics.answerGap),
        ],
      ],
    );
  }

  Widget _avpu() {
    return Column(
      children: [
        for (final level in Avpu.values) ...[
          _avpuTile(level),
          const SizedBox(height: AppMetrics.answerGap),
        ],
      ],
    );
  }

  Widget _avpuTile(Avpu level) {
    final selected = answers.consciousness == level;
    return Semantics(
      button: true,
      selected: selected,
      label: '${level.label}: ${level.detail}',
      child: Material(
        color: selected ? AppColors.teal700 : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _update(() => answers.consciousness = level),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: AppMetrics.minTouch,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  switch (level) {
                    Avpu.alert => Icons.person,
                    Avpu.voice => Icons.record_voice_over,
                    Avpu.pain => Icons.touch_app,
                    Avpu.unresponsive => Icons.nightlight,
                  },
                  color: AppColors.textPrimary,
                  size: 28,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${level.label} (${level.letter})',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        level.detail,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSubdued,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle,
                      color: AppColors.textPrimary, size: 26),
              ],
            ),
          ),
        ),
      ),
    );
  }
}