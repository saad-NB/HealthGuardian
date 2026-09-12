import 'breathing_rate/breathing_rate_service.dart';
import 'heart_rate/heart_rate_service.dart';
import 'heart_rate/ppg_capture.dart';
import 'measurement_session.dart';
import 'models.dart';
import 'permissions.dart';

/// Whether a sensing stack is wired for [kind]. The UI uses this to show or
/// hide "Measure with phone" — no (null) session means manual entry only.
bool vitalsSensingSupported(VitalKind kind) {
  switch (kind) {
    case VitalKind.heartRate:
    case VitalKind.breathingRate:
      return true;
  }
}

/// Builds a ready-to-run [MeasurementSession] for a vital kind.
///
/// The breathing rate path uses the microphone ([BreathingRateService]); the
/// heart rate path uses the camera ([HeartRateService]). Callers (Monitor
/// tab, triage steps) treat a null session as "not available yet" and fall
/// back to manual entry.
MeasurementSession? createMeasurementSession(VitalKind kind) {
  if (!vitalsSensingSupported(kind)) return null;
  const permissions = VitalPermissions();
  if (kind == VitalKind.heartRate) {
    // One capture per session: every retry reopens the same camera object
    // (serialized teardown), and the measuring screen can show its live feed
    // and park in "position your finger" before the countdown starts.
    final capture = PpgCapture();
    return MeasurementSession(
      kind: kind,
      ensureAccess: permissions.ensure,
      run: () => HeartRateService(sourceFactory: () => capture).run(),
      livePreviewBuilder: (_) => capture.buildPreview(),
      previewListenable: capture.previewListenable,
      positionsFirst: true,
      beginPositioning: capture.start,
      endPositioning: capture.stop,
    );
  }
  return MeasurementSession(
    kind: kind,
    ensureAccess: permissions.ensure,
    run: () => BreathingRateService().run(),
  );
}