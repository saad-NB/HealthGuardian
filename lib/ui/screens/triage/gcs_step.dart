import 'package:flutter/material.dart';

import '../../../triage/models.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/question_scaffold.dart';

/// Section C — GCS pickers, shown only when indicated (AVPU != Alert, A1
/// danger sign, or chief complaint suggesting head injury).
/// Three sequential questions: Eye, Verbal, Motor; each selection updates
/// the component in place; only Continue advances (spec §6).
class GcsStep extends StatelessWidget {
  const GcsStep({
    super.key,
    required this.component,
    required this.answers,
    required this.progress,
    required this.steps,
    required this.onChanged,
    required this.onRefresh,
    required this.onBack,
    required this.onRestart,
  });

  /// 'eye', 'verbal', or 'motor'.
  final String component;
  final TriageAnswers answers;
  final int progress;
  final int steps;
  final VoidCallback onChanged;
  final VoidCallback onRefresh;
  final VoidCallback? onBack;
  final VoidCallback onRestart;

  String get _title => switch (component) {
        'eye' => 'Eye opening',
        'verbal' => 'Verbal response',
        'motor' => 'Motor response',
        _ => 'GCS component',
      };

  String get _explain => switch (component) {
        'eye' =>
          'Does the patient open their eyes spontaneously, to sound, '
          'to pain, or not at all?',
        'verbal' =>
          'Can the patient speak clearly, or are they confused / making '
          'sounds / silent?',
        'motor' =>
          'Can the patient obey commands, localise pain, withdraw from '
          'pain, or is there an abnormal response?',
        _ => '',
      };

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
          const SizedBox(height: 4),
          Text(_explain, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 28),
          ..._options(),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: onChanged,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  List<Widget> _options() {
    return switch (component) {
      'eye' => [
          _tile(Icons.visibility, 'Spontaneous', 'Opens eyes by itself', 4),
          _tile(Icons.record_voice_over, 'Voice', 'Opens when spoken to', 3),
          _tile(Icons.touch_app, 'Pain', 'Opens only to pain', 2),
          _tile(Icons.block, 'None', 'No eye opening', 1),
        ],
      'verbal' => [
          _tile(Icons.check_circle, 'Oriented', 'Knows name, place, date', 5),
          _tile(Icons.help_outline, 'Confused', 'Converses but disoriented', 4),
          _tile(Icons.short_text, 'Words', 'Makes recognisable words', 3),
          _tile(Icons.volume_down, 'Sounds', 'Makes sounds only', 2),
          _tile(Icons.block, 'None', 'No verbal response', 1),
        ],
      'motor' => [
          _tile(Icons.back_hand, 'Obeys', 'Follows simple commands', 6),
          _tile(Icons.gps_fixed, 'Localises', 'Moves toward a pain source', 5),
          _tile(Icons.arrow_upward, 'Withdraws', 'Pulls away from pain', 4),
          _tile(Icons.compress, 'Flexion', 'Abnormal bending of arms', 3),
          _tile(Icons.arrow_outward, 'Extension', 'Straightening of arms', 2),
          _tile(Icons.block, 'None', 'No motor response', 1),
        ],
      _ => [],
    };
  }

  Widget _tile(IconData icon, String label, String detail, int score) {
    final current = switch (component) {
      'eye' => answers.gcsEye,
      'verbal' => answers.gcsVerbal,
      'motor' => answers.gcsMotor,
      _ => null,
    };
    final selected = current == score;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label: $detail ($score)',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Material(
          color: selected ? AppColors.teal700 : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () {
              switch (component) {
                case 'eye':
                  answers.gcsEye = score;
                case 'verbal':
                  answers.gcsVerbal = score;
                case 'motor':
                  answers.gcsMotor = score;
              }
              onRefresh();
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              constraints: const BoxConstraints(minHeight: AppMetrics.minTouch),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(icon, size: 30, color: AppColors.textPrimary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            )),
                        Text(detail,
                            style: const TextStyle(
                              fontSize: 15,
                              color: AppColors.textSubdued,
                            )),
                      ],
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.check_circle,
                        color: AppColors.textPrimary, size: 28),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}