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
  ///
  /// [systemPrompt] overrides the default [systemMessage]; pass `null` to use
  /// the default. [history] carries prior turns as User/Assistant messages
  /// (never a system role) so multi-turn chat stays grounded.
  ///
  /// [onFinished] reports the final `finish_reason` reported by llama.cpp
  /// (`"stop"`, `"length"`, `"tool_calls"` or `"unknown"`); `"length"` means
  /// the reply hit its token cap and is truncated.
  Stream<String> chat(
    String prompt, {
    String? systemPrompt,
    List<Message>? history,
    Uint8List? imageBytes,
    bool Function(String accumulated)? stopWhen,
    void Function(String fullOutput, int elapsedMs, String finishedReason)?
        onFinished,
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

    final messages = <Message>[
      Message(Role.system, systemPrompt ?? systemMessage),
      ...?history,
      Message(Role.user, userText.toString()),
    ];

    final request = OpenAiRequest(
      messages: messages,
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
    int? requestId;
    var stopSent = false;

    void maybeStop() {
      final predicate = stopWhen;
      if (stopSent || predicate == null) return;
      if (!predicate(output.toString())) return;
      stopSent = true;
      final id = requestId;
      if (id != null) fllamaCancelInference(id);
    }

    final createdId = await fllamaChat(request, (response, responseJson, done) {
      if (!done && response.length > lastLen) {
        final delta = response.substring(lastLen);
        lastLen = response.length;
        output.write(delta);
        controller.add(delta);
      }
      if (done) {
        sw.stop();
        if (response.length > lastLen) {
          final rest = response.substring(lastLen);
          lastLen = response.length;
          output.write(rest);
          controller.add(rest);
        }
        onFinished?.call(
          output.toString(),
          sw.elapsedMilliseconds,
          parseFinishedReason(responseJson),
        );
        if (!controller.isClosed) controller.close();
        return;
      }
      maybeStop();
    });
    requestId = createdId;
    // A stop condition may have fired before the id was known.
    if (stopSent) fllamaCancelInference(createdId);

    unawaited(() async {
      await Future<void>.delayed(const Duration(minutes: 15));
      if (!controller.isClosed) {
        controller.addError(StateError('Inference timed out (request $createdId).'));
        controller.close();
      }
    }());
    requestIdOfLastCall = createdId;

    yield* controller.stream;
  }

  /// Extracts the OpenAI-style `finish_reason` (`"stop"`, `"length"`,
  /// `"tool_calls"`) from the stream chunk JSON fllama reports, or
  /// `"unknown"` when it is absent/unparseable.
  static String parseFinishedReason(String responseJson) {
    if (responseJson.trim().isEmpty) return 'unknown';
    try {
      final root = jsonDecode(responseJson);
      final choices = (root as Map<String, dynamic>)['choices'];
      if (choices is List) {
        for (final choice in choices) {
          if (choice is Map<String, dynamic>) {
            final reason = choice['finish_reason'];
            if (reason is String && reason.isNotEmpty) return reason;
          }
        }
      }
    } catch (_) {
      // fall through -> unknown
    }
    return 'unknown';
  }

  int? requestIdOfLastCall;
}
