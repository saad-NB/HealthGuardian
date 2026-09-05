import 'package:flutter/material.dart';

import '../../../triage/models.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/answer_chip.dart';
import '../../widgets/question_scaffold.dart';
import 'danger_signs_step.dart';
import 'result_step.dart';
import 'vitals_steps.dart';

/// Drives the linear triage walkthrough (UI/UX plan §5.2, §6).
///
/// Adult path: age → danger signs → 8 vitals steps → result.
/// Child/infant path: age → danger signs → result (Peds scales pending).
class TriageFlowScreen extends StatefulWidget {
  const TriageFlowScreen({super.key});

  @override
  State<TriageFlowScreen> createState() => _TriageFlowScreenState();
}

class _TriageFlowScreenState extends State<TriageFlowScreen> {
  final TriageAnswers _answers = TriageAnswers();
  int _step = 0;
  bool _jumpedToResult = false;

  static const int _ageIndex = 0;
  static const int _dangerIndex = 1;
  static const int _vitalStart = 2;
  static const int _vitalStepCount = 8;

  int get _vitalCount => _answers.ageGroup?.usesNews2 ?? false
      ? _vitalStepCount
      : 0;
  int get _resultIndex => _vitalStart + _vitalCount;
  int get _stepCount => _resultIndex + 1;

  void _goTo(int index) => setState(() {
        _step = index;
        _jumpedToResult = false;
      });

  void _next() {
    if (_step < _stepCount - 1) {
      _goTo(_step + 1);
    } else {
      _goTo(_resultIndex);
    }
  }

  void _undo() => _goTo((_step - 1).clamp(0, _stepCount - 1));

  void _restart() => setState(() {
        _answers.reset();
        _step = _ageIndex;
        _jumpedToResult = false;
      });

  void _selectAge(AgeGroup g) {
    setState(() => _answers.ageGroup = g);
    _next();
  }

  void _jumpToResult() {
    setState(() {
      _step = _resultIndex;
      _jumpedToResult = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Triage')),
      body: _buildStep(),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _ageIndex:
        return _ageGate();
      case _dangerIndex:
        return DangerSignsStep(
          answers: _answers,
          progress: _step,
          steps: _stepCount,
          onContinue: () => _next(),
          onResult: _jumpToResult,
          onBack: () => _goTo(_ageIndex),
          onRestart: _restart,
        );
      default:
        if (_step == _resultIndex) {
          return ResultStep(
            answers: _answers,
            onEditVitals: _vitalCount > 0 ? () => _goTo(_vitalStart) : null,
            onEditDanger: () => _goTo(_dangerIndex),
            onRestart: _restart,
            jumpedFromDanger: _jumpedToResult,
          );
        }
        final vitalStep = _step - _vitalStart;
        return VitalsStep(
          step: vitalStep,
          answers: _answers,
          progress: _step,
          steps: _stepCount,
          onChanged: () => _next(),
          onRefresh: () => setState(() {}),
          onBack: _step > _vitalStart
              ? () => _goTo(_step - 1)
              : () => _goTo(_dangerIndex),
          onRestart: _restart,
        );
    }
  }

  Widget _ageGate() {
    return QuestionScaffold(
      progress: _step + 1,
      steps: _stepCount,
      onBack: null,
      onUndo: _undo,
      onRestart: _restart,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Who is this for?',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          for (final g in AgeGroup.values) ...[
            AnswerChip(
              label: g.label,
              detail: g.detail,
              icon: switch (g) {
                AgeGroup.infant => Icons.child_care,
                AgeGroup.child => Icons.child_friendly,
                AgeGroup.adult => Icons.person,
                AgeGroup.olderAdult => Icons.elderly,
              },
              selected: _answers.ageGroup == g,
              onSelected: () => _selectAge(g),
            ),
            const SizedBox(height: AppMetrics.answerGap),
          ],
        ],
      ),
    );
  }
}