import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:healthguardian/ui/screens/triage/triage_flow_screen.dart';
import 'package:healthguardian/ui/theme/app_theme.dart';

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapContinue(WidgetTester tester) =>
    _tap(tester, find.text('Continue'));

Future<void> _setAgeYears(WidgetTester tester, int years) async {
  await _tap(tester, find.byKey(const ValueKey('valueDisplay')));
  await tester.enterText(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    ),
    '$years',
  );
  await _tap(tester, find.text('Save'));
}

Future<void> _selectAge(WidgetTester tester, String age) async {
  await tester.pumpWidget(
    MaterialApp(theme: buildAppTheme(), home: const TriageFlowScreen()),
  );
  // Age starts blank; the band is derived from the entered number. The only
  // explicit shortcut is "Newborn" for patients under 1 year.
  if (age == 'Newborn') {
    await _tap(tester, find.text('Newborn'));
  } else if (age == 'Toddler') {
    await _setAgeYears(tester, 2);
  } else {
    await _setAgeYears(tester, 30);
  }
  await _tapContinue(tester); // confirm the patient info step
}

Future<void> _finishComplaint(WidgetTester tester) async {
  await _tapContinue(tester); // complaint menu -> next round
  await _tap(tester, find.text('No, that is all')); // no more complaints
}

