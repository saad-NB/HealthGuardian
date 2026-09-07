import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthguardian/triage/burn_profile.dart';
import 'package:healthguardian/triage/models.dart';
import 'package:healthguardian/ui/widgets/burn_body_map.dart';

void main() {
  group('BurnProfile', () {
    for (final profile in [
      BurnProfile.adult,
      BurnProfile.child10to14,
      BurnProfile.child5to9,
      BurnProfile.child1to4,
      BurnProfile.infant,
    ]) {
      test('${profile.name} weights sum to 100 across front + back', () {
        var total = 0.0;
        for (final region in BurnRegion.values) {
          total += profile.total(region);
        }
        expect(total, closeTo(100, 0.0001));
      });
    }

    test('every region has a non-zero weight on at least one side', () {
      for (final region in BurnRegion.values) {
        final total = BurnProfile.adult.total(region);
        expect(total, greaterThan(0), reason: '${region.name} weight');
      }
    });

    test('unsupported sides return zero weight', () {
      expect(
          BurnProfile.adult.weight(BodySide.front, BurnRegion.posteriorTrunk),
          0);
      expect(
          BurnProfile.adult.weight(BodySide.back, BurnRegion.anteriorTrunk), 0);
      expect(
          BurnProfile.adult.weight(BodySide.front, BurnRegion.genitals),
          closeTo(1, 0.0001));
    });

    test('forAge maps every age group to the correct profile', () {
      expect(BurnProfile.forAge(AgeGroup.neonate), BurnProfile.infant);
      expect(BurnProfile.forAge(AgeGroup.infant), BurnProfile.infant);
      expect(BurnProfile.forAge(AgeGroup.toddler), BurnProfile.child1to4);
      expect(BurnProfile.forAge(AgeGroup.preschool), BurnProfile.child1to4);
      expect(BurnProfile.forAge(AgeGroup.schoolAge), BurnProfile.child5to9);
      expect(BurnProfile.forAge(AgeGroup.preteen), BurnProfile.child10to14);
      expect(BurnProfile.forAge(AgeGroup.teenager), BurnProfile.child10to14);
      expect(BurnProfile.forAge(AgeGroup.adult), BurnProfile.adult);
      expect(BurnProfile.forAge(AgeGroup.olderAdult), BurnProfile.adult);
      expect(BurnProfile.forAge(null), BurnProfile.adult);
    });

    test('infant head is larger than adult head (Lund-Browder rule)', () {
      expect(BurnProfile.infant.total(BurnRegion.head),
          greaterThan(BurnProfile.adult.total(BurnRegion.head)));
      expect(BurnProfile.adult.total(BurnRegion.head), 9);
      expect(BurnProfile.infant.total(BurnRegion.head), 19);
    });

    test('adult leg weights: 18 total, arm 9 total', () {
      final adult = BurnProfile.adult;
      expect(adult.total(BurnRegion.rightThigh) +
              adult.total(BurnRegion.rightKnee) +
              adult.total(BurnRegion.rightLowerLeg) +
              adult.total(BurnRegion.rightFoot),
          closeTo(18, 0.0001));
      expect(
          adult.total(BurnRegion.rightUpperArm) +
              adult.total(BurnRegion.rightElbow) +
              adult.total(BurnRegion.rightForearm) +
              adult.total(BurnRegion.rightHand),
          closeTo(9, 0.0001));
    });
  });

  group('BurnAnswers.syncFromShaded', () {
    final adult = BurnProfile.adult;

    test('shading an arm region derives tbsa + critical hand area', () {
      final burn = BurnAnswers();
      burn.toggleRegion(BodySide.front, BurnRegion.rightUpperArm, adult);
      burn.toggleRegion(BodySide.front, BurnRegion.rightHand, adult);
      expect(burn.tbsaPercent, closeTo(2.8, 0.001));
      expect(burn.areas, contains(BurnArea.hand));
      expect(burn.hasCriticalArea, isTrue);
    });

    test('toggling twice unshades and clears critical areas', () {
      final burn = BurnAnswers();
      burn.toggleRegion(BodySide.front, BurnRegion.leftHand, adult);
      burn.toggleRegion(BodySide.front, BurnRegion.leftHand, adult);
      expect(burn.tbsaPercent, 0);
      expect(burn.areas, isEmpty);
    });

    test('leg area with front+back stacks to the full leg weight', () {
      final burn = BurnAnswers();
      burn.toggleRegion(BodySide.front, BurnRegion.rightThigh, adult);
      burn.toggleRegion(BodySide.back, BurnRegion.rightThigh, adult);
      expect(burn.tbsaPercent, closeTo(9.5, 0.001));
    });

    test('clearShaded resets tbsa and areas', () {
      final burn = BurnAnswers();
      burn
        ..toggleRegion(BodySide.front, BurnRegion.head, adult)
        ..toggleRegion(BodySide.back, BurnRegion.head, adult);
      burn.clearShaded(adult);
      expect(burn.tbsaPercent, 0);
      expect(burn.areas, isEmpty);
    });

    test('head derives the face critical area', () {
      final burn = BurnAnswers();
      burn.toggleRegion(BodySide.front, BurnRegion.head, adult);
      expect(burn.areas, contains(BurnArea.face));
    });

    test('tbsaPercent uses a single decimal (rule thresholds stay stable)', () {
      final burn = BurnAnswers();
      burn.toggleRegion(BodySide.front, BurnRegion.leftLowerLeg, adult);
      expect(burn.tbsaPercent, 3.3);
      expect(burn.tbsaPercent.toStringAsFixed(1), '3.3');
    });
  });

  group('BurnBodyMap widget', () {
    testWidgets('tapping a region shades it, re-tap clears', (tester) async {
      Set<(BodySide, BurnRegion)>? shaded;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: _Harness(
              onChanged: (s) => shaded = s,
            ),
          ),
        ),
      ));

      final arm = find.bySemanticsLabel('Front: Left upper arm');
      await tester.ensureVisible(arm);
      await tester.pumpAndSettle();
      await tester.tap(arm);
      await tester.pump();
      expect(shaded, contains((BodySide.front, BurnRegion.leftUpperArm)));
      expect(find.text('Burned: 1.8%'), findsOneWidget);

      await tester.tap(arm);
      await tester.pump();
      expect(shaded, isEmpty);
      expect(find.text('Burned: 0.0%'), findsOneWidget);
    });

    testWidgets('back side exposes back-only regions and hides front-only',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: _Harness(onChanged: (_) {})),
        ),
      ));

      expect(find.bySemanticsLabel('Front: Genitals'), findsOneWidget);
      expect(find.text('Burned: 0.0%'), findsOneWidget);

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Back: Back & buttocks'), findsOneWidget);
      expect(find.bySemanticsLabel('Back: Genitals'), findsNothing);
      expect(find.bySemanticsLabel('Back: Left upper arm'), findsOneWidget);
    });
  });
}

class _Harness extends StatefulWidget {
  const _Harness({required this.onChanged});

  final ValueChanged<Set<(BodySide, BurnRegion)>> onChanged;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  Set<(BodySide, BurnRegion)> _shaded = {};

  @override
  Widget build(BuildContext context) {
    return BurnBodyMap(
      profile: BurnProfile.adult,
      shaded: _shaded,
      onChanged: (s) {
        widget.onChanged(s);
        setState(() => _shaded = s);
      },
    );
  }
}