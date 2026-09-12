import 'dart:async';

import 'package:flutter/widgets.dart';

import 'models.dart';

/// Phases a vitals measurement session passes through (ADR-017 §3).
enum SessionPhase {
  idle,
  requestingPermission,
  /// Camera/mic is live so the user can position (HR: finger over lens) but the
  /// countdown has NOT started — measurement begins only on [beginMeasure].
  positioning,
  measuring,
  success,
  insufficientSignal,
  failed,
  cancelled,
}

/// State machine for one vitals measurement session. Shared by both
/// sub-modules (HR + RR) and by the Monitor tab and the in-triage steps.
///
/// Framework-free apart from [ChangeNotifier]: all platform work happens
/// behind the injected [ensureAccess] / [run] callbacks, so the whole flow is
/// testable headless with fakes.
class MeasurementSession extends ChangeNotifier {
  MeasurementSession({
    required this.kind,
    required this.ensureAccess,
    required this.run,
    DateTime Function()? now,
    this.livePreviewBuilder,
    this.previewListenable,
    this.positionsFirst = false,
    this.beginPositioning,
    this.endPositioning,
  }) : _now = now ?? DateTime.now;

  final VitalKind kind;

  /// Resolves to true when the platform permission for [kind] is granted.
  final Future<bool> Function(VitalKind kind) ensureAccess;

  /// Produces a new measurement-event stream for one measuring attempt.
  final Stream<MeasurementEvent> Function() run;

  /// Builds a live sensor view (camera feed) for the measuring phase, or null
  /// when the source is not ready / not surfaceable (e.g. microphone).
  final Widget? Function(BuildContext context)? livePreviewBuilder;

  /// Fires whenever that sensor view could become available/change (camera
  /// initialised/released); the screen listens so the feed appears live even
  /// while parked in positioning, not only on a phase change.
  final Listenable? previewListenable;

  /// When true the session stops at [SessionPhase.positioning] after the
  /// permission check (camera live, no countdown) instead of measuring
  /// immediately — the user positions the sensor and starts on their own tap
  /// ([beginMeasure]). Both flows use this: heart rate parks with the camera
  /// live for finger placement; breathing rate parks with no sensor running so
  /// the user can quiet the room and position the phone first.
  final bool positionsFirst;

  /// Starts the sensor for the positioning phase (e.g. camera on for preview).
  final Future<void> Function()? beginPositioning;

  /// Stops the sensor started by [beginPositioning] when the session is
  /// abandoned before measuring. NO-OP while measuring (the service owns the
  /// teardown there).
  final Future<void> Function()? endPositioning;

  final DateTime Function() _now;

  SessionPhase _phase = SessionPhase.idle;
  SessionPhase get phase => _phase;

  VitalReading? _reading;
  VitalReading? get reading => _reading;

  String? _message;
  String? get message => _message;

  Map<String, String>? _debug;
  Map<String, String>? get debug => _debug;

  double _elapsedSeconds = 0;
  double get elapsedSeconds => _elapsedSeconds;

  /// 0..1 fill for the countdown ring.
  double get progress => (_elapsedSeconds / kind.sessionSeconds).clamp(0.0, 1.0);

  /// True once a reading exists and the phase is [SessionPhase.success].
  bool get hasReading => _reading != null && _phase == SessionPhase.success;

  bool get isTerminal => switch (_phase) {
        SessionPhase.success ||
        SessionPhase.insufficientSignal ||
        SessionPhase.failed ||
        SessionPhase.cancelled =>
          true,
        _ => false,
      };

  StreamSubscription<MeasurementEvent>? _sub;
  bool _disposed = false;

  /// Bumped on every start/cancel so straggler events and in-flight async
  /// chains from a superseded attempt are dropped (never awaited on — see
  /// [_stop]).
  int _epoch = 0;

