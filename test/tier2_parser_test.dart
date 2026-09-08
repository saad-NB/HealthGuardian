import 'package:flutter_test/flutter_test.dart';

import 'package:healthguardian/triage/models.dart';
import 'package:healthguardian/triage/tier2_parser.dart';

void main() {
  group('Tier2Parser.parse (fail-closed, ADR-014)', () {
    test('parses a clean strict-JSON reply', () {
      final a = Tier2Parser.parse(
        '{"triage_level":"P1","summary":"- a\\n- b\\n- c\\n- d","requires_human_verification":true}',
      );
      expect(a.suggestion, TriageTier.p1);
      expect(a.summary, contains('- a'));
      expect(a.requiresHumanVerification, isTrue);
    });

    test('tolerates prose wrapped around the JSON object', () {
      final raw =
          'Here is my analysis:\\n{"triage_level": "P2", '
          '"summary": "- high risk\\n- monitor"} \\nHope that helps.';
      final a = Tier2Parser.parse(raw);
      expect(a.suggestion, TriageTier.p2);
      expect(a.summary, contains('high risk'));
    });

    test('accepts lowercase and numeric tiers', () {
      expect(Tier2Parser.parse('{"triage_level":"p5","summary":"- x"}').suggestion,
          TriageTier.p5);
      expect(Tier2Parser.parse('{"triage_level":3,"summary":"- x"}').suggestion,
          TriageTier.p3);
      expect(Tier2Parser.parse('{"tier":"emergency","summary":"- x"}').suggestion,
          TriageTier.p1);
    });

    test('empty string fails closed to no suggestion', () {
      final a = Tier2Parser.parse('   ');
      expect(a.hasSuggestion, isFalse);
      expect(a.summary, isEmpty);
    });

    test('non-JSON garbage fails closed', () {
      final a = Tier2Parser.parse('I think the patient is fine.');
      expect(a.hasSuggestion, isFalse);
    });

    test('off-schema tier value fails closed (never guesses)', () {
      final a = Tier2Parser.parse('{"triage_level":"P9","summary":"- x"}');
      expect(a.hasSuggestion, isFalse);
      expect(a.summary, '- x');
    });

    test('missing tier key fails closed but keeps the summary', () {
      final a = Tier2Parser.parse('{"summary":"- nothing flagged"}');
      expect(a.hasSuggestion, isFalse);
      expect(a.summary, '- nothing flagged');
    });

    test('unbalanced braces fail closed', () {
      final a = Tier2Parser.parse('{"triage_level":"P1"');
      expect(a.hasSuggestion, isFalse);
    });

    test('nested strings with braces do not confuse the extractor', () {
      final raw = '{"triage_level":"P1","summary":"say } now"}';
      final a = Tier2Parser.parse(raw);
      expect(a.suggestion, TriageTier.p1);
      expect(a.summary, contains('} now'));
    });

    test('default requires_human_verification is true', () {
      final a = Tier2Parser.parse('{"triage_level":"P1","summary":"- x"}');
      expect(a.requiresHumanVerification, isTrue);
    });
  });
}