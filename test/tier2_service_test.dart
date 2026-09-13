import 'dart:typed_data';

import 'package:fllama/fllama.dart' show Message, Role;
import 'package:flutter_test/flutter_test.dart';

import 'package:healthguardian/services/llm_service.dart';
import 'package:healthguardian/services/tier2_service.dart';
import 'package:healthguardian/state/app_state.dart';
import 'package:healthguardian/triage/inference_budget.dart';
import 'package:healthguardian/triage/models.dart';
import 'package:healthguardian/triage/tier2.dart';

class _Reply {
  const _Reply(this.content, this.reason);

  final String content;
  final String reason;
}

class _FakeLlm extends LlmService {
  _FakeLlm(this.replies, this.createdTokens, this.createdContextSize)
      : super(
          modelPath: 'fake',
          maxTokens: createdTokens,
          contextSize: createdContextSize,
        );

  final List<_Reply> replies;
  final int createdTokens;
  final int createdContextSize;

  @override
  Stream<String> chat(
    String prompt, {
    String? systemPrompt,
    List<Message>? history,
    Uint8List? imageBytes,
    bool Function(String accumulated)? stopWhen,
    void Function(String fullOutput, int elapsedMs, String finishedReason)?
        onFinished,
  }) async* {
    assert(replies.isNotEmpty, 'fake llm ran out of scripted replies');
    final reply = replies.removeAt(0);
    yield reply.content;
    onFinished?.call(reply.content, 5, reply.reason);
  }
}

List<int> _maxTokensSeen = [];
int _contextSizeSeen = -1;
int _factoryCalls = 0;

Tier2Service _service(List<_Reply> replies) {
  _maxTokensSeen = [];
  _contextSizeSeen = -1;
  _factoryCalls = 0;
  return Tier2Service(
    app: AppState(),
    llmFactory: (app, maxTokens, contextSize) {
      _factoryCalls++;
      _maxTokensSeen.add(maxTokens);
      _contextSizeSeen = contextSize;
      return _FakeLlm(replies, maxTokens, contextSize);
    },
  );
}

void main() {
  setUp(() => InferenceBudget.configure(usableContext: 2048));

  group('Tier2Service.generateSummary budgets and retries', () {
    test('success on first attempt returns populated assessment', () async {
      const replyText =
          '{"triage_level":5,"summary":"- Stable vitals\\n- No red flags",'
          '"requires_human_verification":false}';
      final service = _service([const _Reply(replyText, 'stop')]);

      final result = await service.generateSummary(Tier2Payload({'k': 'v'}));

      expect(result.suggestion, TriageTier.p5);
      expect(result.summary, contains('- Stable vitals'));
      expect(result.requiresHumanVerification, isFalse);
      expect(_factoryCalls, 1);
      expect(_maxTokensSeen.single, inInclusiveRange(512, 1536));
      expect(_contextSizeSeen, InferenceBudget.requestedContext);
      expect(service.lastAttempts, contains('finish=stop'));
      expect(service.lastError, isEmpty);
    });

    test('turns a fixable length-truncated first attempt into a retry',
        () async {
      const validReply =
          '{"triage_level":5,"summary":"ok","requires_human_verification":false}';
      final service = _service([
        const _Reply('{"triage_level":5,"summary":"cut', 'length'),
        const _Reply(validReply, 'stop'),
      ]);

      final result = await service.generateSummary(Tier2Payload({'k': 'v'}));

      expect(result.suggestion, TriageTier.p5);
      expect(_factoryCalls, 2);
      expect(_maxTokensSeen[0], inInclusiveRange(512, 1536));
      expect(_maxTokensSeen[1], _maxTokensSeen[0],
          reason: 'retry uses the same fitting budget');
      expect(service.lastAttempts, contains('finish=length'));
    });

    test('fails closed after both attempts are length-truncated', () async {
      final service = _service([
        const _Reply('{"triage_level":5","summary":"c', 'length'),
        const _Reply('{"triage_level":5","summary":"c', 'length'),
      ]);

      final result = await service.generateSummary(Tier2Payload({'k': 'v'}));

      expect(result.suggestion, isNull);
      expect(result.summary, isEmpty);
      expect(result.requiresHumanVerification, isTrue);
      expect(_factoryCalls, 2);
      expect(_maxTokensSeen[0], inInclusiveRange(512, 1536));
      expect(_maxTokensSeen[1], _maxTokensSeen[0]);
      expect(service.lastError, contains('empty reply after retry'));
    });

    test('still fails closed when the reply is empty (cold start)', () async {
      final service = _service([
        const _Reply('', 'stop'),
        const _Reply('', 'stop'),
      ]);

      final result = await service.generateSummary(Tier2Payload({'k': 'v'}));

      expect(result.suggestion, isNull);
      expect(_factoryCalls, 2);
    });
  });

  group('Tier2Service.chatTurn budgets', () {
    test('uses the requested context and an in-range completion', () async {
      final service = _service([
        const _Reply('{"triage_level":5,"summary":"ok","requires_human_verification":false}', 'stop'),
      ]);
      final history = [
        Message(Role.user, 'Does it need a hospital?'),
        Message(Role.assistant, 'Not right away.'),
      ];

      String? receivedReason;
      final chunks = <String>[];
      await for (final c in service.chatTurn(
        prompt: 'So it is minor?',
        patientContext: 'Patient: adult, normal vitals, P5.',
        history: history,
        onFinished: (_, _, reason) => receivedReason = reason,
      )) {
        chunks.add(c);
      }

      expect(chunks, isNotEmpty);
      expect(receivedReason, 'stop');
      expect(_contextSizeSeen, InferenceBudget.requestedContext);
      expect(_maxTokensSeen.single, inInclusiveRange(384, 1024));
    });
  });
}