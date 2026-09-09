import 'dart:async';

import 'package:fllama/fllama.dart' show Message;
import 'package:flutter/foundation.dart' show debugPrint;

import '../prompts/tier2_prompts.dart';
import '../state/app_state.dart';
import '../triage/inference_budget.dart';
import '../triage/tier2.dart';
import '../triage/tier2_parser.dart';
import 'llm_service.dart';

/// Orchestrates Tier 2 (MedGemma-1.5-4B via fllama): the triage summary call
/// and the context-aware chat surfaces (ADR-014).
///
/// Inject a fake subclass in widget tests; the real service delegates to
/// [LlmService] on fllama's background isolate and is fail-closed — every
/// failure returns [Tier2Assessment.none] so Tier 1 always stands.
class Tier2Service {
  Tier2Service({
    required this.app,
    LlmService Function(AppState app, int maxTokens, int contextSize)?
        llmFactory,
  }) : _llmFactory = llmFactory ?? _defaultLlm;

  /// Shared app state used to resolve the model path and readiness.
  final AppState app;

  final LlmService Function(AppState app, int maxTokens, int contextSize)
      _llmFactory;

  /// True when the MedGemma GGUF is downloaded and the device can run it.
  /// While false, the app is fully functional on Tier 1 alone.
  bool get available => app.modelReady;

  /// Last inference error string (empty on success). Useful for debugging
  /// fail-closed Tier 2 calls on-device.
  String lastError = '';

  /// Per-attempt diagnostics from the most recent [generateSummary] call,
  /// e.g. `[a1:218000ms bytes=0 err=- finish=stop][a2:...]`. Empty until a call
  /// runs.
  String lastAttempts = '';

  static LlmService _defaultLlm(AppState app, int maxTokens, int contextSize) =>
      LlmService(
        modelPath: app.modelPath ?? '',
        mmprojPath: app.mmprojPath,
        maxTokens: maxTokens,
        contextSize: contextSize,
        temperature: 0.1,
      );

  LlmService _llm(int maxTokens, int contextSize) =>
      _llmFactory(app, maxTokens, contextSize);

  /// Runs the Tier 2 triage summary call: streaming output is parsed into a
  /// [Tier2Assessment]; parse failures fail closed to `none`.
  ///
  /// The completion budget is dynamic ([InferenceBudget.summaryCompletion]).
  /// Up to one retry happens on cold-start error/empty or on a `length`
  /// truncated reply; the retry runs at the max budget.
  Future<Tier2Assessment> generateSummary(
    Tier2Payload payload, {
    void Function(String delta)? onToken,
  }) async {
    final sw = Stopwatch()..start();
    final buffer = StringBuffer();
    lastError = '';
    final promptTokens = InferenceBudget.estimateTokens(kTier2SummarySystem) +
        InferenceBudget.estimateTokens(tier2SummaryUserPrompt(payload));

    Future<int> invoke() async {
      var tried = 0;
      Object? error;
      lastAttempts = '';
      while (tried < 2) {
        tried++;
        error = null;
        buffer.clear();
        final completion = tried == 1
            ? InferenceBudget.summaryCompletion(promptTokens)
            : InferenceBudget.summaryCompletionCap;
        var finishedReason = 'unknown';
        final stepSw = Stopwatch()..start();
        try {
          await for (final delta in _llm(
            completion,
            InferenceBudget.summaryContextSize,
          ).chat(
            tier2SummaryUserPrompt(payload),
            systemPrompt: kTier2SummarySystem,
            onFinished: (_, _, reason) => finishedReason = reason,
          )) {
            buffer.write(delta);
            onToken?.call(delta);
          }
        } catch (e) {
          error = e;
        }
        stepSw.stop();
        lastAttempts += '[a$tried:${stepSw.elapsedMilliseconds}ms '
            'bytes=${buffer.toString().length} err=${error ?? '-'} '
            'finish=$finishedReason]';
        // Success = a non-empty reply that did not hit the token cap.
        if (error == null &&
            buffer.toString().trim().isNotEmpty &&
            finishedReason != 'length') {
          return 0;
        }
        // Cold-start loads sometimes emit nothing (error or empty reply) and a
        // `length` reply means the JSON may have been cut; retry once warm at
        // the max budget.
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      lastError = error?.toString() ?? 'empty reply after retry';
      debugPrint('[tier2] inference error (after retry): $lastError');
      return -1;
    }

    final exit = await invoke();
    if (exit != 0) return const Tier2Assessment();

    final parsed = Tier2Parser.parse(buffer.toString());
    // Keep the raw reply in logcat for model diagnostics (ADR-014).
    debugPrint('[tier2] reply ${sw.elapsedMilliseconds}ms bytes=${buffer.toString().length} '
        'suggestion=${parsed.suggestion} reply: ${buffer.toString()}');
    return Tier2Assessment(
      suggestion: parsed.suggestion,
      summary: parsed.summary,
      requiresHumanVerification: parsed.requiresHumanVerification,
      rawOutput: parsed.rawOutput,
      elapsedMs: sw.elapsedMilliseconds,
    );
  }

  /// Streams one context-aware chat turn. [history] holds prior exchanges as
  /// User/Assistant [Message]s (no system role). Yields text deltas and ends
  /// when the assistant reply completes. The reply budget is dynamic within the
  /// fixed chat context window ([InferenceBudget.chatCompletion]).
  Stream<String> chatTurn({
    required String prompt,
    String? patientContext,
    List<Message>? history,
    void Function(String fullOutput, int elapsedMs, String finishedReason)?
        onFinished,
  }) {
    final systemPrompt = chatSystemPrompt(patientContext: patientContext);
    final promptTokens = InferenceBudget.chatPromptTokens(
      systemText: systemPrompt,
      history: history,
    );
    final completion = InferenceBudget.chatCompletion(promptTokens);
    return _llm(completion, InferenceBudget.chatContextSize).chat(
      prompt,
      systemPrompt: systemPrompt,
      history: history,
      onFinished: onFinished,
    );
  }
}