import 'package:fllama/fllama.dart' show Message, Role;
import 'package:flutter_test/flutter_test.dart';

import 'package:healthguardian/triage/inference_budget.dart';

void main() {
  setUp(() => InferenceBudget.configure(usableContext: 2048));

  group('estimateTokens', () {
    test('uses ~3 chars per token', () {
      expect(InferenceBudget.estimateTokens('hello'), 2);
      expect(InferenceBudget.estimateTokens(''), 0);
      expect(InferenceBudget.estimateTokens('a' * 100), 34);
    });
  });

  group('usable vs requested context (fllama n_parallel = 4)', () {
    test('requested is four times the usable window', () {
      InferenceBudget.configure(usableContext: 3072);
      expect(InferenceBudget.usableContext, 3072);
      expect(InferenceBudget.requestedContext, 12288);
      expect(InferenceBudget.parallelSlots, 4);
    });
  });

  group('summaryCompletion (dynamic, ADR-014/019)', () {
    test('caps at 1536 when the prompt is tiny', () {
      expect(InferenceBudget.summaryCompletion(0), 1536);
    });

    test('never exceeds the remaining room', () {
      for (var p = 0; p <= InferenceBudget.usableContext; p += 128) {
        final c = InferenceBudget.summaryCompletion(p);
        expect(p + c, lessThanOrEqualTo(InferenceBudget.usableContext));
      }
    });

    test('drops to zero once the prompt fills the window', () {
      expect(InferenceBudget.summaryCompletion(2048), 0);
      expect(InferenceBudget.summaryCompletion(30000), 0);
    });
  });

  group('chatCompletion (usable window)', () {
    test('caps at 1024 on a small prompt', () {
      expect(InferenceBudget.chatCompletion(0), 1024);
    });

    test('prompt + completion always fit in the usable window', () {
      for (var p = 0; p <= InferenceBudget.usableContext; p += 128) {
        final c = InferenceBudget.chatCompletion(p);
        expect(p + c, lessThanOrEqualTo(InferenceBudget.usableContext));
      }
    });

    test('returns zero when the prompt already fills the window', () {
      expect(InferenceBudget.chatCompletion(2048), 0);
    });
  });

  group('chatPromptCap', () {
    test('leaves the completion floor plus headroom', () {
      expect(
        InferenceBudget.usableContext - InferenceBudget.chatPromptCap,
        InferenceBudget.chatCompletionFloor + InferenceBudget.chatHeadroom,
      );
    });
  });

  group('compactHistory', () {
    Message msg(String t) => Message(Role.user, t);

    test('keeps everything when within budget', () {
      final h = [msg('one'), msg('two'), msg('three')];
      expect(InferenceBudget.compactHistory(h, 100000), hasLength(3));
    });

    test('keeps the newest messages when over budget', () {
      final h = [
        msg('a' * 500),
        msg('b' * 500),
        msg('c' * 500),
        msg('d' * 500),
        msg('e' * 500),
      ];
      final kept = InferenceBudget.compactHistory(h, 300);
      expect(kept, isNotEmpty);
      expect(kept.last.text, 'e' * 500, reason: 'newest message always kept');
      expect(kept.fold<int>(0, (s, m) => s + m.text.length), lessThanOrEqualTo(300 * 4));
    });

    test('a single over-budget message is still returned', () {
      final h = [msg('x' * 10_000)];
      final kept = InferenceBudget.compactHistory(h, 10);
      expect(kept, hasLength(1));
      expect(kept.single.text, 'x' * 10_000);
    });

    test('empty history stays empty', () {
      expect(InferenceBudget.compactHistory(const [], 100), isEmpty);
    });
  });

  group('chatPromptTokens', () {
    test('sums system, context and history', () {
      final tokens = InferenceBudget.chatPromptTokens(
        systemText: 'a' * 30,
        contextText: 'b' * 30,
        history: [Message(Role.user, 'c' * 30)],
      );
      expect(tokens, 30);
    });
  });
}
