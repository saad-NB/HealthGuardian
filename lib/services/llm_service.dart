import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fllama/fllama.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Thin wrapper around fllama's OpenAI-style chat API.
///
/// - Delivers streams of text deltas (fllama reports cumulative text,
///   we emit only the newly generated portion).
/// - Runs inference on fllama's background isolate (never blocks the UI).
class LlmService {
  LlmService({
    required this.modelPath,
    this.mmprojPath,
    this.numGpuLayers = 0,
    this.maxTokens = 256,
    this.contextSize = 4096,
    this.temperature = 0.1,
    this.onLog,
  });

  final String modelPath;
  final String? mmprojPath;
  final int numGpuLayers;
  final int maxTokens;
  final int contextSize;
  final double temperature;
  final void Function(String line)? onLog;

  static const String systemMessage =
      'You are a medical triage and imaging assistant for low-resource / '
      'offline settings. Answer concisely, safely, and never claim a '
      'diagnosis as certain.';

  /// Sends [prompt] (+ optional [imageBytes]) and yields generated text.
  Stream<String> chat(
    String prompt, {
    Uint8List? imageBytes,
    void Function(String fullOutput, int elapsedMs)? onFinished,
  }) async* {
    final controller = StreamController<String>();

    final userText = StringBuffer();
    final isVision = imageBytes != null && (mmprojPath?.isNotEmpty ?? false);
    if (isVision) {
      userText.write(
        '<img src="data:image/jpeg;base64,${base64Encode(imageBytes)}">\n\n',
      );
    }
    userText.write(prompt.trim());

    final request = OpenAiRequest(
      messages: [
        Message(Role.system, systemMessage),
        Message(Role.user, userText.toString()),
      ],
      modelPath: modelPath,
      mmprojPath: isVision ? mmprojPath : null,
      numGpuLayers: numGpuLayers,
      maxTokens: maxTokens,
      contextSize: contextSize,
      temperature: temperature,
      presencePenalty: 1.1,
      logger: onLog ?? (line) => debugPrint('[llama] $line'),
    );

    final output = StringBuffer();
    final sw = Stopwatch()..start();
    var lastLen = 0;

    final requestId = await fllamaChat(request, (response, responseJson, done) {
      if (!done && response.length > lastLen) {
        final delta = response.substring(lastLen);
        lastLen = response.length;
        output.write(delta);
        controller.add(delta);
      }
      if (done) {
        sw.stop();
        onFinished?.call(output.toString(), sw.elapsedMilliseconds);
        if (!controller.isClosed) controller.close();
      }
    });

    unawaited(() async {
      await Future<void>.delayed(const Duration(minutes: 15));
      if (!controller.isClosed) {
        controller.addError(StateError('Inference timed out (request $requestId).'));
        controller.close();
      }
    }());
    requestIdOfLastCall = requestId;

    yield* controller.stream;
  }

  int? requestIdOfLastCall;
}
