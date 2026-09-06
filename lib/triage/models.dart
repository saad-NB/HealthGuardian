import 'package:flutter/material.dart';

/// Vital-sign scoring scale, driven by the age bracket (spec §3).
enum VitalScale {
  news2(label: 'NEWS2'),
  pedsNews2(label: 'Peds-NEWS2'),
  pews(label: 'PEWS');

  const VitalScale({required this.label});

  final String label;
}

/// Age bracket chosen at the very first triage question (spec §3).
///
/// Each bracket selects the vital-sign scale and, for children, the exact
/// Peds-NEWS2 scoring row (§5.2).
enum AgeGroup {
  neonate(label: 'Newborn', detail: 'Less than 1 month old', scale: VitalScale.pews),
  infant(label: 'Infant', detail: '1 - 11 months', scale: VitalScale.pedsNews2),
  toddler(label: 'Toddler', detail: '1 - 2 years', scale: VitalScale.pedsNews2),
  preschool(label: 'Child', detail: '3 - 4 years', scale: VitalScale.pedsNews2),
  schoolAge(label: 'Child', detail: '5 - 7 years', scale: VitalScale.pedsNews2),
  preteen(label: 'Pre-teen', detail: '8 - 11 years', scale: VitalScale.pedsNews2),
  teenager(label: 'Teen', detail: '12 - 15 years', scale: VitalScale.pedsNews2),
  adult(label: 'Adult', detail: '16 - 64 years', scale: VitalScale.news2),
  olderAdult(label: 'Older adult', detail: '65 years and older', scale: VitalScale.news2);

  const AgeGroup({required this.label, required this.detail, required this.scale});

  final String label;
  final String detail;
  final VitalScale scale;

  bool get usesNews2 => scale == VitalScale.news2;
  bool get isPediatric => scale == VitalScale.pedsNews2;

  /// Peds-NEWS2 bracket key used by [PedsNews2Thresholds] (§5.2 tables).
  /// Null for non-pediatric brackets.
  String? get pedsBracket => switch (this) {
        AgeGroup.infant => 'infant',
        AgeGroup.toddler => 'toddler',
        AgeGroup.preschool => 'preschool',
        AgeGroup.schoolAge => 'school',
        AgeGroup.preteen => 'preteen',
        AgeGroup.teenager => 'teen',
        _ => null,
      };

  /// True when the patient is younger than 1 year (feeds the §21.6
  /// temperature-concern list) .
  bool get isUnderOneYear => this == neonate || this == infant;

  /// True for 65+ (feeds the §21.6 temperature-concern list).
  bool get isOlderAdult => this == olderAdult;
}

/// AVPU consciousness level (Section B7).
enum Avpu {
  alert(letter: 'A', label: 'Alert', detail: 'Awake and responsive'),
  voice(letter: 'V', label: 'Voice', detail: 'Responds to voice'),
  pain(letter: 'P', label: 'Pain', detail: 'Responds to pain only'),
  unresponsive(letter: 'U', label: 'Unresponsive', detail: 'No response');

  const Avpu({required this.letter, required this.label, required this.detail});

  final String letter;
  final String label;
  final String detail;
}

/// Capillary refill time — pediatric-only scoring input (spec §5.2).
enum CapillaryRefill {
  under2(label: 'Less than 2 seconds', detail: 'Refills quickly (normal)', score: 0),
  twoTo3(label: '2 - 3 seconds', detail: 'Slower refill', score: 1),
  over3(label: 'More than 3 seconds', detail: 'Very slow refill', score: 3);

  const CapillaryRefill({
    required this.label,
    required this.detail,
    required this.score,
  });

  final String label;
  final String detail;
  final int score;

  /// PEWS-style bracket key matching [PedsNews2Thresholds.capillaryRefillScore].
  String get refillKey => switch (this) {
        CapillaryRefill.under2 => 'under2',
        CapillaryRefill.twoTo3 => 'twoTo3',
        CapillaryRefill.over3 => 'over3',
      };
}

/// Neonatal consciousness/feeding state (spec §5.3, PEWS table row).
enum NeonatalConsciousness {
  feedingWell(label: 'Alert, feeding well', detail: 'Awake and feeds normally', score: 0),
  drowsyPoor(label: 'Drowsy or poor feeding', detail: 'Hard to wake or feeds poorly', score: 1),
  unresponsiveNoFeed(label: 'Unresponsive, not feeding', detail: 'Does not respond or feed at all', score: 2);

  const NeonatalConsciousness({
    required this.label,
    required this.detail,
    required this.score,
  });

  final String label;
  final String detail;
  final int score;

