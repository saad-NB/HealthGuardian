import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:healthguardian/services/tier2_service.dart';
import 'package:healthguardian/state/app_state.dart';
import 'package:healthguardian/triage/models.dart';
import 'package:healthguardian/triage/tier2.dart';
import 'package:healthguardian/ui/screens/triage/result_step.dart';
import 'package:healthguardian/ui/theme/app_theme.dart';

class _FakeTier2Service extends Tier2Service {
  _FakeTier2Service({
    required super.app,
    this.availableOverride = true,
    this.assessment = Tier2Assessment.none,
  });

  final bool availableOverride;
  final Tier2Assessment assessment;

  @override
  bool get available => availableOverride;

  @override
  Future<Tier2Assessment> generateSummary(
    Tier2Payload payload, {
    void Function(String delta)? onToken,
  }) async =>
      assessment;
}

TriageAnswers _adultNormal() {
  final a = TriageAnswers();
  a.ageGroup = AgeGroup.adult;
  a.respiratoryRate = 14;
  a.spo2 = 98;
  a.systolicBp = 120;
  a.heartRate = 70;
  a.temperature = 36.8;
  a.consciousness = Avpu.alert;
  a.onOxygen = false;
  a.copdCo2Retention = false;
  a.chiefComplaint = ChiefComplaint.throat;
  return a;
}

Future<void> _pump(
  WidgetTester tester, {
  required Tier2Service service,
  TriageAnswers? answers,
  AppState? app,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: ResultStep(
          answers: answers ?? _adultNormal(),
          onEditVitals: () {},
          onEditDanger: () {},
          onRestart: () {},
          jumpedFromDanger: false,
          app: app ?? AppState(),
          tier2Service: service,
        ),
      ),
    ),
  );
}

void main() {
  group('ResultStep Tier 2 UI (ADR-014)', () {
    testWidgets('hides AI features when the model is unavailable',
        (tester) async {
      final service = _FakeTier2Service(
        app: AppState(),
        availableOverride: false,
      );
      await _pump(tester, service: service);

      expect(find.text('Generate AI summary (Tier 2)'), findsNothing);
      expect(find.text('AI analysis (MedGemma)'), findsNothing);
      // Tier 1 banner sections are still present and authoritative.
      expect(find.text('Why this result'), findsOneWidget);
      expect(find.text('Next steps'), findsOneWidget);
    });

    testWidgets('generates AI summary and shows Tier 1 flag above AI flag',
        (tester) async {
      final service = _FakeTier2Service(
        app: AppState(),
        assessment: const Tier2Assessment(
          suggestion: TriageTier.p2,
          summary: '- line1\n- line2\n- line3\n- line4',
        ),
      );
      await _pump(tester, service: service);

      final generate = find.text('Generate AI summary (Tier 2)');
      await tester.ensureVisible(generate);
      await tester.pumpAndSettle();
      await tester.tap(generate);
      await tester.pumpAndSettle();

      // Both flags rendered.
      expect(find.text('AI analysis (MedGemma)'), findsOneWidget);
      expect(find.text('P2'), findsWidgets);
      // Escalation merge note is visible.
      expect(find.textContaining('AI flags higher urgency'), findsOneWidget);

      // Ordering: Tier 1 reasoning appears above the AI card.
      final tier1Y = tester.getTopLeft(find.text('Why this result')).dy;
      final aiY = tester.getTopLeft(find.text('AI analysis (MedGemma)')).dy;
      expect(tier1Y, lessThan(aiY));

      // Merge keeps the escalation and surfaces the summary.
      expect(find.textContaining('line1'), findsOneWidget);
      expect(find.textContaining('final P2'), findsOneWidget);
    });

    testWidgets('Ask about this result opens the seeded chat', (tester) async {
      final service = _FakeTier2Service(
        app: AppState(),
        assessment: const Tier2Assessment(suggestion: TriageTier.p2, summary: '- a'),
      );
      await _pump(tester, service: service);

      final generate = find.text('Generate AI summary (Tier 2)');
      await tester.ensureVisible(generate);
      await tester.pumpAndSettle();
      await tester.tap(generate);
      await tester.pumpAndSettle();

      final ask = find.text('Ask about this result');
      await tester.ensureVisible(ask);
      await tester.pumpAndSettle();
      await tester.tap(ask);
      await tester.pumpAndSettle();

      expect(find.text('Triage context attached'), findsOneWidget);
      expect(find.textContaining('Type your question'), findsOneWidget);
    });
  });
}