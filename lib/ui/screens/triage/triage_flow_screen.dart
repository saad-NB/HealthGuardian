import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../triage/engine.dart';
import '../../../triage/models.dart';
import '../../../triage/record.dart';
import '../../../triage/record_store.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/answer_chip.dart';
import '../../widgets/question_scaffold.dart';
import 'burn_step.dart';
import 'complaint_step.dart';
import 'danger_signs_step.dart';
import 'gcs_step.dart';
import 'modifiers_step.dart';
import 'probes_step.dart';
import 'result_step.dart';
import 'sepsis_step.dart';
import 'vitals_steps.dart';

/// One node in the dynamic triage walkthrough (spec §2 flow).
///
/// The step list is rebuilt as answers change so the walkthrough stays
/// adaptive (e.g. GCS appears only when indicated; sepsis only when engaged).
sealed class Node {
  const Node();
}

/// Vitals field step ('rr', 'spo2', 'sbp', 'hr', 'temp', 'onOxygen',
/// 'copd', 'capRefill', 'feeding', 'avpu').
class VitalNode extends Node {
  const VitalNode(this.field);
  final String field;
}

/// Final result.
class ResultNode extends Node {
  const ResultNode();
}

/// Age bracket gate.
class AgeNode extends Node {
  const AgeNode();
}

/// Danger-sign gate.
class DangerNode extends Node {
  const DangerNode();
}

/// Chief complaint (Section D1).
class ComplaintNode extends Node {
  const ComplaintNode();
}

/// GCS component ('eye', 'verbal', 'motor').
class GcsNode extends Node {
  const GcsNode(this.component);
  final String component;
}

/// Section E probes for a branch.
class ProbesNode extends Node {
  const ProbesNode(this.branch);
  final ProbeBranch branch;
}

/// Section F sepsis screen.
class SepsisNode extends Node {
  const SepsisNode();
}

/// Section H burn module (shown only for the wound/burn complaint).
class BurnNode extends Node {
  const BurnNode();
}

/// Section I modifiers (bump-after-merge).
class ModifiersNode extends Node {
  const ModifiersNode();
}

/// Whether GCS is indicated at all (spec §6).
bool _gcsIndicated(TriageAnswers a) {
  if (a.consciousness != null && a.consciousness != Avpu.alert) return true;
  if (a.chiefComplaint?.suggestsHeadInjury ?? false) return true;
  if (a.dangerSigns.isNotEmpty && a.chiefComplaint == ChiefComplaint.headache) {
    return true;
  }
  return false;
}

/// Whether the sepsis screen is engaged (spec §9 gate).
bool _sepsisEngaged(TriageAnswers a) {
  if (a.chiefComplaint == ChiefComplaint.fever) return true;
  // Shown when temperature or SpO2 was not measured.
  if (a.tempMissing || a.spo2Missing) return true;
  if (a.sepsis.f1 == true) return true;
  return false;
}

/// Builds the ordered walkthrough node list for the current answers.
List<Node> _buildNodes(TriageAnswers a) {
  final nodes = <Node>[
    const AgeNode(),
    const DangerNode(),
  ];

  // Vitals, scaled by age bracket.
  final age = a.ageGroup;
  if (age != null) {
    switch (age.scale) {
      case VitalScale.news2:
        nodes.addAll(const [
          VitalNode('rr'),
          VitalNode('spo2'),
          VitalNode('sbp'),
          VitalNode('hr'),
          VitalNode('temp'),
          VitalNode('onOxygen'),
          VitalNode('copd'),
          VitalNode('avpu'),
        ]);
      case VitalScale.pedsNews2:
        nodes.addAll(const [
          VitalNode('rr'),
          VitalNode('spo2'),
          VitalNode('hr'),
          VitalNode('temp'),
          VitalNode('capRefill'),
          VitalNode('onOxygen'),
          VitalNode('avpu'),
        ]);
      case VitalScale.pews:
        nodes.addAll(const [
          VitalNode('rr'),
          VitalNode('spo2'),
          VitalNode('hr'),
          VitalNode('temp'),
          VitalNode('feeding'),
          VitalNode('onOxygen'),
        ]);
    }
  }

  // Chief complaint.
  nodes.add(const ComplaintNode());

  // GCS when indicated.
  if (_gcsIndicated(a)) {
    nodes.addAll(const [
      GcsNode('eye'),
      GcsNode('verbal'),
      GcsNode('motor'),
    ]);
  }

  // Probes for a branch.
  final branch = a.chiefComplaint?.branch;
  if (branch != null) {
    nodes.add(ProbesNode(branch));
  }

  // Sepsis when engaged.
  if (_sepsisEngaged(a)) {
    nodes.add(const SepsisNode());
  }

  // Burn module for the wound/burn complaint (spec §11/§22, step 7).
  if (a.chiefComplaint == ChiefComplaint.wound) {
    nodes.add(const BurnNode());
  }

  // Modifiers run after the merge candidates, before the result (§12/§13).
  nodes.add(const ModifiersNode());

  nodes.add(const ResultNode());
  return nodes;
}

/// Drives the adaptive triage walkthrough (UI/UX plan §5.2, §6–§9).
class TriageFlowScreen extends StatefulWidget {
  const TriageFlowScreen({super.key, this.store});

  /// Record persistence; defaults to the encrypted local store. Injected in
  /// tests to avoid hitting the platform keystore.
  final TriageRecordStore? store;

  @override
  State<TriageFlowScreen> createState() => _TriageFlowScreenState();
}

class _TriageFlowScreenState extends State<TriageFlowScreen> {
  final TriageAnswers _answers = TriageAnswers();
  late final TriageRecordStore _store =
      widget.store ?? TriageRecordStore();
  int _step = 0;
  bool _jumpedToResult = false;

