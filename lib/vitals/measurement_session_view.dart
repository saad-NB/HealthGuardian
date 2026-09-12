import 'package:flutter/material.dart';

import '../ui/theme/app_tokens.dart';
import 'measurement_session.dart';
import 'models.dart';

/// Confidence colours: teal for clearly-acceptable, amber for "accept with
/// thought", red for "low confidence / confirm to accept" (ADR-017 §6).
Color confidenceColor(ReadingConfidence c) => switch (c) {
      ReadingConfidence.high => AppColors.teal700,
      ReadingConfidence.medium => AppColors.reviewBanner,
      ReadingConfidence.low => AppColors.tierP1,
    };

/// Pushes the shared vitals measurement session as a full-screen dialog.
/// Returns the confirmed [VitalReading], or null when the user cancelled /
/// entered manually.
Future<VitalReading?> launchMeasurementSession(
  BuildContext context, {
  required MeasurementSession session,
  String? cancelLabel,
  void Function(VitalReading reading)? onAccepted,
}) async {
  final result = await Navigator.of(context).push<VitalReading>(
    MaterialPageRoute<VitalReading>(
      fullscreenDialog: true,
      builder: (_) => MeasurementSessionScreen(
        session: session,
        cancelLabel: cancelLabel,
        onAccepted: onAccepted,
      ),
    ),
  );
  return result;
}

/// Shared measurement-session UI for HR and RR (ADR-017). Consumes a
/// [MeasurementSession]; all sensor logic stays behind the injected service.
class MeasurementSessionScreen extends StatefulWidget {
  const MeasurementSessionScreen({
    super.key,
    required this.session,
    this.cancelLabel,
    this.onAccepted,
  });

  final MeasurementSession session;

  /// Text for the abandon button, e.g. "Enter manually instead".
  final String? cancelLabel;

  /// Called when the user confirms a reading (before the sheet pops).
  final void Function(VitalReading reading)? onAccepted;

  @override
  State<MeasurementSessionScreen> createState() =>
      _MeasurementSessionScreenState();
}

