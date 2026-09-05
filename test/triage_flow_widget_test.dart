import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:healthguardian/ui/screens/triage/triage_flow_screen.dart';
import 'package:healthguardian/ui/theme/app_theme.dart';

Future<void> _tapContinue(WidgetTester tester) async {
  final button = find.text('Continue');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _goToDangerSigns(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(theme: buildAppTheme(), home: const TriageFlowScreen()),
  );
  await tester.tap(find.text('Adult'));
  await tester.pumpAndSettle();
}

void main() {
  group('Triage flow UI smoke test', () {
    testWidgets('age gate → adult → danger signs', (tester) async {
      await _goToDangerSigns(tester);
      expect(find.text('Does the patient have ANY of these right now?'),
          findsOneWidget);
    });

    testWidgets('a danger sign Yes jumps straight to the P1 result',
        (tester) async {
      await _goToDangerSigns(tester);

      final firstRow = find.byKey(const ValueKey('danger-A1'));
      final yes = find.descendant(of: firstRow, matching: find.text('Yes'));
      await tester.ensureVisible(yes);
      await tester.pumpAndSettle();
      await tester.tap(yes);
      await tester.pumpAndSettle();

      expect(find.text('P1 - Emergency'), findsOneWidget);
      expect(find.text('Next steps'), findsOneWidget);
    });

    testWidgets('healthy adult walkthrough maps to P5', (tester) async {
      await _goToDangerSigns(tester);
      await _tapContinue(tester);

      for (var i = 0; i < 8; i++) {
        await _tapContinue(tester);
      }

      expect(find.text('P5 - Minor'), findsOneWidget);
      expect(find.textContaining('NEWS2 score: 0'), findsOneWidget);
    });

    testWidgets('marking SpO2 missing shows the review banner on result',
        (tester) async {
      await _goToDangerSigns(tester);
      await _tapContinue(tester);
      await _tapContinue(tester);

      final missing = find.text('I cannot measure this');
      await tester.ensureVisible(missing);
      await tester.pumpAndSettle();
      await tester.tap(missing);
      await tester.pumpAndSettle();

      for (var i = 0; i < 7; i++) {
        await _tapContinue(tester);
      }

      expect(find.textContaining('readings were missing'), findsOneWidget);
    });
  });
}