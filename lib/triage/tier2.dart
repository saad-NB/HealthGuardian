import 'models.dart';

/// Structured Tier 2 input payload (spec §16) sent to MedGemma.
///
/// Pure Dart (framework-free) so payload construction, the escalation-only
/// merge, and context rendering are unit-tested headless (ADR-014).
class Tier2Payload {
  Tier2Payload(this._data);

  final Map<String, dynamic> _data;

  Map<String, dynamic> toJson() => _data;

  /// Builds the spec §16 payload from the walking answers + Tier 1 result.
  factory Tier2Payload.from(TriageAnswers a, TriageResult result) {
    final age = a.ageGroup;
    final gcsTotal = (a.gcsEye != null && a.gcsVerbal != null && a.gcsMotor != null)
        ? a.gcsEye! + a.gcsVerbal! + a.gcsMotor!
        : null;
    final mods = a.modifiers;

    return Tier2Payload({
      'spec': 'spec-16-tier2-payload',
      'patientContext': {
        'ageGroup': age?.label,
        'ageBand': age != null ? ageBandText(age) : null,
        'sex': mods.sex,
        'pregnant': mods.pregnant,
        'immunocompromised': mods.immunocompromised,
        'muacCm': mods.muacCm,
        'cfsFrailty': mods.cfsLevel,
      },
      'vitals': {
        'respiratoryRatePerMin': a.respiratoryRate,
        'spo2Percent': a.spo2,
        'spo2Missing': a.spo2Missing,
        'systolicBpMmHg': a.systolicBp,
        'heartRatePerMin': a.heartRate,
        'temperatureC': a.temperature,
        'temperatureMissing': a.tempMissing,
        'onOxygen': a.onOxygen,
        'copdCo2Retention': a.copdCo2Retention,
        'consciousness': a.consciousness?.label,
        'capillaryRefill': a.capillaryRefill?.label,
        'neonatalState': a.neonatalConsciousness?.label,
      },
      'gcs': {
        'eye': a.gcsEye,
        'verbal': a.gcsVerbal,
        'motor': a.gcsMotor,
        'total': gcsTotal,
      },
      'chiefComplaint': a.chiefComplaint?.label,
      'probeAnswers': Map<String, dynamic>.from(a.probeAnswers),
      'sepsisScreen': {
        'f1InfectionSuspected': a.sepsis.f1,
        'f2AlteredMentation': a.sepsis.f2,
        'f3HighRespRate': a.sepsis.f3,
        'f4LowSystolicBp': a.sepsis.f4,
        'f5Age65Plus': a.sepsis.f5,
        'f6Immunocompromised': a.sepsis.f6,
        'f7AbnormalTemp': a.sepsis.f7,
        'qsofa': a.sepsis.qsofa,
      },
      'burn': {
        'cause': a.burn.cause?.label,
        'tbsaPercent': a.burn.tbsaPercent,
        'areas': a.burn.areas.map((ar) => ar.label).toList(),
        'hasCriticalArea': a.burn.hasCriticalArea,
        'depth': a.burn.depth?.label,
        'airwaySigns': a.burn.airwaySigns,
        'circumferential': a.burn.circumferential,
      },
      'modifiers': {
        'requiresBump': mods.requiresBump(
          age?.isUnderFive == true || age == AgeGroup.olderAdult,
        ),
      },
      'tier1Result': {
        'tier': result.tier.name.toUpperCase(),
        'urgency': result.tier.urgencyIndex + 1,
        'label': result.tier.label,
        'vitalAggregate': result.aggregate,
        'scale': result.scale?.label,
        'reasons': result.reasons,
        'vitalReviewRequired': result.vitalReviewRequired,
      },
      'patientSummary': buildPatientContext(a, result),
    });
  }
}

/// Readable age-band text for the payload and chat context.
String ageBandText(AgeGroup g) => switch (g) {
      AgeGroup.neonate => '0-1 month',
      AgeGroup.infant => '1-11 months',
      AgeGroup.toddler => '1-2 years',
      AgeGroup.preschool => '3-4 years',
      AgeGroup.schoolAge => '5-7 years',
      AgeGroup.preteen => '8-11 years',
      AgeGroup.teenager => '12-15 years',
      AgeGroup.adult => '16-64 years',
      AgeGroup.olderAdult => '65+ years',
    };

