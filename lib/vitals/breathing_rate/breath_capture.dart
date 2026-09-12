import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

/// One chunk of normalized (-1..1) PCM16 samples with its elapsed-seconds tag
/// (end-of-chunk time since session start).
class BreathChunk {
  const BreathChunk({required this.samples, required this.elapsedSeconds});

  final Float64List samples;
  final double elapsedSeconds;
}

/// Pluggable source of PCM chunks. The microphone implementation reads real
/// audio; tests substitute synthetic waveforms ([BreathChunkSource] keeps the
/// service headless-testable, ADR-017 §3 "backend swappable").
abstract class BreathChunkSource {
  Future<void> start();
  Stream<BreathChunk> get stream;
  Future<void> stop();
}

/// Mic capture for breathing rate (ADR-017 §5.2): `record` at 16 kHz mono
/// PCM16, no on-device audio effects (so the energy envelope we measure is the
/// room's, not the DSP's). Permission is handled upstream by
/// `VitalPermissions` (RECORD_AUDIO).
class BreathCapture implements BreathChunkSource {
  BreathCapture({this.sampleRateHz = 16000});

  final int sampleRateHz;

  final AudioRecorder _recorder = AudioRecorder();
  StreamController<BreathChunk>? _sink;
  StreamSubscription<Uint8List>? _sub;
  bool _started = false;
  double _elapsed = 0;

  @override
  Future<void> start() async {
    if (_started) return;
    final pcm = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRateHz,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );

    _sink = StreamController<BreathChunk>();
    _elapsed = 0;
    _sub = pcm.listen(
      (bytes) {
        final n = bytes.lengthInBytes >> 1;
        if (n == 0) return;
        final samples = Float64List(n);
        final view = ByteData.sublistView(bytes);
        for (var i = 0; i < n; i++) {
          samples[i] = view.getInt16(i << 1, Endian.little) / 32768.0;
        }
        _elapsed += n / sampleRateHz;
        _sink?.add(BreathChunk(samples: samples, elapsedSeconds: _elapsed));
      },
      onError: (Object e) {
        _sink?.addError(e);
      },
      onDone: () => _sink?.close(),
    );
    _started = true;
  }

  @override
  Stream<BreathChunk> get stream => _sink!.stream;

  @override
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    await _sub?.cancel();
    _sub = null;
    // stop() returns the output path, which is null for stream recording; the
    // plugin still needs it called (and disposing frees the mic).
    try {
      await _recorder.stop();
    } catch (_) {}
    try {
      await _recorder.dispose();
    } catch (_) {}
    final sink = _sink;
    _sink = null;
    if (sink != null && !sink.isClosed) {
      await sink.close();
    }
  }

  @override
  String toString() => 'BreathCapture(sampleRateHz=$sampleRateHz)';
}