  /// PEWS bracket key matching [NeonatalPewsThresholds.consciousnessScore].
  String get stateKey => switch (this) {
        NeonatalConsciousness.feedingWell => 'feedingWell',
        NeonatalConsciousness.drowsyPoor => 'drowsyPoor',
        NeonatalConsciousness.unresponsiveNoFeed => 'unresponsiveNoFeed',
      };
}

/// Scored probe branch for Section E (spec §8). Only the six detailed
/// branches carry scored probes in this increment.
enum ProbeBranch {
  chest(label: 'Chest pain', stepTitle: 'Chest pain'),
  breathing(label: 'Breathing difficulty', stepTitle: 'Breathing difficulty'),
  fever(label: 'Fever', stepTitle: 'Fever'),
  headache(label: 'Headache', stepTitle: 'Headache'),
  abdo(label: 'Abdominal pain', stepTitle: 'Abdominal pain'),
  psych(label: 'Mental health', stepTitle: 'Mental health crisis');

  const ProbeBranch({required this.label, required this.stepTitle});

  final String label;
  final String stepTitle;
}

/// Section D1 — chief complaint (18-option chip grid, spec §7).
/// [branch] selects the Section E probe set; null means no scored probes in
/// this increment (branch-specific sets not yet specced/built).
enum ChiefComplaint {
  fever(id: 'fever', label: 'Fever', branch: ProbeBranch.fever),
  breathing(id: 'breathing', label: 'Breathing difficulty', branch: ProbeBranch.breathing),
  chest(id: 'chest', label: 'Chest pain', branch: ProbeBranch.chest),
  abdo(id: 'abdo', label: 'Abdominal pain', branch: ProbeBranch.abdo),
  gastrointestinal(id: 'gi', label: 'Vomiting or diarrhoea', branch: null),
  throat(id: 'throat', label: 'Sore throat', branch: null),
  ear(id: 'ear', label: 'Ear pain', branch: null),
  eye(id: 'eye', label: 'Eye problem', branch: null),
  skin(id: 'skin', label: 'Skin rash', branch: null),
  wound(id: 'wound', label: 'Wound or burn', branch: null),
  headache(id: 'headache', label: 'Headache', branch: ProbeBranch.headache),
  weakness(id: 'weakness', label: 'Weakness or numbness', branch: null),
  urinary(id: 'urinary', label: 'Urinary problem', branch: null),
  pregnancy(id: 'pregnancy', label: 'Pregnancy-related', branch: null),
  injury(id: 'injury', label: 'Injury or trauma', branch: null),
  poisoning(id: 'poisoning', label: 'Poisoning or overdose', branch: null),
  mentalHealth(id: 'mental', label: 'Mental health crisis', branch: ProbeBranch.psych),
  other(id: 'other', label: 'Other problem', branch: null);

  const ChiefComplaint({required this.id, required this.label, required this.branch});

  final String id;
  final String label;
  final ProbeBranch? branch;

  /// Whether the chief complaint suggests a head-injury context for GCS
  /// tier overrides (spec §6).
  bool get suggestsHeadInjury => this == injury || this == headache;
}

/// One Section E scored probe question (per-branch list in probes.dart).
class ProbeQuestion {
  const ProbeQuestion({required this.id, required this.text, required this.score});

  final String id;
  final String text;
  final int score;
}

/// Section F — sepsis screen answers (spec §9). Fields are tri-state so an
/// unanswered row renders uncoloured; the engine treats null as false.
class SepsisAnswers {
  /// F1 suspected or confirmed infection (gate to qSOFA/pedSIRS).
  bool? f1;

  /// F2 altered mental status (confused, drowsy, not normal).
  bool? f2;

  /// F3 RR >=22/min (adult) or age-adjusted high (child).
  bool? f3;

  /// F4 systolic BP <=100 mmHg (adult) or age-adjusted low (child).
  bool? f4;

  /// F5 age >=65 years.
  bool? f5;

  /// F6 immunocompromised.
  bool? f6;

  /// F7 temperature <36C or >38.5C.
  bool? f7;

  int get qsofa =>
      ((f2 ?? false) ? 1 : 0) +
      ((f3 ?? false) ? 1 : 0) +
      ((f4 ?? false) ? 1 : 0);

  void reset() {
    f1 = f2 = f3 = f4 = f5 = f6 = f7 = null;
  }
}

