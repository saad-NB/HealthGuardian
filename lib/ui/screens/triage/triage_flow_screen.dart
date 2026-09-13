import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../services/tier2_service.dart';
import '../../../state/app_state.dart';
import '../../../triage/engine.dart';
import '../../../triage/models.dart';
import '../../../triage/record.dart';
import '../../../triage/record_store.dart';
import '../../../triage/tier2.dart';
import '../../../vitals/measurement_session_view.dart';
import '../../../vitals/models.dart' as vitals;
import '../../../vitals/sessions.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/answer_chip.dart';
import '../../widgets/question_scaffold.dart';
import '../../widgets/stepper_tiles.dart';
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

/// Age bracket gate / patient details (name, exact age, sex).
class PatientInfoNode extends Node {
  const PatientInfoNode();
}

/// Danger-sign gate.
class DangerNode extends Node {
  const DangerNode();
}

/// Chief complaint (Section D1) picker menu.
class ComplaintNode extends Node {
  const ComplaintNode();
}

/// "Any other problems?" loop-back prompt shown after each complaint round.
class MoreProblemsNode extends Node {
  const MoreProblemsNode();
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
  // Any selected complaint pipeline may be fever; the screen also shows when
  // temperature or SpO2 was not measured.
  if (a.answeredComplaints.contains(ChiefComplaint.fever)) return true;
  if (a.tempMissing || a.spo2Missing) return true;
  if (a.sepsis.f1 == true) return true;
  return false;
}

