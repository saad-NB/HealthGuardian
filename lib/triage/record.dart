import 'models.dart';

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
      version: '2.0',
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

  /// Idempotent JSON re-hydration (for the History store).
  static TriageRecord fromJson(Map<String, dynamic> json) {
    final finalTier = TriageTier.values.firstWhere(
      (t) => t.name == (json['finalTier'] as Map<String, dynamic>)['tier'],
      orElse: () => TriageTier.p3,
    );
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
    );
  }
}