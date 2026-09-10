import 'models.dart';
import 'tier2.dart';

/// Storable JSON record of one completed Tier 1 triage (spec §15 / §21.9).
///
/// Round-trips through JSON for the encrypted local History store. The record
/// is a buildable snapshot: it captures the contributing scores, every
/// missing-parameter list, any substitutions applied, the modifier bump,
/// and the raw inputs used — enough to reproduce the result offline.
class TriageRecord {
  const TriageRecord({
    required this.triageId,
    required this.timestamp,
    required this.version,
    required this.finalTier,
    required this.contributingScores,
    required this.mergeReasons,
    required this.missingParams,
    required this.substitutionApplied,
    required this.safetyFlags,
    required this.modifiers,
    required this.gates,
    required this.inputs,
    this.tier2,
  });

  final String triageId;
  final DateTime timestamp;
  final String version;
  final TriageTier finalTier;

  /// Map of contributing module -> details (score/tier/components).
  final Map<String, dynamic> contributingScores;

  /// Human-readable merge reasons (shown in the result step).
  final List<String> mergeReasons;

  /// Every parameter that was missing/invalid during the walkthrough.
  final List<String> missingParams;

  /// True when any missing parameter received a context-based substitution.
  final bool substitutionApplied;

  /// safetyFlags: ['vitalReviewRequired'] etc.
  final List<String> safetyFlags;

  /// Modifier block: active flags + whether a bump was applied.
  final Map<String, dynamic> modifiers;

  /// gates: passed + triggered danger-sign list.
  final Map<String, dynamic> gates;

  /// Input snapshot for reproducibility (vitals, complaint, burn, modifiers).
  final Map<String, dynamic> inputs;

  /// Tier 2 advisory block (ADR-014, record v2.1). Null until the AI summary
  /// completes. [finalTier] stays authoritative Tier 1; this never overrides.
  final Tier2Assessment? tier2;

  /// True when Tier 2 suggested a more urgent tier than [finalTier].
  bool get aiEscalated =>
      tier2?.hasSuggestion == true && tier2!.escalatedFrom(finalTier);

  /// Copy with a Tier 2 assessment attached (same id, timestamp, version) so
  /// the store upserts one record for the session (idempotent by triageId).
  TriageRecord withTier2(Tier2Assessment assessment) => TriageRecord(
        triageId: triageId,
        timestamp: timestamp,
        version: version,
        finalTier: finalTier,
        contributingScores: contributingScores,
        mergeReasons: mergeReasons,
        missingParams: missingParams,
        substitutionApplied: substitutionApplied,
        safetyFlags: safetyFlags,
        modifiers: modifiers,
        gates: gates,
        inputs: inputs,
        tier2: assessment,
      );

  String get tierKey => finalTier.name;

  static String nowIso(DateTime dt) => dt.toUtc().toIso8601String();

  Map<String, dynamic> toJson({DateTime Function() now = DateTime.now}) {
    return {
      'triageId': triageId,
      'timestamp': nowIso(timestamp),
      'version': version,
      'finalTier': {
        'tier': tierKey,
        'urgency': finalTier.urgencyIndex + 1,
        'label': finalTier.label,
      },
      'contributingScores': contributingScores,
      'mergeReasons': mergeReasons,
      'missingParams': missingParams,
      'substitutionApplied': substitutionApplied,
      'safetyFlags': safetyFlags,
      'modifiers': modifiers,
      'gates': gates,
      'inputs': inputs,
      if (tier2 != null) 'tier2': tier2!.toJson(),
    };
  }

  /// Build a record from raw answers with only the fields the record owns.
  static TriageRecord fromAnswers({
    required TriageAnswers answers,
    required TriageTier finalTier,
    required Map<String, dynamic> contributingScores,
    required List<String> mergeReasons,
    required List<String> missingParams,
    required bool substitutionApplied,
    required List<String> safetyFlags,
    required Map<String, dynamic> modifiers,
    required Map<String, dynamic> gates,
    required Map<String, dynamic> inputs,
    String? triageId,
    DateTime? timestamp,
  }) {
    return TriageRecord(
      triageId: triageId ?? _newId(timestamp ?? DateTime.now()),
      timestamp: timestamp ?? DateTime.now(),
      version: '2.1',
      finalTier: finalTier,
      contributingScores: contributingScores,
      mergeReasons: mergeReasons,
      missingParams: missingParams,
      substitutionApplied: substitutionApplied,
      safetyFlags: safetyFlags,
      modifiers: modifiers,
      gates: gates,
      inputs: inputs,
    );
  }

  static String _newId(DateTime dt) {
    final micros = dt.microsecondsSinceEpoch;
    final noise = (micros * 2654435761) & 0xFFFFFFF;
    return 'tg-${micros.toRadixString(16)}-${noise.toRadixString(16)}';
  }