/// Readable (non-JSON) triage context used to seed post-triage chat.
///
/// Always framed as decision support, never a diagnosis.
String buildPatientContext(TriageAnswers a, TriageResult result) {
  final b = StringBuffer()
    ..writeln('TIER 1 TRIAGE CONTEXT (decision support - not a diagnosis)')
    ..writeln('Age group: ${a.ageGroup?.label ?? 'Unknown'}')
    ..writeln('Chief complaint: ${a.chiefComplaint?.label ?? 'Not stated'}');

  final vitalLines = <String>[
    if (a.respiratoryRate != null) 'RR ${a.respiratoryRate}/min',
    if (a.spo2 != null)
      'SpO2 ${a.spo2}%'
    else if (a.spo2Missing)
      'SpO2 not available',
    if (a.systolicBp != null) 'BP ${a.systolicBp}',
    if (a.heartRate != null) 'HR ${a.heartRate}/min',
    if (a.temperature != null)
      'Temp ${a.temperature}C'
    else if (a.tempMissing)
      'Temp not available',
    if (a.consciousness != null) 'AVPU ${a.consciousness!.letter}',
    if (a.onOxygen == true) 'On oxygen',
    if (a.capillaryRefill != null) 'Cap refill ${a.capillaryRefill!.label}',
    if (a.neonatalConsciousness != null)
      'Neonatal state ${a.neonatalConsciousness!.label}',
  ];
  if (vitalLines.isNotEmpty) b.writeln('Vitals: ${vitalLines.join(', ')}');

  final gcs = (a.gcsEye != null && a.gcsVerbal != null && a.gcsMotor != null)
      ? a.gcsEye! + a.gcsVerbal! + a.gcsMotor!
      : null;
  if (gcs != null) {
    b.writeln('GCS: $gcs/15 (E${a.gcsEye} V${a.gcsVerbal} M${a.gcsMotor})');
  }

  if (a.probeAnswers.isNotEmpty) {
    final yes = a.probeAnswers.entries.where((e) => e.value).map((e) => e.key).toList();
    if (yes.isNotEmpty) b.writeln('Concerning probes: ${yes.join(', ')}');
  }

  if (a.sepsis.f1 == true) {
    b.writeln('Sepsis screen engaged (F1 suspected infection, qSOFA ${a.sepsis.qsofa}).');
  } else if (a.sepsis.f1 == false || a.tempMissing || a.spo2Missing) {
    b.writeln('Sepsis screen answered (no suspected infection).');
  }

  if (a.burn.engaged) {
    b.writeln(
      'Burn: TBSA ${a.burn.tbsaPercent}%, '
      'depth ${a.burn.depth?.label ?? 'unknown'}, '
      'critical area=${a.burn.hasCriticalArea}.',
    );
  }

  b.writeln('Tier 1 result: ${result.tier.label} (${result.tier.name.toUpperCase()}).');
  if (result.reasons.isNotEmpty) {
    b.writeln('Tier 1 reasons: ${result.reasons.join('; ')}');
  }
  if (result.vitalReviewRequired) {
    b.writeln('NOTE: vitals review required - some measurements were missing.');
  }
  return b.toString();
}

/// Tier 2 output (MedGemma) plus provenance for the audit trail.
///
/// [suggestion] is null when the model's reply was unparsable or off-schema
/// (fail-closed: the AI is simply ignored and Tier 1 stands — ADR-014).
class Tier2Assessment {
  const Tier2Assessment({
    this.suggestion,
    this.summary = '',
    this.requiresHumanVerification = true,
    this.rawOutput,
    this.elapsedMs,
  });

  /// Empty assessment used whenever Tier 2 is skipped or fails closed.
  static const none = Tier2Assessment();

  final TriageTier? suggestion;
  final String summary;
  final bool requiresHumanVerification;

  /// Full raw model reply (kept for debugging / audit; not shown to users).
  final String? rawOutput;

  /// Inference wall-clock time in ms.
  final int? elapsedMs;

  /// True when a validated tier was parsed.
  bool get hasSuggestion => suggestion != null;

  /// True when [suggestion] is more urgent than [base].
  bool escalatedFrom(TriageTier base) =>
      suggestion != null && suggestion!.urgencyIndex < base.urgencyIndex;

  /// ADR-005 / ADR-014 escalation-only merge. Tier 2 can never downgrade.
  ///
  /// ```dart
  /// assert(Tier2Assessment.merge(base, a).urgencyIndex <= base.urgencyIndex);
  /// ```
  static TriageTier merge(TriageTier base, Tier2Assessment ai) =>
      ai.suggestion == null ? base : base.atMostUrgent(ai.suggestion!);

  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{
      'summary': summary,
      'requires_human_verification': requiresHumanVerification,
    };
    if (suggestion != null) out['suggestion'] = suggestion!.name;
    if (elapsedMs != null) out['latency_ms'] = elapsedMs;
    return out;
  }

  static Tier2Assessment fromJson(Map<String, dynamic> json) {
    TriageTier? tier;
    final s = json['suggestion'];
    if (s is String) {
      for (final t in TriageTier.values) {
        if (t.name == s.toLowerCase()) {
          tier = t;
          break;
        }
      }
    }
    return Tier2Assessment(
      suggestion: tier,
      summary: json['summary'] as String? ?? '',
      requiresHumanVerification:
          json['requires_human_verification'] as bool? ?? true,
      elapsedMs: (json['latency_ms'] as num?)?.toInt(),
    );
  }
}

/// Copies [json] minus any 'tier2' key (used by the record fingerprint so the
/// tier-1 save and the post-tier-2 upsert dedupe).
Map<String, dynamic> jsonWithoutTier2(Map<String, dynamic> json) =>
    Map<String, dynamic>.of(json)..remove('tier2');