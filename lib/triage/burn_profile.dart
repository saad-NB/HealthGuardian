import 'models.dart';

/// Body side of the shading figure.
enum BodySide {
  front,
  back;

  String get label => this == front ? 'Front' : 'Back';
}

/// Body regions of the tap-to-shade figure. Each region maps to a
/// [BurnArea] (for the engine's critical-area rules) and carries a
/// Lund-Browder-style percentage weight per age profile (see [BurnProfile]).
enum BurnRegion {
  head(label: 'Head', area: BurnArea.face),
  anteriorTrunk(label: 'Chest & abdomen'),
  posteriorTrunk(label: 'Back & buttocks'),
  genitals(label: 'Genitals', area: BurnArea.genitals),
  rightUpperArm(label: 'Right upper arm'),
  leftUpperArm(label: 'Left upper arm'),
  rightElbow(label: 'Right elbow', area: BurnArea.joint),
  leftElbow(label: 'Left elbow', area: BurnArea.joint),
  rightForearm(label: 'Right forearm'),
  leftForearm(label: 'Left forearm'),
  rightHand(label: 'Right hand', area: BurnArea.hand),
  leftHand(label: 'Left hand', area: BurnArea.hand),
  rightThigh(label: 'Right thigh'),
  leftThigh(label: 'Left thigh'),
  rightKnee(label: 'Right knee', area: BurnArea.joint),
  leftKnee(label: 'Left knee', area: BurnArea.joint),
  rightLowerLeg(label: 'Right lower leg'),
  leftLowerLeg(label: 'Left lower leg'),
  rightFoot(label: 'Right foot', area: BurnArea.foot),
  leftFoot(label: 'Left foot', area: BurnArea.foot);

  const BurnRegion({required this.label, this.area});

  final String label;

  /// The engine's coarse critical-area bucket this region belongs to
  /// (head→face, hands, feet, genitals, elbows/knees→joint).
  final BurnArea? area;

  /// Whether this region is drawable on a given side of the figure.
  bool supports(BodySide side) => switch (this) {
        anteriorTrunk => side == BodySide.front,
        posteriorTrunk => side == BodySide.back,
        genitals => side == BodySide.front,
        _ => true,
      };

  bool get isCritical => area != null;
}

/// Lund-Browder-derived surface-area weights keyed by age profile.
///
/// Each profile's front + back weights sum to exactly 100 (% of the body),
/// so shading regions on either side always yields a valid TBSA.
class BurnProfile {
  const BurnProfile({
    required this.name,
    required this.frontWeight,
    required this.backWeight,
  });

  final String name;
  final Map<BurnRegion, double> frontWeight;
  final Map<BurnRegion, double> backWeight;

  double weight(BodySide side, BurnRegion region) => switch (side) {
        BodySide.front => frontWeight[region] ?? 0,
        BodySide.back => backWeight[region] ?? 0,
      };

  double total(BurnRegion region) =>
      (frontWeight[region] ?? 0) + (backWeight[region] ?? 0);

  static const Map<BurnRegion, double> _armLimbFront = {
    BurnRegion.rightUpperArm: 1.75,
    BurnRegion.leftUpperArm: 1.75,
    BurnRegion.rightElbow: 0.25,
    BurnRegion.leftElbow: 0.25,
    BurnRegion.rightForearm: 1.5,
    BurnRegion.leftForearm: 1.5,
    BurnRegion.rightHand: 1.0,
    BurnRegion.leftHand: 1.0,
  };
  static const Map<BurnRegion, double> _armLimbBack = {
    BurnRegion.rightUpperArm: 1.75,
    BurnRegion.leftUpperArm: 1.75,
    BurnRegion.rightElbow: 0.25,
    BurnRegion.leftElbow: 0.25,
    BurnRegion.rightForearm: 1.5,
    BurnRegion.leftForearm: 1.5,
    BurnRegion.rightHand: 1.0,
    BurnRegion.leftHand: 1.0,
  };

  static const Map<BurnRegion, double> _legsFrontAdult = {
    BurnRegion.rightThigh: 4.75,
    BurnRegion.leftThigh: 4.75,
    BurnRegion.rightKnee: 0.25,
    BurnRegion.leftKnee: 0.25,
    BurnRegion.rightLowerLeg: 3.25,
    BurnRegion.leftLowerLeg: 3.25,
    BurnRegion.rightFoot: 0.75,
    BurnRegion.leftFoot: 0.75,
  };
  static const Map<BurnRegion, double> _legsBackAdult = _legsFrontAdult;

  static const Map<BurnRegion, double> _legsFront10to14 = {
    BurnRegion.rightThigh: 4.5,
    BurnRegion.leftThigh: 4.5,
    BurnRegion.rightKnee: 0.25,
    BurnRegion.leftKnee: 0.25,
    BurnRegion.rightLowerLeg: 3.0,
    BurnRegion.leftLowerLeg: 3.0,
    BurnRegion.rightFoot: 0.75,
    BurnRegion.leftFoot: 0.75,
  };
  static const Map<BurnRegion, double> _legsBack10to14 = _legsFront10to14;

