import 'dart:math' as math;

import 'package:fllama/fllama.dart' show Message;

/// Per-call inference budgets for the local MedGemma worker (ADR-014/ADR-019).
///
/// fllama hardcodes `n_parallel = 4` with a non-unified KV cache, so llama.cpp
/// divides the requested context by four (`n_ctx_seq = n_ctx / 4`). Every budget
/// here is therefore expressed against the **usable** per-sequence window
/// ([usableContext]); the value actually handed to fllama is [requestedContext]
/// (`usableContext * parallelSlots`).
///
/// Completion is computed dynamically from the measured prompt every call so a
/// reply can never overflow the window:
/// - summary: a strict-JSON reply always gets room, clamped to a
///   [summaryCompletionFloor, summaryCompletionCap] band.
/// - chat: the reply gets the remaining window, clamped to a
///   [chatCompletionFloor, chatCompletionCap] band; history is compacted rather
///   than letting the prompt overflow.
///
/// Token estimate is a cheap heuristic (≈3 chars per token) used only to size
/// budgets; the native server still owns the real tokenization.
class InferenceBudget {
  InferenceBudget._();

  /// fllama's hardcoded `n_parallel` (see `device_capabilities.dart`).
  static const int parallelSlots = 4;

  /// Conservative chars-per-token heuristic for English + medical JSON.
  static const double charsPerToken = 3.0;

  static int _usableContext = 2048;

  /// Sets the per-sequence window from the detected device profile. Values
  /// `<= 0` are ignored so a disabled device keeps a sane default for tests.
  static void configure({required int usableContext}) {
    if (usableContext > 0) _usableContext = usableContext;
  }

  /// Tokens available to a single conversation (`n_ctx_seq`).
  static int get usableContext => _usableContext;

  /// `contextSize` (n_ctx) to hand to fllama so one conversation gets
  /// [usableContext] tokens.
  static int get requestedContext => _usableContext * parallelSlots;

  /// Completion budget for the Tier 2 summary call.
  static const int summaryHeadroom = 320;
  static const int summaryCompletionFloor = 512;
  static const int summaryCompletionCap = 1536;

  /// Completion budget for chat turns.
  static const int chatHeadroom = 192;
  static const int chatCompletionFloor = 384;
  static const int chatCompletionCap = 1024;

  /// Max prompt tokens (excluding completion) after which chat history must be
  /// compacted so completion never drops below [chatCompletionFloor].
  static int get chatPromptCap =>
      math.max(0, usableContext - chatCompletionFloor - chatHeadroom);

  static int estimateTokens(String text) =>
      (text.length / charsPerToken).ceil();

  /// Clamps [room] into `[floor, cap]` but never above the available room, so
  /// `prompt + completion` always fits inside [usableContext].
  static int _completion(int room, int floor, int cap) {
    if (room <= 0) return 0;
    return room.clamp(math.min(floor, room), math.min(cap, room));
  }

  /// Dynamic `maxTokens` for the summary call given the prompt's token size.
  static int summaryCompletion(int promptTokens) => _completion(
        usableContext - promptTokens - summaryHeadroom,
        summaryCompletionFloor,
        summaryCompletionCap,
      );

  /// Dynamic `maxTokens` for a chat turn given the prompt's token size.
  static int chatCompletion(int promptTokens) => _completion(
        usableContext - promptTokens - chatHeadroom,
        chatCompletionFloor,
        chatCompletionCap,
      );

  /// Keeps the newest [budgetTokens]-worth of [history], always retaining the
  /// last message (the pending user question). Callers pass only the chat
  /// transcript — system prompt and the attached triage context are sized
  /// separately and never dropped.
  static List<Message> compactHistory(
    List<Message> history,
    int budgetTokens,
  ) {
    if (history.isEmpty) return history;
    final keep = <Message>[];
    var running = 0;
    for (var i = history.length - 1; i >= 0; i--) {
      final m = history[i];
      running += estimateTokens(m.text);
      if (running > budgetTokens && keep.isNotEmpty) {
        break;
      }
      keep.insert(0, m);
    }
    if (keep.isEmpty) {
      keep.add(history.last);
    }
    return keep;
  }

  static int _tokensOf(List<Message> messages) =>
      messages.fold(0, (sum, m) => sum + estimateTokens(m.text));

  /// Convenience: prompt token count for a chat turn (system + optional
  /// attached triage context + transcript).
  static int chatPromptTokens({
    required String systemText,
    String? contextText,
    List<Message>? history,
  }) =>
      estimateTokens(systemText) +
      estimateTokens(contextText ?? '') +
      _tokensOf(history ?? const []);
}
