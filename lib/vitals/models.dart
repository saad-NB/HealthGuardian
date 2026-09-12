import 'package:flutter/foundation.dart';

/// On-device vitals sensing types (ADR-017, docs/VITALS_SENSING.md).
///
/// Pure data — no plugin/platform code here so the types and the session
/// state machine run headless in unit/widget tests.

/// Which vital a measurement targets.
enum VitalKind {
  heartRate(
    label: 'Heart rate',
    unit: 'bpm',
    shortUnit: 'bpm',
    sessionSeconds: 30,
    instruction:
        'Firmly cover the rear camera lens and flash with your fingertip. '
        'Keep very still for the countdown.',
  ),
  breathingRate(
    label: 'Breathing rate',
    unit: 'breaths/min',
    shortUnit: 'breaths/min',
    sessionSeconds: 45,
    instruction:
        'Put the phone\'s microphone near your mouth or nose and breathe '
        'normally. Keep the room quiet during the countdown.',
  );

  const VitalKind({
    required this.label,
    required this.unit,
    required this.shortUnit,
    required this.sessionSeconds,
    required this.instruction,
  });

  final String label;
  final String unit;
  final String shortUnit;

  /// Target session length in seconds. Tunable constants (VITALS_SENSING §9.3
  /// — any change requires a DECISIONS entry).
  final int sessionSeconds;
  final String instruction;
}

/// Screening confidence for a reading. Never clinical-grade (ADR-017 §6).
enum ReadingConfidence {
  low(label: 'Low'),
  medium(label: 'Medium'),
  high(label: 'High');

  const ReadingConfidence({required this.label});

  final String label;

  bool get isAcceptableOnItsOwn => this != low;
}

/// Where a vital value came from (provenance, added to record inputs).
enum VitalSource {
  manual(label: 'manual'),
  sensor(label: 'sensor');

  const VitalSource({required this.label});

  final String label;
}

/// One finished sensor reading (value + confidence + time). Raw frames/audio
/// never leave the device; only this snapshot may be stored (VITALS_SENSING
/// §7.3).
@immutable
class VitalReading {
  const VitalReading({
    required this.kind,
    required this.value,
    required this.confidence,
    required this.measuredAt,
    this.note,
  });

  final VitalKind kind;
  final double value;
  final ReadingConfidence confidence;
  final DateTime measuredAt;

  /// Optional human-readable caveat, e.g. "some movement detected".
  final String? note;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'value': value,
        'confidence': confidence.name,
        'measuredAt': measuredAt.toIso8601String(),
        if (note != null) 'note': note,
      };

  factory VitalReading.fromJson(Map<String, dynamic> json) => VitalReading(
        kind: VitalKind.values.byName(json['kind'] as String),
        value: (json['value'] as num).toDouble(),
        confidence: ReadingConfidence.values.byName(
          json['confidence'] as String,
        ),
        measuredAt: DateTime.parse(json['measuredAt'] as String),
        note: json['note'] as String?,
      );
}

/// Provenance for a vital value stored in `TriageAnswers.measurementMeta`
/// (VITALS_SENSING §7.1). Sensor fills drop in here so records and Ask AI can
/// tell "sensor, medium confidence" from a manual guess without any engine
/// behaviour changing.
@immutable
class VitalMeasurement {
  const VitalMeasurement({
    required this.source,
    required this.confidence,
    required this.measuredAt,
  });

  final VitalSource source;
  final ReadingConfidence confidence;
  final DateTime measuredAt;

  Map<String, dynamic> toJson() => {
        'source': source.label,
        'confidence': confidence.label.toLowerCase(),
        'measuredAt': measuredAt.toIso8601String(),
      };
}

/// Events a measurement service emits over its session stream.
sealed class MeasurementEvent {
  const MeasurementEvent();
}

/// Periodic progress while measuring (seconds elapsed since session start).
class MeasurementProgress extends MeasurementEvent {
  const MeasurementProgress(
    this.elapsedSeconds, {
    this.instantValue,
    this.debug,
  });

  final double elapsedSeconds;
  final double? instantValue;

  /// Live sensor diagnostics for the debug panel (label -> value). Null/empty
  /// for non-sensing flows and microphone measurements.
  final Map<String, String>? debug;
}

/// A reading completed and passed the session's minimum quality bar.
class MeasurementSuccess extends MeasurementEvent {
  const MeasurementSuccess(this.reading);

  final VitalReading reading;
}

/// Signal too poor to estimate; the session should stop and offer retry.
class MeasurementInsufficient extends MeasurementEvent {
  const MeasurementInsufficient(this.reason, {this.debug});

  final String reason;

  /// Terminal sensor diagnostics (why it was rejected), rendered in the
  /// debugging panel on the insufficient-signal screen.
  final Map<String, String>? debug;
}

/// Hard failure (sensor error, capture could not start, etc.).
class MeasurementFailed extends MeasurementEvent {
  const MeasurementFailed(this.reason);

  final String reason;
}