  static const Map<BurnRegion, double> _legsFront5to9 = {
    BurnRegion.rightThigh: 4.25,
    BurnRegion.leftThigh: 4.25,
    BurnRegion.rightKnee: 0.25,
    BurnRegion.leftKnee: 0.25,
    BurnRegion.rightLowerLeg: 2.75,
    BurnRegion.leftLowerLeg: 2.75,
    BurnRegion.rightFoot: 0.75,
    BurnRegion.leftFoot: 0.75,
  };
  static const Map<BurnRegion, double> _legsBack5to9 = _legsFront5to9;

  static const Map<BurnRegion, double> _legsFront1to4 = {
    BurnRegion.rightThigh: 3.5,
    BurnRegion.leftThigh: 3.5,
    BurnRegion.rightKnee: 0.25,
    BurnRegion.leftKnee: 0.25,
    BurnRegion.rightLowerLeg: 2.5,
    BurnRegion.leftLowerLeg: 2.5,
    BurnRegion.rightFoot: 0.75,
    BurnRegion.leftFoot: 0.75,
  };
  static const Map<BurnRegion, double> _legsBack1to4 = _legsFront1to4;

  static const Map<BurnRegion, double> _legsFrontInfant = {
    BurnRegion.rightThigh: 3.25,
    BurnRegion.leftThigh: 3.25,
    BurnRegion.rightKnee: 0.25,
    BurnRegion.leftKnee: 0.25,
    BurnRegion.rightLowerLeg: 2.25,
    BurnRegion.leftLowerLeg: 2.25,
    BurnRegion.rightFoot: 0.75,
    BurnRegion.leftFoot: 0.75,
  };
  static const Map<BurnRegion, double> _legsBackInfant = _legsFrontInfant;

  static const Map<BurnRegion, double> _headAdult = {
    BurnRegion.head: 4.5, // f+b = 9
  };
  static const Map<BurnRegion, double> _head10to14 = {
    BurnRegion.head: 5.5, // f+b = 11
  };
  static const Map<BurnRegion, double> _head5to9 = {
    BurnRegion.head: 6.5, // f+b = 13
  };
  static const Map<BurnRegion, double> _head1to4 = {
    BurnRegion.head: 8.5, // f+b = 17
  };
  static const Map<BurnRegion, double> _headInfant = {
    BurnRegion.head: 9.5, // f+b = 19
  };

  static const Map<BurnRegion, double> _trunkFront = {
    BurnRegion.anteriorTrunk: 18.0,
    BurnRegion.genitals: 1.0,
  };
  static const Map<BurnRegion, double> _trunkBack = {
    BurnRegion.posteriorTrunk: 18.0,
  };

  factory BurnProfile.forAge(AgeGroup? age) {
    if (age == null) return adult;
    return switch (age) {
      AgeGroup.neonate || AgeGroup.infant => infant,
      AgeGroup.toddler || AgeGroup.preschool => child1to4,
      AgeGroup.schoolAge => child5to9,
      AgeGroup.preteen || AgeGroup.teenager => child10to14,
      AgeGroup.adult || AgeGroup.olderAdult => adult,
    };
  }

  /// Adult (16+): head 9%, arms 9% each, legs 18% each, trunk 36%.
  static const BurnProfile adult = BurnProfile(
    name: 'Adult',
    frontWeight: {..._headAdult, ..._trunkFront, ..._armLimbFront, ..._legsFrontAdult},
    backWeight: {..._headAdult, ..._trunkBack, ..._armLimbBack, ..._legsBackAdult},
  );

  /// 10-14 years: head 11%, legs 17% each.
  static const BurnProfile child10to14 = BurnProfile(
    name: '10-14 years',
    frontWeight: {..._head10to14, ..._trunkFront, ..._armLimbFront, ..._legsFront10to14},
    backWeight: {..._head10to14, ..._trunkBack, ..._armLimbBack, ..._legsBack10to14},
  );

  /// 5-9 years: head 13%, legs 16% each.
  static const BurnProfile child5to9 = BurnProfile(
    name: '5-9 years',
    frontWeight: {..._head5to9, ..._trunkFront, ..._armLimbFront, ..._legsFront5to9},
    backWeight: {..._head5to9, ..._trunkBack, ..._armLimbBack, ..._legsBack5to9},
  );

  /// 1-4 years: head 17%, legs 14% each.
  static const BurnProfile child1to4 = BurnProfile(
    name: '1-4 years',
    frontWeight: {..._head1to4, ..._trunkFront, ..._armLimbFront, ..._legsFront1to4},
    backWeight: {..._head1to4, ..._trunkBack, ..._armLimbBack, ..._legsBack1to4},
  );

  /// Under 1 year: head 19%, legs 13% each.
  static const BurnProfile infant = BurnProfile(
    name: 'Under 1 year',
    frontWeight: {..._headInfant, ..._trunkFront, ..._armLimbFront, ..._legsFrontInfant},
    backWeight: {..._headInfant, ..._trunkBack, ..._armLimbBack, ..._legsBackInfant},
  );
}