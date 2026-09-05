import 'package:flutter/material.dart';

import '../../../triage/models.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/question_scaffold.dart';
import '../../widgets/segmented_yes_no.dart';
import '../../widgets/stepper_tiles.dart';

/// One focused vital-sign question (UI/UX plan §6.3).
/// Section B fields B1-B8, one per step.
class VitalsStep extends StatelessWidget {
  const VitalsStep({
    super.key,
    required this.step,
    required this.answers,
    required this.progress,
    required this.steps,
    required this.onChanged,
    required this.onRefresh,
    required this.onBack,
    required this.onRestart,
  });

  final int step;
  final TriageAnswers answers;
  final int progress;
  final int steps;
  final VoidCallback onChanged;

  /// Rebuilds the current step without advancing (used by in-step toggles
  /// such as "Not available").
  final VoidCallback onRefresh;
  final VoidCallback? onBack;
  final VoidCallback onRestart;

  String get _title {
    switch (step) {
      case 0:
        return 'Breaths per minute (breathing rate)';
      case 1:
        return 'Oxygen level (SpO2, %)';
      case 2:
        return 'Systolic blood pressure (mmHg)';
      case 3:
        return 'Heart rate (beats per minute)';
      case 4:
        return 'Temperature (°C)';
      case 5:
        return 'Is the patient on oxygen?';
      case 6:
        return 'Known COPD or CO2 retention?';
      default:
        return 'How alert is the patient?';
    }
  }

  String get _explain {
    switch (step) {
      case 0:
        return 'Count full breaths for 30 seconds and double it.';
      case 1:
        return 'A pulse oximeter shows this number, usually 95-100%.';
      case 2:
        return 'The higher number of a blood pressure reading.';
      case 3:
        return 'Count heartbeats for 30 seconds and double it.';
      case 4:
        return 'Usual is around 37 °C. Measure if a thermometer is available.';
      case 5:
        return 'Is the patient using oxygen now (mask, nasal tube)?';
      case 6:
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
          switch (step) {
            0 => _rr(),
            1 => _spo2(),
            2 => _sbp(),
            3 => _hr(),
            4 => _temp(),
            5 => _onOxygen(),
            6 => _copd(),
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

  void _continue() {
    switch (step) {
      case 0:
        answers.respiratoryRate ??= 16;
        break;
      case 1:
        if (!answers.spo2Missing) answers.spo2 ??= 96;
        break;
      case 2:
        answers.systolicBp ??= 120;
        break;
      case 3:
        answers.heartRate ??= 70;
        break;
      case 4:
        if (!answers.tempMissing) answers.temperature ??= 37.0;
        break;
      case 7:
        answers.consciousness ??= Avpu.alert;
        break;
    }
    onChanged();
  }

  Widget _rr() {
    return StepperTiles(
      value: answers.respiratoryRate ?? 16,
      onChanged: (v) {
        answers.respiratoryRate = v;
        onChanged();
      },
      min: 4,
      max: 60,
      step: 1,
      unit: '/min',
      quickValues: const [12, 16, 20, 24],
    );
  }

  Widget _spo2() {
    final value = answers.spo2;
    final missing = answers.spo2Missing;
    return StepperTiles(
      value: value ?? 96,
      onChanged: (v) {
        answers.spo2 = v.round().toDouble();
        answers.spo2Missing = false;
        onChanged();
      },
      min: 50,
      max: 100,
      step: 1,
      unit: '%',
      quickValues: const [92, 95, 98],
      canBeMissing: true,
      missing: missing,
      onMissing: () {
        if (!missing) {
          answers.spo2 = null;
          answers.spo2Missing = true;
        } else {
          answers.spo2 = 96;
          answers.spo2Missing = false;
        }
        onRefresh();
      },
    );
  }

  Widget _sbp() {
    return StepperTiles(
      value: answers.systolicBp ?? 120,
      onChanged: (v) {
        answers.systolicBp = v.round().toDouble();
        onChanged();
      },
      min: 60,
      max: 260,
      step: 5,
      unit: 'mmHg',
      quickValues: const [100, 120, 140],
    );
  }

  Widget _hr() {
    return StepperTiles(
      value: answers.heartRate ?? 70,
      onChanged: (v) {
        answers.heartRate = v.round().toDouble();
        onChanged();
      },
      min: 20,
      max: 220,
      step: 1,
      unit: 'bpm',
      quickValues: const [60, 72, 90],
    );
  }

  Widget _temp() {
    final value = answers.temperature;
    final missing = answers.tempMissing;
    return StepperTiles(
      value: value ?? 37.0,
      onChanged: (v) {
        answers.temperature = v;
        answers.tempMissing = false;
        onChanged();
      },
      min: 34.0,
      max: 43.0,
      step: 0.1,
      decimals: 1,
      unit: '°C',
      quickValues: const [36.0, 37.0, 38.0],
      canBeMissing: true,
      missing: missing,
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
      onChanged: (v) {
        answers.onOxygen = v;
        onChanged();
      },
    );
  }

  Widget _copd() {
    return SegmentedYesNo(
      value: answers.copdCo2Retention,
      onChanged: (v) {
        answers.copdCo2Retention = v;
        onChanged();
      },
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
          onTap: () {
            answers.consciousness = level;
            onChanged();
          },
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