  /// Begins (or restarts) the session: asks permission, then either parks in
  /// [SessionPhase.positioning] (camera live, waiting for the user's
  /// "Start measuring" tap) or goes straight to measuring.
  ///
  /// Cancellation of a previous attempt is fire-and-forget: we never block on
  /// the platform stream tearing down.
  Future<void> start() async {
    if (_phase == SessionPhase.measuring ||
        _phase == SessionPhase.positioning) {
      return;
    }
    final epoch = ++_epoch;
    _stop();

    _phase = SessionPhase.requestingPermission;
    _reading = null;
    _message = null;
    _debug = null;
    _elapsedSeconds = 0;
    _notify();

    final granted = await ensureAccess(kind);
    if (_disposed || epoch != _epoch) return;

    if (!granted) {
      _phase = SessionPhase.failed;
      _message =
          'The app needs $_permissionName permission to use the phone\'s '
          'sensor. Grant it in Settings (top-left gear) and try again.';
      _notify();
      return;
    }

    if (positionsFirst) {
      _phase = SessionPhase.positioning;
      _notify();
      try {
        await beginPositioning?.call();
      } catch (e) {
        if (_disposed || epoch != _epoch) return;
        _enter(SessionPhase.failed, message: '$e');
      }
      return;
    }

    await _runMeasure(epoch);
  }

  /// Starts the countdown once the user has the sensor positioned (HR: finger
  /// firmly over the lens). The window is fully available for collecting
  /// usable signal instead of being spent placing the sensor.
  Future<void> beginMeasure() async {
    if (_phase != SessionPhase.positioning) return;
    final epoch = ++_epoch;
    _message = null;
    _debug = null;
    _elapsedSeconds = 0;
    await _runMeasure(epoch);
  }

  Future<void> _runMeasure(int epoch) async {
    _phase = SessionPhase.measuring;
    _notify();
    try {
      final stream = run();
      _sub = stream.listen(
        (e) {
          if (epoch == _epoch) _onEvent(e);
        },
        onError: (Object e) {
          if (epoch == _epoch) _enter(SessionPhase.failed, message: '$e');
        },
      );
    } catch (e) {
      if (epoch == _epoch) _enter(SessionPhase.failed, message: '$e');
    }
  }

  /// Confirms the current reading (explicit user "Accept" / "Accept anyway").
  void accept() {
    if (reading == null) return;
    _stop();
    _epoch++;
  }

  /// From a terminal failure / insufficient-signal state: measure again.
  Future<void> retry() => start();

  /// Abandons the session. The caller keeps its manual-entry fallback.
  Future<void> cancel() async {
    if (_phase == SessionPhase.positioning) {
      // Positioning sensor is owned here, not by a measurement service.
      try {
        await endPositioning?.call();
      } catch (_) {}
    }
    _stop();
    _epoch++;
    _enter(SessionPhase.cancelled);
  }

  void _onEvent(MeasurementEvent event) {
    switch (event) {
      case MeasurementProgress(:final elapsedSeconds, :final debug):
        _elapsedSeconds = elapsedSeconds;
        if (debug != null && debug.isNotEmpty) _debug = debug;
        _notify();
      case MeasurementSuccess(:final reading):
        _reading = reading;
        _stop();
        _enter(SessionPhase.success);
      case MeasurementInsufficient(:final reason, :final debug):
        if (debug != null && debug.isNotEmpty) _debug = debug;
        _enter(SessionPhase.insufficientSignal, message: reason);
      case MeasurementFailed(:final reason):
        _enter(SessionPhase.failed, message: reason);
    }
  }

  void _enter(SessionPhase phase, {String? message}) {
    _phase = phase;
    if (message != null) _message = message;
    _notify();
  }

  /// Drops the current attempt without waiting for its teardown.
  void _stop() {
    final sub = _sub;
    _sub = null;
    if (sub != null) unawaited(sub.cancel());
  }

  String get _permissionName => switch (kind) {
        VitalKind.heartRate => 'camera',
        VitalKind.breathingRate => 'microphone',
      };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stop();
    super.dispose();
  }

  /// Timestamp used to stamp accepted readings (kept on the session so callers
  /// and tests share one clock).
  DateTime stamp() => _now();
}