  /// Content fingerprint of the last record persisted for this session, so
  /// editing vitals and landing on the result again stores an updated record
  /// instead of a duplicate. Cleared on restart (§15 idempotency).
  String? _savedFingerprint;

  List<Node> get _nodes => _buildNodes(_answers);
  int get _nodeCount => _nodes.length;

  /// Fingerprint that ignores [TriageRecord.triageId] and timestamp so
  /// re-landing on the same result does not duplicate the record.
  String _contentFingerprint(TriageRecord r) {
    final json = r.toJson()
      ..remove('triageId')
      ..remove('timestamp');
    return jsonEncode(json);
  }

  Future<void> _saveResult(TriageAnswers answers) async {
    try {
      final record = TriageEngine.computeRecord(answers);
      final fingerprint = _contentFingerprint(record);
      if (fingerprint == _savedFingerprint) return;
      _savedFingerprint = fingerprint;
      await _store.save(record);
    } catch (_) {
      // Fire-and-forget: a failed save must not block the walkthrough.
    }
  }

  void _goTo(int index) => setState(() {
        _step = index.clamp(0, _nodeCount - 1);
        _jumpedToResult = false;
        if (_nodes[_step] is ResultNode) {
          _saveResult(_answers);
        }
      });

  void _next() {
    if (_step < _nodeCount - 1) {
      _goTo(_step + 1);
    } else {
      _goTo(_nodeCount - 1);
    }
  }

  void _restart() => setState(() {
        _answers.reset();
        _step = 0;
        _jumpedToResult = false;
        _savedFingerprint = null;
      });

  void _dangerContinue() {
    if (_answers.dangerSigns.isNotEmpty) {
      setState(() {
        _step = _nodeCount - 1;
        _jumpedToResult = true;
      });
      _saveResult(_answers);
    } else {
      _next();
    }
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _buildNodes(_answers);
    final idx = _step.clamp(0, nodes.length - 1);
    final node = nodes[idx];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Triage')),
      body: _buildNode(node, idx, nodes.length),
    );
  }

  int get _vitalStartIndex {
    final nodes = _buildNodes(_answers);
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i] is VitalNode) return i;
    }
    return -1;
  }

  Widget _buildNode(Node node, int index, int count) {
    switch (node) {
      case AgeNode():
        return _ageGate(index, count);
      case DangerNode():
        return DangerSignsStep(
          answers: _answers,
          progress: index,
          steps: count,
          onContinue: _dangerContinue,
          onBack: () => _goTo(index - 1),
          onRestart: _restart,
        );
      case VitalNode(:final field):
        return VitalsStep(
          field: field,
          age: _answers.ageGroup ?? AgeGroup.adult,
          answers: _answers,
          progress: index,
          steps: count,
          onChanged: _next,
          onRefresh: () => setState(() {}),
          onBack: index > 0 ? () => _goTo(index - 1) : null,
          onRestart: _restart,
        );
      case ComplaintNode():
        return ComplaintStep(
          answers: _answers,
          progress: index,
          steps: count,
          onAdvance: _next,
          onBack: () => _goTo(index - 1),
          onRestart: _restart,
        );
      case GcsNode(:final component):
        return GcsStep(
          component: component,
          answers: _answers,
          progress: index,
          steps: count,
          onChanged: _next,
          onRefresh: () => setState(() {}),
          onBack: () => _goTo(index - 1),
          onRestart: _restart,
        );
      case ProbesNode(:final branch):
        return ProbesStep(
          branch: branch,
          answers: _answers,
          progress: index,
          steps: count,
          onContinue: _next,
          onBack: () => _goTo(index - 1),
          onRestart: _restart,
        );
      case SepsisNode():
        return SepsisStep(
          answers: _answers,
          progress: index,
          steps: count,
          onContinue: _next,
          onBack: () => _goTo(index - 1),
          onRestart: _restart,
        );
      case BurnNode():
        return BurnStep(
          answers: _answers,
          progress: index,
          steps: count,
          onAdvanced: _next,
          onRefresh: () => setState(() {}),
          onBack: () => _goTo(index - 1),
          onRestart: _restart,
        );
      case ModifiersNode():
        return ModifiersStep(
          answers: _answers,
          progress: index,
          steps: count,
          onAdvance: _next,
          onRefresh: () => setState(() {}),
          onBack: () => _goTo(index - 1),
          onRestart: _restart,
        );
      case ResultNode():
        final vitalCount =
            _buildNodes(_answers).whereType<VitalNode>().length;
        return ResultStep(
          answers: _answers,
          onEditVitals: vitalCount > 0
              ? () => _goTo(vitalCount > 0 ? _vitalStartIndex : index)
              : null,
          onEditDanger: () => _goTo(_dangerIndex()),
          onRestart: _restart,
          jumpedFromDanger: _jumpedToResult,
        );
    }
  }

  int _dangerIndex() {
    final nodes = _buildNodes(_answers);
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i] is DangerNode) return i;
    }
    return 0;
  }

  Widget _ageGate(int index, int count) {
    return QuestionScaffold(
      progress: index + 1,
      steps: count,
      onBack: null,
      onUndo: () => _goTo(index - 1),
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
              icon: switch (g.scale) {
                VitalScale.pews => Icons.child_care,
                VitalScale.pedsNews2 => Icons.child_friendly,
                VitalScale.news2 => g == AgeGroup.olderAdult
                    ? Icons.elderly
                    : Icons.person,
              },
              selected: _answers.ageGroup == g,
              onSelected: () {
                setState(() => _answers.ageGroup = g);
                _next();
              },
            ),
            const SizedBox(height: AppMetrics.answerGap),
          ],
        ],
      ),
    );
  }
}