/// Builds the ordered walkthrough node list for the current answers.
List<Node> _buildNodes(TriageAnswers a) {
  final nodes = <Node>[
    const PatientInfoNode(),
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

  // Probes for the complaint currently being worked through.
  final activeBranch = a.activeComplaint?.branch;
  if (activeBranch != null) {
    nodes.add(ProbesNode(activeBranch));
  }

  // Loop back prompt: allows collecting more complaints.
  if (a.answeredComplaints.isNotEmpty) {
    nodes.add(const MoreProblemsNode());
  }

  // Sepsis when engaged.
  if (_sepsisEngaged(a)) {
    nodes.add(const SepsisNode());
  }

  // Burn module for any selected wound/burn complaint (spec §11/§22, step 7).
  if (a.answeredComplaints.contains(ChiefComplaint.wound)) {
    nodes.add(const BurnNode());
  }

  // Modifiers run after the merge candidates, before the result (§12/§13).
  nodes.add(const ModifiersNode());

  nodes.add(const ResultNode());
  return nodes;
}

/// Drives the adaptive triage walkthrough (UI/UX plan §5.2, §6–§9).
class TriageFlowScreen extends StatefulWidget {
  const TriageFlowScreen({
    super.key,
    this.store,
    this.app,
    this.tier2Service,
  });

  /// Record persistence; defaults to the encrypted local store. Injected in
  /// tests to avoid hitting the platform keystore.
  final TriageRecordStore? store;

  /// Shared state; used to open the post-triage chat when [tier2Service] runs.
  final AppState? app;

  /// Optional Tier 2 service. When null the result step hides AI features.
  final Tier2Service? tier2Service;

  @override
  State<TriageFlowScreen> createState() => _TriageFlowScreenState();
}

class _TriageFlowScreenState extends State<TriageFlowScreen> {
  final TriageAnswers _answers = TriageAnswers();
  late final TextEditingController _nameController = TextEditingController();
  late final TriageRecordStore _store =
      widget.store ?? TriageRecordStore();
  int _step = 0;

  /// The node currently on screen (captured during build). Advancement works
  /// from this identity so list-length changes don't skew the index math.
  Node? _shownNode;

  bool _jumpedToResult = false;

  /// Content fingerprint of the last record persisted for this session, so
  /// editing vitals and landing on the result again stores an updated record
  /// instead of a duplicate. Cleared on restart (§15 idempotency).
  String? _savedFingerprint;

  List<Node> get _nodes => _buildNodes(_answers);
  int get _nodeCount => _nodes.length;

  /// Fingerprint that ignores [TriageRecord.triageId] and timestamp (and the
  /// advisory [TriageRecord.tier2] block) so re-landing on the same result
  /// does not duplicate the record (ADR-014).
  String _contentFingerprint(TriageRecord r) {
    final json = jsonWithoutTier2(r.toJson())
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

  /// Upserts the same session record (idempotent by [TriageRecord.triageId])
  /// with the Tier 2 advisory block attached.
  Future<void> _saveTier2(TriageAnswers answers, Tier2Assessment ai) async {
    try {
      final base = TriageEngine.computeRecord(answers);
      await _store.save(base.withTier2(ai));
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

  /// Whether [a] and [b] name the same step. Nodes are rebuilt on every
  /// answer, and the list length can change (e.g. probes drop off once the
  /// active complaint is confirmed), so advancing must match by identity
  /// rather than by a raw list index.
  bool _sameNode(Node a, Node b) {
    if (a.runtimeType != b.runtimeType) return false;
    return switch ((a, b)) {
      (VitalNode(field: final fa), VitalNode(field: final fb)) => fa == fb,
      (GcsNode(component: final ca), GcsNode(component: final cb)) =>
        ca == cb,
      (ProbesNode(branch: final ba), ProbesNode(branch: final bb)) =>
        ba == bb,
      _ => true,
    };
  }

  void _next() {
    setState(() {
      final nodes = _buildNodes(_answers);
      var idx = _step;
      final shown = _shownNode;
      if (shown != null) {
        final match = nodes.indexWhere((n) => _sameNode(n, shown));
        if (match >= 0) idx = match;
      }
      _step = (idx + 1).clamp(0, nodes.length - 1);
      _jumpedToResult = false;
      if (nodes[_step] is ResultNode) {
        _saveResult(_answers);
      }
    });
  }

void _restart() => setState(() {
      _answers.reset();
      _nameController.clear();
      _step = 0;
      _jumpedToResult = false;
      _savedFingerprint = null;
    });

  /// "Measure with phone" (VITALS_SENSING §2): runs the shared sensor session
  /// and, on an accepted reading, fills the engine field + provenance so Tier 1
  /// scoring works identically to a manual entry.
  Future<vitals.VitalReading?> _measureVital(vitals.VitalKind kind) async {
    final session = createMeasurementSession(kind);
    if (session == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${kind.label} sensing is not available yet.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return null;
    }
    final reading = await launchMeasurementSession(
      context,
      session: session,
      cancelLabel: 'Enter manually instead',
    );
    if (reading == null) return null;
    final field = switch (kind) {
      vitals.VitalKind.heartRate => 'hr',
      vitals.VitalKind.breathingRate => 'rr',
    };
    if (mounted) {
      setState(() {
        _answers.recordSensorValue(
          field,
          reading.value,
          vitals.VitalMeasurement(
            source: vitals.VitalSource.sensor,
            confidence: reading.confidence,
            measuredAt: reading.measuredAt,
          ),
        );
      });
    }
    return reading;
  }

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
    _shownNode = node;
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
      case PatientInfoNode():
        return _patientInfo(index, count);
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
          onMeasure: _measureVital,
          measureSupported: vitalsSensingSupported,
        );
      case ComplaintNode():
        return ComplaintStep(
          answers: _answers,
          progress: index,
          steps: count,
          onAdvance: _next,
          onRefresh: () => setState(() {}),
          onBack: () => _goTo(index - 1),
          onRestart: _restart,
        );
      case MoreProblemsNode():
        return _moreProblems(index, count);
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
          app: widget.app,
          tier2Service: widget.tier2Service,
          onTier2Complete: (ai) => _saveTier2(_answers, ai),
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

  Widget _patientInfo(int index, int count) {
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
            'Tell us about the patient',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Optional details help label the record. You can leave them '
            'blank and continue.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              labelText: 'Patient name (optional)',
              hintText: 'e.g. Fatima or a case code',
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.20)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.20)),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Age',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          StepperTiles(
            value: (_answers.modifiers.ageYears ?? 0).toDouble(),
            onChanged: (v) => setState(() {
              _answers.modifiers.ageYears = v.round();
              final bracket = AgeGroup.fromYears(_answers.modifiers.ageYears);
              if (bracket != null) _answers.ageGroup = bracket;
            }),
            min: 0,
            max: 120,
            step: 1,
            unit: 'years',
            canBeMissing: true,
            missing: _answers.modifiers.ageYears == null,
            emptyLabel: '',
          ),
          const SizedBox(height: 12),
          AnswerChip(
            label: AgeGroup.neonate.label,
            detail: AgeGroup.neonate.detail,
            icon: Icons.child_care,
            selected: _answers.ageGroup == AgeGroup.neonate,
            onSelected: () => setState(() {
              _answers.ageGroup = AgeGroup.neonate;
              _answers.modifiers.ageYears = 0;
            }),
          ),
          const SizedBox(height: 8),
          Text(
            'Sex',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          for (final s in const [
            ('male', 'Male', Icons.male),
            ('female', 'Female', Icons.female),
            (null, 'Prefer not to say', Icons.help_outline),
          ]) ...[
            AnswerChip(
              label: s.$2,
              icon: s.$3,
              selected: _answers.modifiers.sex == s.$1,
              onSelected: () =>
                  setState(() => _answers.modifiers.sex = s.$1),
            ),
            const SizedBox(height: AppMetrics.answerGap),
          ],
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: () => setState(() {
              final name = _nameController.text.trim();
              _answers.patientName = name.isEmpty ? null : name;
              _answers.modifiers.ageAnswered = true;
              _answers.modifiers.sexAnswered = true;
              _next();
            }),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Widget _moreProblems(int index, int count) {
    return QuestionScaffold(
      progress: index + 1,
      steps: count,
      onBack: () => _goTo(index - 1),
      onUndo: () => _goTo(index - 1),
      onRestart: _restart,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Any other problems?',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'You can add more complaints or continue to the questions.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          AnswerChip(
            label: 'Yes, add another problem',
            icon: Icons.playlist_add,
            selected: false,
            onSelected: () => setState(() {
              _answers.activeComplaint = null;
              _goTo(_complaintIndex());
            }),
          ),
          const SizedBox(height: AppMetrics.answerGap),
          AnswerChip(
            label: 'No, that is all',
            icon: Icons.done_all,
            selected: false,
            onSelected: () {
              _answers.activeComplaint = null;
              _next();
            },
          ),
        ],
      ),
    );
  }

  int _complaintIndex() {
    final nodes = _buildNodes(_answers);
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i] is ComplaintNode) return i;
    }
    return 1;
  }
}