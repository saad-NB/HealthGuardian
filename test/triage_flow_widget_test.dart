import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:healthguardian/ui/screens/triage/triage_flow_screen.dart';
import 'package:healthguardian/ui/theme/app_theme.dart';
import 'package:healthguardian/ui/theme/app_tokens.dart';
import 'package:healthguardian/ui/widgets/segmented_yes_no.dart';

Color segmentColor(WidgetTester tester, Finder segmentText) {
  final material = tester.widget<Material>(
    find.ancestor(of: segmentText, matching: find.byType(Material)).first,
  );
  return material.color!;
}

Future<void> _tapContinue(WidgetTester tester) async {
  final button = find.text('Continue');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _setAgeYears(WidgetTester tester, int years) async {
  final display = find.byKey(const ValueKey('valueDisplay'));
  await tester.ensureVisible(display);
  await tester.pumpAndSettle();
  await tester.tap(display);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    ),
    '$years',
  );
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

Future<void> _goToDangerSigns(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(theme: buildAppTheme(), home: const TriageFlowScreen()),
  );
  // Age starts blank; enter 30 to select the adult (NEWS2) scale.
  await _setAgeYears(tester, 30);
  await _tapContinue(tester); // confirm the patient info step
}

Future<void> _goToVitals(WidgetTester tester) async {
  await _goToDangerSigns(tester);
  await _tapContinue(tester);
}

/// Selects a complaint then walks through: menu Continue + "no more
/// problems", landing wherever the walkthrough goes next.
Future<void> _selectComplaint(WidgetTester tester, String complaint) async {
  await tester.ensureVisible(find.text(complaint));
  await tester.pumpAndSettle();
  await tester.tap(find.text(complaint));
  await tester.pumpAndSettle();
  await _tapContinue(tester);
  if (find.text('No, that is all').evaluate().isNotEmpty) {
    await tester.ensureVisible(find.text('No, that is all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No, that is all'));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('Triage flow UI smoke test', () {
    testWidgets('age gate → adult → danger signs', (tester) async {
      await _goToDangerSigns(tester);
      expect(find.text('Does the patient have ANY of these right now?'),
          findsOneWidget);
    });

    testWidgets('a danger sign Yes stays on the list; Continue lands on P1',
        (tester) async {
      await _goToDangerSigns(tester);

      final firstRow = find.byKey(const ValueKey('danger-A1'));
      final yes = find.descendant(of: firstRow, matching: find.text('Yes'));
      await tester.ensureVisible(yes);
      await tester.pumpAndSettle();
      await tester.tap(yes);
      await tester.pumpAndSettle();

      expect(find.text('Does the patient have ANY of these right now?'),
          findsOneWidget);
      expect(find.textContaining('emergency danger signal'), findsOneWidget);
      expect(find.text('See result now'), findsNothing);

      await _tapContinue(tester);

      expect(find.text('P1 - Emergency'), findsOneWidget);
      expect(find.text('Next steps'), findsOneWidget);
    });

    testWidgets('healthy adult walkthrough maps to P5', (tester) async {
      await _goToDangerSigns(tester);
      await _tapContinue(tester);

      // 7 continues to get through 7 vitals (rr → spo2 → sbp → hr → temp → onOxygen → copd → avpu).
      for (var i = 0; i < 7; i++) {
        await _tapContinue(tester);
      }

      // Now at avpu (8th vital). Continue goes to complaint step.
      await _tapContinue(tester);

      // Complaint step: pick "Other problem" then close the round.
      await _selectComplaint(tester, 'Other problem');

      // Modifiers step: advance past it (no risk factors selected).
      await _tapContinue(tester);

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

      // Continue through remaining vitals: sbp, hr, temp, onOxygen, copd, avpu,
      // then on the 7th continue reach the complaint step.
      for (var i = 0; i < 7; i++) {
        await _tapContinue(tester);
      }

      // Complaint step: pick "Other problem" then close the round.
      await _selectComplaint(tester, 'Other problem');

      // Missing SpO2 engages the sepsis screen; Continue through it.
      await _tapContinue(tester);

      // Modifiers step: advance past it.
      await _tapContinue(tester);

      expect(find.textContaining('readings were missing'), findsOneWidget);
    });

    testWidgets('+ and - stay on the same question and update the readout',
        (tester) async {
      await _goToVitals(tester);
      expect(find.text('Breaths per minute (breathing rate)'), findsOneWidget);

      await tester.ensureVisible(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('Breaths per minute (breathing rate)'), findsOneWidget);
      expect(find.text('18 /min'), findsOneWidget);

      await tester.ensureVisible(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();

      expect(find.text('Breaths per minute (breathing rate)'), findsOneWidget);
      expect(find.text('17 /min'), findsOneWidget);
    });

    testWidgets('tap value box opens numeric dialog; letters are stripped',
        (tester) async {
      await _goToVitals(tester);

      await tester.ensureVisible(find.byKey(const ValueKey('valueDisplay')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('valueDisplay')));
      await tester.pumpAndSettle();

      final field = find.byType(TextField);
      expect(field, findsOneWidget);

      await tester.enterText(field, '4a2b');
      var controller =
          tester.widget<TextField>(field).controller!;
      expect(controller.text, '42');

      await tester.enterText(field, '25');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Breaths per minute (breathing rate)'), findsOneWidget);
      expect(find.text('25 /min'), findsOneWidget);
    });

    testWidgets('typed value above the hard limit is clamped',
        (tester) async {
      await _goToVitals(tester);

      await tester.ensureVisible(find.byKey(const ValueKey('valueDisplay')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('valueDisplay')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '9999');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('200 /min'), findsOneWidget);
    });

    testWidgets('danger rows start uncolored; tapping No highlights only No',
        (tester) async {
      await _goToDangerSigns(tester);

      final firstRow = find.byKey(const ValueKey('danger-A1'));
      final yes = find.descendant(of: firstRow, matching: find.text('Yes'));
      final no = find.descendant(of: firstRow, matching: find.text('No'));

      expect(segmentColor(tester, yes), AppColors.optionFill);
      expect(segmentColor(tester, no), AppColors.optionFill);

      await tester.ensureVisible(no);
      await tester.pumpAndSettle();
      await tester.tap(no);
      await tester.pumpAndSettle();

      expect(segmentColor(tester, no), AppColors.teal700);
      expect(segmentColor(tester, yes), AppColors.optionFill);
      expect(find.text('Does the patient have ANY of these right now?'),
          findsOneWidget);
    });
  });

  group('SegmentedYesNo tri-state', () {
    Widget app({bool? value}) => MaterialApp(
          home: Scaffold(
            body: SegmentedYesNo(value: value, onChanged: (_) {}),
          ),
        );

    testWidgets('null value colors no segment', (tester) async {
      await tester.pumpWidget(app());
      expect(segmentColor(tester, find.text('Yes')), AppColors.optionFill);
      expect(segmentColor(tester, find.text('No')), AppColors.optionFill);
    });

    testWidgets('true colors Yes only', (tester) async {
      await tester.pumpWidget(app(value: true));
      expect(segmentColor(tester, find.text('Yes')), AppColors.teal700);
      expect(segmentColor(tester, find.text('No')), AppColors.optionFill);
    });

    testWidgets('false colors No only', (tester) async {
      await tester.pumpWidget(app(value: false));
      expect(segmentColor(tester, find.text('Yes')), AppColors.optionFill);
      expect(segmentColor(tester, find.text('No')), AppColors.teal700);
    });
  });
}