class _MeasurementSessionScreenState extends State<MeasurementSessionScreen> {
  bool _debugExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.session.start();
    });
  }

  @override
  void dispose() {
    widget.session.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.session.kind.label),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.session,
          builder: (context, _) => Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppMetrics.margin),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: _body(),
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppMetrics.margin,
                  8,
                  AppMetrics.margin,
                  16,
                ),
                child: Text(
                  'Screening estimate only — not a substitute for clinical '
                  'assessment.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.textSubdued),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final session = widget.session;
    final kind = session.kind;
    switch (session.phase) {
      case SessionPhase.idle:
      case SessionPhase.requestingPermission:
        return _pillar(
          child: Column(
            children: [
              const CircularProgressIndicator(color: AppColors.teal700),
              const SizedBox(height: 24),
              Text(
                'Checking ${_sensorName(kind)} access…',
                style: TextStyle(color: AppColors.textSubdued),
              ),
            ],
          ),
        );
      case SessionPhase.positioning:
        return _pillar(
          child: Column(
            children: [
              _livePreview(wide: true),
              const SizedBox(height: 20),
              Text(
                'Place your fingertip firmly over the rear camera and flash, '
                'then tap Start measuring. The countdown only begins once the '
                'signal is good.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 28),
              _gapFilledButton(
                'Start measuring',
                onPressed: () => widget.session.beginMeasure(),
              ),
              const SizedBox(height: 10),
              _cancelButton(),
            ],
          ),
        );
      case SessionPhase.measuring:
        return _pillar(
          child: Column(
            children: [
              if (kind == VitalKind.heartRate) ...[
                _livePreview(),
                const SizedBox(height: 20),
              ],
              SizedBox(
                width: 220,
                height: 220,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: session.progress,
                        strokeWidth: 10,
                        backgroundColor: AppColors.optionFill,
                        color: AppColors.teal700,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(kind.sessionSeconds - session.elapsedSeconds).ceil().clamp(0, 9999)}s',
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        const Text(
                          'remaining',
                          style:
                              TextStyle(color: AppColors.textSubdued, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                kind.instruction,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              _debugPanel(compact: false),
            ],
          ),
        );
      case SessionPhase.success:
        return _success(session.reading!);
      case SessionPhase.insufficientSignal:
        return _pillar(
          child: Column(
            children: [
              const Icon(Icons.sensors_off,
                  size: 56, color: AppColors.reviewBanner),
              const SizedBox(height: 16),
              Text(
                'Not enough signal',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                session.message ??
                    'The sensor could not pick up a reliable signal.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSubdued),
              ),
              _debugPanel(compact: true),
              const SizedBox(height: 24),
              _gapFilledButton('Try again', onPressed: () => session.retry()),
              const SizedBox(height: 10),
              _cancelButton(),
            ],
          ),
        );
      case SessionPhase.failed:
        return _pillar(
          child: Column(
            children: [
              const Icon(Icons.error_outline,
                  size: 56, color: AppColors.tierP1),
              const SizedBox(height: 16),
              Text(
                'Could not start measuring',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                session.message ?? 'Something went wrong with the sensor.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSubdued),
              ),
              _debugPanel(compact: true),
              const SizedBox(height: 24),
              _gapFilledButton('Try again', onPressed: () => session.retry()),
              const SizedBox(height: 10),
              _cancelButton(),
            ],
          ),
        );
      case SessionPhase.cancelled:
        return const SizedBox.shrink();
    }
  }

  Widget _success(VitalReading reading) {
    final low = reading.confidence == ReadingConfidence.low;
    return _pillar(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: confidenceColor(reading.confidence).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: confidenceColor(reading.confidence)),
            ),
            child: Text(
              '${reading.confidence.label} confidence',
              style: TextStyle(
                color: confidenceColor(reading.confidence),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${reading.value.round()}',
                    style: Theme.of(context).textTheme.displayLarge,
                  ),
                  TextSpan(
                    text: '  ${reading.kind.shortUnit}',
                    style: TextStyle(color: AppColors.textSubdued, fontSize: 22),
                  ),
                ],
              ),
            ),
          ),
          if (reading.note != null) ...[
            const SizedBox(height: 8),
            Text(
              reading.note!,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSubdued),
            ),
          ],
          if (low) ...[
            const SizedBox(height: 16),
            Text(
              'This reading is low-confidence. Use it only if you cannot '
              'get a better one.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.tierP1),
            ),
          ],
          const SizedBox(height: 28),
          _gapFilledButton(
            low ? 'Accept anyway' : 'Use this reading',
            onPressed: () {
              widget.session.accept();
              widget.onAccepted?.call(reading);
              Navigator.of(context).pop(reading);
            },
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => widget.session.retry(),
            icon: const Icon(Icons.replay),
            label: const Text('Measure again'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(AppMetrics.minTouch),
              side: const BorderSide(color: AppColors.border),
              foregroundColor: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          _cancelButton(),
        ],
      ),
    );
  }

  Widget _cancelButton() {
    final label = widget.cancelLabel ?? 'Cancel';
    return TextButton(
      onPressed: () {
        widget.session.cancel();
        Navigator.of(context).pop();
      },
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(AppMetrics.minTouch),
        foregroundColor: AppColors.textPrimary,
      ),
      child: Text(label),
    );
  }

  Widget _gapFilledButton(String label, {required VoidCallback onPressed}) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(AppMetrics.minTouch),
      ),
      child: Text(label),
    );
  }

  Widget _pillar({required Widget child}) {
    return Align(
      alignment: Alignment.topCenter,
      child: child,
    );
  }

  /// Live rear-camera feed so the user can verify fingertip coverage while
  /// measuring (ADR-017 / `PpgCapture.buildPreview`). Listens to the source's
  /// [previewListenable] so the feed appears the moment the camera is ready —
  /// e.g. during positioning, before the countdown has started. A placeholder
  /// shows until frames are actually flowing.
  Widget _livePreview({bool wide = false}) {
    final session = widget.session;
    final listenable = session.previewListenable;
    Widget content() =>
        session.livePreviewBuilder?.call(context) ?? _cameraStarting();

    final feed = listenable == null
        ? content()
        : ListenableBuilder(
            listenable: listenable,
            builder: (context, _) => content(),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: wide ? 280 : 200,
        height: wide ? 210 : 150,
        child: ColoredBox(
          color: const Color(0xFF10141A),
          child: feed,
        ),
      ),
    );
  }

  Widget _cameraStarting() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.videocam_off_outlined, color: AppColors.textSubdued),
          const SizedBox(height: 6),
          const Text(
            'Starting camera…',
            style: TextStyle(color: AppColors.textSubdued, fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// Diagnostics from the measurement events: live while measuring (updates
  /// every progress tick), or a compact "why it failed" summary on the
  /// insufficient/failed screens. Collapsible so normal users ignore it.
  Widget _debugPanel({required bool compact}) {
    final debug = widget.session.debug;
    if (debug == null || debug.isEmpty) return const SizedBox.shrink();

    final expanded = !compact || _debugExpanded;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _debugExpanded = !_debugExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bug_report_outlined,
                      size: 16, color: AppColors.textSubdued),
                  const SizedBox(width: 6),
                  Text(
                    'Sensor diagnostics',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSubdued,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: AppColors.textSubdued,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF10141A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Wrap(
                spacing: 14,
                runSpacing: 6,
                children: debug.entries.map((e) {
                  return Text(
                    '${e.key}: ${e.value}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8AA0B4),
                      fontFamily: 'monospace',
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  String _sensorName(VitalKind kind) => switch (kind) {
        VitalKind.heartRate => 'camera',
        VitalKind.breathingRate => 'microphone',
      };
}