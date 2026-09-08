import 'package:flutter_test/flutter_test.dart';

import 'package:healthguardian/triage/models.dart';
import 'package:healthguardian/triage/tier2.dart';

void main() {
  group('Tier2Assessment.merge (ADR-005 escalation-only invariant)', () {
    test('null suggestion leaves the base tier untouched', () {
      for (final base in TriageTier.values) {
        expect(Tier2Assessment.merge(base, Tier2Assessment.none), base);
      }
    });

    test('final tier is always the more urgent of base and suggestion', () {
      for (final base in TriageTier.values) {
        for (final suggestion in TriageTier.values) {
          final ai = Tier2Assessment(suggestion: suggestion);
          final merged = Tier2Assessment.merge(base, ai);
          expect(
            merged,
            base.atMostUrgent(suggestion),
            reason: 'base=$base suggestion=$suggestion',
          );
        }
      }
    });

    test('invariant: merged tier is never less urgent than base', () {
      for (final base in TriageTier.values) {
        for (final suggestion in TriageTier.values) {
          final merged = Tier2Assessment.merge(
            base,
            Tier2Assessment(suggestion: suggestion),
          );
          expect(merged.urgencyIndex, lessThanOrEqualTo(base.urgencyIndex));
        }
      }
    });

    test('escalatedFrom only reports true escalations', () {
      expect(Tier2Assessment(suggestion: TriageTier.p1).escalatedFrom(TriageTier.p3), isTrue);
      expect(Tier2Assessment(suggestion: TriageTier.p3).escalatedFrom(TriageTier.p3), isFalse);
      expect(Tier2Assessment.none.escalatedFrom(TriageTier.p3), isFalse);
      // Downgrade suggestion must never be reported as an escalation.
      expect(Tier2Assessment(suggestion: TriageTier.p5).escalatedFrom(TriageTier.p3), isFalse);
    });
  });

  group('Tier2Assessment JSON (record v2.1)', () {
    test('toJson/fromJson round-trips suggestion + summary', () {
      const original = Tier2Assessment(
        suggestion: TriageTier.p2,
        summary: '- line1\n- line2\n- line3\n- line4',
        requiresHumanVerification: true,
        elapsedMs: 8123,
      );
      final restored =
          Tier2Assessment.fromJson(original.toJson());
      expect(restored.suggestion, TriageTier.p2);
      expect(restored.summary, original.summary);
      expect(restored.elapsedMs, 8123);
    });

    test('toJson omits suggestion when absent (advisory-only)', () {
      const a = Tier2Assessment(summary: '- only a note');
      final json = a.toJson();
      expect(json.containsKey('suggestion'), isFalse);
      expect(json['summary'], '- only a note');
    });

    test('fromJson tolerates a missing suggestion key', () {
      final restored = Tier2Assessment.fromJson({'summary': '- x'});
      expect(restored.hasSuggestion, isFalse);
      expect(restored.summary, '- x');
    });
  });
}