  /// Idempotent JSON re-hydration (for the History store). Tolerant: missing
  /// v2.1 fields (e.g. a legacy v2.0 record with no `tier2`) load as null.
  static TriageRecord fromJson(Map<String, dynamic> json) {
    final finalTier = TriageTier.values.firstWhere(
      (t) => t.name == (json['finalTier'] as Map<String, dynamic>)['tier'],
      orElse: () => TriageTier.p3,
    );
    final tier2Raw = json['tier2'];
    return TriageRecord(
      triageId: json['triageId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      version: json['version'] as String? ?? '2.0',
      finalTier: finalTier,
      contributingScores:
          Map<String, dynamic>.from(json['contributingScores'] as Map),
      mergeReasons: List<String>.from(json['mergeReasons'] as List),
      missingParams: List<String>.from(json['missingParams'] as List),
      substitutionApplied: json['substitutionApplied'] as bool? ?? false,
      safetyFlags: List<String>.from(json['safetyFlags'] as List),
      modifiers: Map<String, dynamic>.from(json['modifiers'] as Map),
      gates: Map<String, dynamic>.from(json['gates'] as Map),
      inputs: Map<String, dynamic>.from(json['inputs'] as Map),
      tier2: tier2Raw is Map<String, dynamic>
          ? Tier2Assessment.fromJson(tier2Raw)
          : null,
    );
  }

  /// Patient name/identifier captured at the start of the walkthrough, if any.
  String get patientName =>
      (inputs['patientName'] as String?)?.trim() ?? '';
}

/// Rebuilds a readable (non-JSON) context string for the Ask-AI chat when it
/// is opened from an existing History record. Mirrors [Tier2Payload]'s
/// `patientSummary` but is sourced from the stored snapshot, so a finished
/// record can be discussed even without the original [TriageAnswers].
///
/// The patient name is deliberately excluded: it labels the chat title, never
/// the model context.
String buildRecordContext(TriageRecord r) {
  final inputs = r.inputs;
  final b = StringBuffer()
    ..writeln('TRIAGE RECORD CONTEXT (decision support - not a diagnosis)');

  final ageName = inputs['age'] as String?;
  for (final g in AgeGroup.values) {
    if (g.name == ageName) {
      b.writeln('Age group: ${g.label}');
      break;
    }
  }
  b.writeln('Triage on: ${r.timestamp.toLocal().toString()}');

  final vitals = (inputs['vitals'] as Map?) ?? const {};
  final v = <String>[
    if (vitals['rr'] != null) 'RR ${vitals['rr']}/min',
    if (vitals['spo2'] != null)
      'SpO2 ${vitals['spo2']}%'
    else if (vitals['spo2Missing'] == true)
      'SpO2 not available',
    if (vitals['sbp'] != null) 'BP ${vitals['sbp']}',
    if (vitals['hr'] != null) 'HR ${vitals['hr']}/min',
    if (vitals['temp'] != null)
      'Temp ${vitals['temp']}C'
    else if (vitals['tempMissing'] == true)
      'Temp not available',
    if (vitals['consciousness'] != null)
      'AVPU ${vitals['consciousness']}',
    if (vitals['capillaryRefill'] != null)
      'Cap refill ${vitals['capillaryRefill']}',
    if (vitals['neonatalConsciousness'] != null)
      'Neonatal state ${vitals['neonatalConsciousness']}',
    if (vitals['onOxygen'] == true) 'On oxygen',
  ];
  if (v.isNotEmpty) b.writeln('Vitals: ${v.join(', ')}');

  final gcs = inputs['gcs'];
  if (gcs is List && gcs.length == 3 && gcs.every((x) => x is int)) {
    final eye = gcs[0] as int, verbal = gcs[1] as int, motor = gcs[2] as int;
    b.writeln('GCS: ${eye + verbal + motor}/15 (E$eye V$verbal M$motor)');
  }

  final complaints = <String>[
    if (inputs['complaint'] is String) inputs['complaint'] as String,
    for (final c in (inputs['additionalComplaints'] as List?) ?? const [])
      if (c is String) c,
  ];
  if (complaints.isNotEmpty) {
    b.writeln('Complaints: ${complaints.join(', ')}');
  }
  final notes = inputs['extraComplaintNotes'] as String?;
  if (notes != null && notes.trim().isNotEmpty) {
    b.writeln('Additional complaint notes: ${notes.trim()}');
  }

  final probes = inputs['probes'];
  if (probes is Map && probes.isNotEmpty) {
    final yes = probes.entries
        .where((e) => e.value == true)
        .map((e) => e.key.toString())
        .toList();
    if (yes.isNotEmpty) b.writeln('Concerning probes: ${yes.join(', ')}');
  }

  final mods = (inputs['modifiers'] as Map?) ?? const {};
  final ms = <String>[
    if (mods['sex'] != null) 'sex ${mods['sex']}',
    if (mods['pregnant'] == true) 'pregnant',
    if (mods['immunocompromised'] == true) 'immunocompromised',
    if (mods['cfsLevel'] != null) 'frailty scale ${mods['cfsLevel']}',
  ];
  if (ms.isNotEmpty) b.writeln('Modifiers: ${ms.join(', ')}');

  b.writeln('Tier 1 result: ${r.finalTier.label}.');
  if (r.mergeReasons.isNotEmpty) {
    b.writeln('Findings: ${r.mergeReasons.join('; ')}');
  }
  if (r.tier2 != null && r.tier2!.summary.isNotEmpty) {
    b.writeln('Earlier AI summary: ${r.tier2!.summary}');
  }
  if (r.safetyFlags.contains('vitalReviewRequired')) {
    b.writeln('NOTE: vitals review required - some measurements were missing.');
  }
  return b.toString();
}