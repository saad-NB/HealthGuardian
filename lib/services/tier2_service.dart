import 'dart:async';

import 'package:fllama/fllama.dart' show Message;

import '../prompts/tier2_prompts.dart';
import '../state/app_state.dart';
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
  Tier2Service({required this.app, LlmService Function(AppState)? llmFactory})
      : _llmFactory = llmFactory ?? _defaultLlm;

  /// Shared app state used to resolve the model path and readiness.
  final AppState app;

  final LlmService Function(AppState app) _llmFactory;

  /// True when the MedGemma GGUF is downloaded and the device can run it.
  /// While false, the app is fully functional on Tier 1 alone.
  bool get available => app.modelReady;

  static LlmService _defaultLlm(AppState app) => LlmService(
        modelPath: app.modelPath ?? '',
        mmprojPath: app.mmprojPath,
        maxTokens: 512,
        contextSize: 4096,
        temperature: 0.1,
      );

  LlmService _llm() => _llmFactory(app);

  /// Runs the Tier 2 triage summary call: streaming output is parsed into a
  /// [Tier2Assessment]; parse failures fail closed to `none`.
  Future<Tier2Assessment> generateSummary(
    Tier2Payload payload, {
    void Function(String delta)? onToken,
  }) async {
    final sw = Stopwatch()..start();
    final buffer = StringBuffer();
    try {
      await for (final delta in _llm().chat(
        tier2SummaryUserPrompt(payload),
        systemPrompt: kTier2SummarySystem,
      )) {
        buffer.write(delta);
        onToken?.call(delta);
      }
    } catch (_) {
      return const Tier2Assessment();
    }

    final parsed = Tier2Parser.parse(buffer.toString());
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
  /// when the assistant reply completes.
  Stream<String> chatTurn({
    required String prompt,
    String? patientContext,
    List<Message>? history,
  }) {
    return _llm().chat(
      prompt,
      systemPrompt: chatSystemPrompt(patientContext: patientContext),
      history: history,
    );
  }
}