/// Five-tier triage outcome (spec §14).
enum TriageTier {
  p1(
    label: 'P1 - Emergency',
    shortLabel: 'Emergency',
    color: Color(0xFFD32F2F),
    response: 'Immediate',
    actionSteps: [
      'Call 112 or ambulance right now.',
      'Go to the nearest hospital now.',
      'Show this result to the ambulance or hospital team.',
    ],
  ),
  p2(
    label: 'P2 - Very Urgent',
    shortLabel: 'Very Urgent',
    color: Color(0xFFF57C00),
    response: 'Within 10 minutes',
    actionSteps: [
      'Contact a doctor or go to hospital without delay.',
      'Someone should stay with the patient.',
      'Recheck in 10 minutes; go sooner if they worsen.',
    ],
  ),
  p3(
    label: 'P3 - Urgent',
    shortLabel: 'Urgent',
    color: Color(0xFFFBC02D),
    response: '30 - 60 minutes',
    useDarkText: true,
    actionSteps: [
      'See a doctor today.',
      'Recheck symptoms in 30 minutes.',
      'Go to hospital if anything becomes severe.',
    ],
  ),
  p4(
    label: 'P4 - Standard',
    shortLabel: 'Standard',
    color: Color(0xFF388E3C),
    response: 'Within 2 hours',
    actionSteps: [
      'Arrange a routine check-up.',
      'Recheck symptoms in 2 hours.',
      'Return for triage if symptoms change.',
    ],
  ),
  p5(
    label: 'P5 - Minor',
    shortLabel: 'Minor',
    color: Color(0xFF1976D2),
    response: 'Within 4 hours',
    actionSteps: [
      'Care at home is usually enough.',
      'Recheck symptoms in 4 hours.',
      'Return for triage or see a doctor if anything changes.',
    ],
  );

  const TriageTier({
    required this.label,
    required this.shortLabel,
    required this.color,
    required this.response,
    required this.actionSteps,
    this.useDarkText = false,
  });

  final String label;
  final String shortLabel;
  final Color color;
  final String response;
  final bool useDarkText;
  final List<String> actionSteps;

  int get urgencyIndex => index;

  /// The more urgent of [this] and [other] (P1 is index 0).
  TriageTier atMostUrgent(TriageTier other) =>
      urgencyIndex <= other.urgencyIndex ? this : other;
}

/// One collected triage session (Sections A/B only for this increment).
class TriageAnswers {
  AgeGroup? ageGroup;

  /// Danger gates answered "Yes" (what the engine reads).
  final Set<String> dangerSigns = {};

  /// Danger gates the user explicitly answered "No". Kept separate so an
  /// untouched row renders as unselected (no false "No chosen" colour).
  final Set<String> dangerNo = {};

  double? respiratoryRate;
  double? spo2;
  double? systolicBp;
  double? heartRate;
  double? temperature;
  Avpu? consciousness;

  /// Nullable so the Yes/No question is visibly unanswered until tapped;
  /// the engine treats null as "No" (NEWS2's on-air assumption).
  bool? onOxygen;
  bool? copdCo2Retention;

  /// Explicit "not available" markers so an unentered value can be told
  /// apart from an intentionally-missing one (spec §21).
  bool spo2Missing = false;
  bool tempMissing = false;

  /// Pediatric-only capillary refill (§5.2).
  CapillaryRefill? capillaryRefill;

  /// Neonatal-only consciousness/feeding state (§5.3).
  NeonatalConsciousness? neonatalConsciousness;

  /// Full GCS components (§6), collected only when indicated. Values persist
  /// as selected; the aggregate applies only when all three are present.
  int? gcsEye;
  int? gcsVerbal;
  int? gcsMotor;

  /// Section D1 chief complaint (§7).
  ChiefComplaint? chiefComplaint;

  /// Section E answered probes: probe id -> Yes/No (§8).
  final Map<String, bool> probeAnswers = {};

  /// Section F sepsis screen (§9).
  final SepsisAnswers sepsis = SepsisAnswers();

  void reset() {
    ageGroup = null;
    dangerSigns.clear();
    dangerNo.clear();
    respiratoryRate = null;
    spo2 = null;
    systolicBp = null;
    heartRate = null;
    temperature = null;
    consciousness = null;
    onOxygen = null;
    copdCo2Retention = null;
    spo2Missing = false;
    tempMissing = false;
    capillaryRefill = null;
    neonatalConsciousness = null;
    gcsEye = null;
    gcsVerbal = null;
    gcsMotor = null;
    chiefComplaint = null;
    probeAnswers.clear();
    sepsis.reset();
  }
}

/// Outcome of the Tier 1 engine, plus a human-readable reason string.
class TriageResult {
  const TriageResult({
    required this.tier,
    required this.reasons,
    required this.vitalReviewRequired,
    this.aggregate,
    this.scale,
    this.decisionSupport = true,
  });

  final TriageTier tier;
  final List<String> reasons;
  final bool vitalReviewRequired;

  /// Vitals aggregate when a vital scale was scored (NEWS2 / Peds-NEWS2 /
  /// PEWS). Null when no scale was applied.
  final int? aggregate;

  /// Which vital-sign scale produced [aggregate].
  final VitalScale? scale;

  /// Every result is framed as decision support, never a diagnosis.
  final bool decisionSupport;
}