void main() {
  group('New flow steps', () {
    testWidgets('chest complaint advances to probe questions', (tester) async {
      await _selectAge(tester, 'Adult');
      for (var i = 0; i < 9; i++) {
        await _tapContinue(tester);
      }

      await _tap(tester, find.text('Chest pain'));
      await _tapContinue(tester); // confirm the complaint menu
      expect(find.text('Questions about Chest pain'), findsOneWidget);
      expect(find.textContaining('spread to the arm'), findsOneWidget);
    });

    testWidgets('toddler walkthrough includes capillary refill step',
        (tester) async {
      await _selectAge(tester, 'Toddler');
      for (var i = 0; i < 5; i++) {
        await _tapContinue(tester);
      }
      expect(find.text('Capillary refill time'), findsOneWidget);

      // Skip COPD step (not present for pediatric).
      await _tapContinue(tester); // refill -> onOxygen
      await _tapContinue(tester); // onOxygen -> avpu
      expect(find.text('How alert is the patient?'), findsOneWidget);
      expect(find.text('Known COPD or CO2 retention?'), findsNothing);
    });

    testWidgets('newborn walkthrough shows feeding step and no AVPU',
        (tester) async {
      await _selectAge(tester, 'Newborn');
      for (var i = 0; i < 5; i++) {
        await _tapContinue(tester);
      }
      expect(find.text('How alert is the baby and how is it feeding?'),
          findsOneWidget);
      // Neonate has no AVPU step; no SBP step.
      expect(find.text('How alert is the patient?'), findsNothing);
      expect(find.text('Systolic blood pressure (mmHg)'), findsNothing);
    });

    testWidgets('fever complaint engages the sepsis screen', (tester) async {
      await _selectAge(tester, 'Adult');
      for (var i = 0; i < 9; i++) {
        await _tapContinue(tester);
      }
      await _tap(tester, find.text('Fever'));
      await _tapContinue(tester); // confirm the complaint menu

      expect(find.textContaining('39°C or higher'), findsOneWidget);
      await _tapContinue(tester); // probes done

      await _tap(tester, find.text('No, that is all'));
      expect(find.text('Sepsis screening questions'), findsOneWidget);
      expect(find.byKey(const ValueKey('sepsis-F1')), findsOneWidget);
    });

    testWidgets('sepsis F1+F2 Yes answers reach the engine (qSOFA 1 → P2)',
        (tester) async {
      await _selectAge(tester, 'Adult');
      for (var i = 0; i < 9; i++) {
        await _tapContinue(tester);
      }
      await _tap(tester, find.text('Fever'));
      await _tapContinue(tester); // confirm the complaint menu
      await _tapContinue(tester); // probes done
      await _tap(tester, find.text('No, that is all'));

      Finder segYes(String field) => find.descendant(
            of: find.byKey(ValueKey('sepsis-$field')),
            matching: find.text('Yes'),
          );
      await _tap(tester, segYes('F1'));
      await _tap(tester, segYes('F2'));

      await _tapContinue(tester); // sepsis -> modifiers
      await _tapContinue(tester); // modifiers -> result
      expect(find.textContaining('qSOFA 1'), findsOneWidget);
      expect(find.textContaining('P2 - Very Urgent'), findsWidgets);
    });
  });

  group('GCS flow', () {
    testWidgets('AVPU alert skips GCS to land on complaint', (tester) async {
      await _selectAge(tester, 'Adult');
      for (var i = 0; i < 9; i++) {
        await _tapContinue(tester);
      }
      // At complaint; GCS not indicated because AVPU stayed Alert.
      await _tap(tester, find.text('Other problem'));
      expect(find.text('Eye opening'), findsNothing);
      // Confirm the menu, say no more complaints, advance to the result.
      await _finishComplaint(tester);
      await _tapContinue(tester);
      expect(find.textContaining('NEWS2 score'), findsOneWidget);
    });

    testWidgets('AVPU pain triggers the three GCS steps after complaint',
        (tester) async {
      await _selectAge(tester, 'Adult');
      for (var i = 0; i < 8; i++) {
        await _tapContinue(tester);
      }
      // On avpu (last vital). Select 'Pain (P)'.
      await _tap(tester, find.text('Pain (P)'));
      await _tapContinue(tester);

      // Complaint step (comes before GCS in the node order).
      await _tap(tester, find.text('Headache'));
      await _tapContinue(tester); // confirm the complaint menu

      // Now GCS eye step.
      expect(find.text('Eye opening'), findsOneWidget);
      await _tap(tester, find.text('Spontaneous'));
      await _tapContinue(tester);

      expect(find.text('Verbal response'), findsOneWidget);
      await _tap(tester, find.text('Oriented'));
      await _tapContinue(tester);

      expect(find.text('Motor response'), findsOneWidget);
      await _tap(tester, find.text('Obeys'));
      await _tapContinue(tester);

      // GCS done; Headache also has a probe branch so probes appear.
      expect(find.textContaining('suddenly, like a thunderclap'), findsOneWidget);
    });
  });

  group('Burn + modifiers flow', () {
    testWidgets('wound complaint opens the burn step and burns reach P4',
        (tester) async {
      await _selectAge(tester, 'Adult');
      for (var i = 0; i < 9; i++) {
        await _tapContinue(tester);
      }
      await _tap(tester, find.text('Wound or burn'));
      await _tapContinue(tester); // complaint menu -> any other problems
      await _tap(tester, find.text('No, that is all')); // -> burn step
      expect(find.text('Wound or burn details'), findsOneWidget);

      // Small partial burn on the arm: shade it on the body figure.
      await _tap(tester, find.bySemanticsLabel('Front: Left upper arm'));
      expect(find.text('Burned: 1.8%'), findsOneWidget);
      await _tap(tester, find.text('Partial-thickness'));
      await _tapContinue(tester); // → modifiers
      await _tapContinue(tester); // → result

      expect(find.textContaining('Burn: partial thickness'), findsOneWidget);
      expect(find.textContaining('P4'), findsOneWidget);
    });

    testWidgets('modifier adult shows only the remaining modifiers',
        (tester) async {
      await _selectAge(tester, 'Adult');
      for (var i = 0; i < 9; i++) {
        await _tapContinue(tester);
      }
      await _tap(tester, find.text('Other problem'));
      await _finishComplaint(tester);

      // Age + sex are captured on the patient info step, so the modifiers
      // step only re-asks the remaining risk factors.
      expect(find.text('Any extra risk factors?'), findsOneWidget);
      expect(find.text('Biological sex (if relevant)'), findsNothing);
      expect(find.text('Age (if known, in years)'), findsNothing);
      await _tapContinue(tester);

      expect(find.text('P5 - Minor'), findsOneWidget);
    });
  });
}