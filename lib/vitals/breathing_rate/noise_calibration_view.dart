import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/theme/app_tokens.dart';
import '../models.dart';
import '../permissions.dart';
import 'breathing_calibration_service.dart';
import 'noise_profile_store.dart';

/// Runs the breathing-rate background-noise calibration as a full-screen
/// dialog. Returns true when a profile was learned (and stored in
/// [NoiseProfileStore]), false when the user cancelled or it failed.
Future<bool> launchBreathingNoiseCalibration(BuildContext context) async {
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      fullscreenDialog: true,
      builder: (_) => const NoiseCalibrationScreen(),
    ),
  );
  return ok ?? false;
}

/// Asks whether to run the background calibration before measuring. Returns
/// true when the user agrees to be redirected through it.
Future<bool> confirmBreathingNoiseCalibration(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Measure background noise first'),
      content: const Text(
        'The app needs a few seconds of quiet to learn the room\'s noise '
        'before it can count breaths reliably. Measure the background noise '
        'now?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Measure background noise'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Records a few seconds of quiet room so the breathing measurement can
/// subtract the learned noise spectrum. Kept separate from the measurement
/// session so the breath countdown never starts before the background step.
class NoiseCalibrationScreen extends StatefulWidget {
  const NoiseCalibrationScreen({super.key, this.service});

  /// Injectable for tests; defaults to a real microphone capture.
  final BreathingCalibrationService? service;

  @override
  State<NoiseCalibrationScreen> createState() => _NoiseCalibrationScreenState();
}

enum _Phase { requesting, calibrating, failed }

class _NoiseCalibrationScreenState extends State<NoiseCalibrationScreen> {
  static const _permissions = VitalPermissions();

  _Phase _phase = _Phase.requesting;
  double _elapsed = 0;
  double _total = 6;
  String? _message;
  StreamSubscription<CalibrationEvent>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.requesting;
      _message = null;
      _elapsed = 0;
    });
    final granted = await _permissions.ensure(VitalKind.breathingRate);
    if (!mounted) return;
    if (!granted) {
      setState(() {
        _phase = _Phase.failed;
        _message = 'The app needs microphone permission to learn the '
            'background noise. Grant it in Settings and try again.';
      });
      return;
    }
    final service = widget.service ?? BreathingCalibrationService();
    _total = service.calibrationSeconds;
    setState(() => _phase = _Phase.calibrating);
    _sub = service.run().listen(
      _onEvent,
      onError: (Object e) {
        if (mounted) {
          setState(() {
            _phase = _Phase.failed;
            _message = '$e';
          });
        }
      },
    );
  }

  void _onEvent(CalibrationEvent event) {
    if (!mounted) return;
    switch (event) {
      case CalibrationProgress(:final elapsedSeconds, :final totalSeconds):
        setState(() {
          _elapsed = elapsedSeconds;
          _total = totalSeconds;
        });
      case CalibrationDone(:final profile):
        NoiseProfileStore.set(profile);
        Navigator.of(context).pop(true);
      case CalibrationFailed(:final reason):
        setState(() {
          _phase = _Phase.failed;
          _message = reason;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Background noise'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel',
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppMetrics.margin),
              child: _body(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.requesting:
        return Column(
          children: [
            const CircularProgressIndicator(color: AppColors.teal700),
            const SizedBox(height: 24),
            Text(
              'Checking microphone access…',
              style: TextStyle(color: AppColors.textSubdued),
            ),
          ],
        );
      case _Phase.calibrating:
        final remaining = (_total - _elapsed).ceil().clamp(0, 9999);
        return Column(
          children: [
            const Icon(Icons.hearing, size: 56, color: AppColors.teal700),
            const SizedBox(height: 16),
            Text(
              'Learning background noise',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Stay quiet and keep the phone still. Don\'t speak or move — '
              'this is how the app learns what the room sounds like.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSubdued),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 160,
              height: 160,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: _total <= 0
                          ? null
                          : (_elapsed / _total).clamp(0.0, 1.0),
                      strokeWidth: 10,
                      backgroundColor: AppColors.optionFill,
                      color: AppColors.teal700,
                    ),
                  ),
                  Text(
                    '${remaining}s',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                ],
              ),
            ),
          ],
        );
      case _Phase.failed:
        return Column(
          children: [
            const Icon(Icons.mic_off, size: 56, color: AppColors.reviewBanner),
            const SizedBox(height: 16),
            Text(
              'Could not measure background',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _message ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSubdued),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _start,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(AppMetrics.minTouch),
              ),
              child: const Text('Try again'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(AppMetrics.minTouch),
              ),
              child: const Text('Cancel'),
            ),
          ],
        );
    }
  }
}
