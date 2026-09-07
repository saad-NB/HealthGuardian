import 'package:flutter/material.dart';

import '../../triage/burn_profile.dart';

/// A single drawable body part: keep the geometry data-driven so the painter
/// and the tap-target overlay stay in lockstep.
class _BodyPart {
  const _BodyPart(this.region, this.kind, this.rect, this.radius);

  final BurnRegion region;
  final int kind; // 0 = oval, 1 = rounded rect
  final Rect rect;
  final double radius;

  Rect get mirrorX => Rect.fromLTRB(
        100 - rect.right,
        rect.top,
        100 - rect.left,
        rect.bottom,
      );
}

const _head = _BodyPart(
    BurnRegion.head, 0, Rect.fromLTRB(38, 1, 62, 27), 0);

const _torsoFront = _BodyPart(
    BurnRegion.anteriorTrunk, 1, Rect.fromLTRB(30, 24, 70, 58), 8);
const _torsoBack = _BodyPart(
    BurnRegion.posteriorTrunk, 1, Rect.fromLTRB(30, 24, 70, 62), 8);

const _genitals = _BodyPart(
    BurnRegion.genitals, 0, Rect.fromLTRB(45, 57, 55, 63), 0);

const _rightUpperArm = _BodyPart(
    BurnRegion.rightUpperArm, 1, Rect.fromLTRB(66, 22, 84, 36), 5);
const _rightElbow = _BodyPart(BurnRegion.rightElbow, 0,
    Rect.fromLTRB(80.5, 34.5, 87.5, 41.5), 0);
const _rightForearm = _BodyPart(
    BurnRegion.rightForearm, 1, Rect.fromLTRB(80, 40, 90, 56), 4);
const _rightHand = _BodyPart(BurnRegion.rightHand, 0,
    Rect.fromLTRB(87.5, 54.5, 96.5, 65.5), 0);

const _rightThigh = _BodyPart(
    BurnRegion.rightThigh, 1, Rect.fromLTRB(54, 56, 68, 88), 7);
const _rightKnee = _BodyPart(BurnRegion.rightKnee, 0,
    Rect.fromLTRB(64, 86, 72, 94), 0);
const _rightLowerLeg = _BodyPart(
    BurnRegion.rightLowerLeg, 1, Rect.fromLTRB(62, 92, 70, 110), 4);
const _rightFoot = _BodyPart(BurnRegion.rightFoot, 0,
    Rect.fromLTRB(64.5, 110.5, 75.5, 117.5), 0);

/// Normalised (100x150) list of drawable body parts for one side. The four
/// limb definitions come directly from the constants above, mirroring the
/// right-side shapes across the vertical axis for the left arm/leg.
List<_BodyPart> _partsFor(BodySide side) {
  final rightLimbs = const [
    _rightUpperArm,
    _rightElbow,
    _rightForearm,
    _rightHand,
    _rightThigh,
    _rightKnee,
    _rightLowerLeg,
    _rightFoot,
  ];
  final leftLimbs = rightLimbs.map((p) => _BodyPart(
        _mirrorRegion(p.region),
        p.kind,
        p.mirrorX,
        p.radius,
      ));
  return switch (side) {
    BodySide.front => [
        _head,
        _genitals,
        _torsoFront,
        ...leftLimbs,
        ...rightLimbs,
      ],
    BodySide.back => [
        _head,
        _torsoBack,
        ...leftLimbs,
        ...rightLimbs,
      ],
  };
}

/// Mirrors a right-side region id to its left counterpart.
BurnRegion _mirrorRegion(BurnRegion r) => switch (r) {
      BurnRegion.rightUpperArm => BurnRegion.leftUpperArm,
      BurnRegion.rightElbow => BurnRegion.leftElbow,
      BurnRegion.rightForearm => BurnRegion.leftForearm,
      BurnRegion.rightHand => BurnRegion.leftHand,
      BurnRegion.rightThigh => BurnRegion.leftThigh,
      BurnRegion.rightKnee => BurnRegion.leftKnee,
      BurnRegion.rightLowerLeg => BurnRegion.leftLowerLeg,
      BurnRegion.rightFoot => BurnRegion.leftFoot,
      _ => r,
    };

class _BodyMapPainter extends CustomPainter {
  _BodyMapPainter({required this.side, required this.shaded});

  final BodySide side;
  final Set<BurnRegion> shaded;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 150);
    final body = Paint()..color = const Color(0xFFF5E9DA);
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0xFF90A4AE);
    final filled = Paint()..color = const Color(0xFFD32F2F);
    final filledOutline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = const Color(0xFF8E1B1B);

    for (final part in _partsFor(side)) {
      _drawPart(canvas, part, body, outline, const Color(0xFFC9AE8E));
    }
    for (final part in _partsFor(side)) {
      if (!shaded.contains(part.region)) continue;
      _drawPart(canvas, part, filled, filledOutline, const Color(0xFF8E1B1B));
    }
  }

  void _drawPart(
    Canvas canvas,
    _BodyPart part,
    Paint fill,
    Paint stroke,
    Color strokeColor,
  ) {
    if (part.kind == 0) {
      canvas.drawOval(part.rect, fill);
      canvas.drawOval(part.rect, stroke..color = strokeColor);
    } else {
      final rrect = RRect.fromRectAndRadius(part.rect, Radius.circular(part.radius));
      canvas.drawRRect(rrect, fill);
      canvas.drawRRect(rrect, stroke..color = strokeColor);
    }
  }

  @override
  bool shouldRepaint(_BodyMapPainter old) =>
      old.side != side || old.shaded != shaded;
}

/// Tap-to-fill front/back body figure (spec Â§11 H3/H4 replacement).
///
/// The figure is a simple vector silhouette with shaded regions drawn in red
/// and each region exposed as an accessible, tappable overlay so the
/// walkthrough and the on-device E2E harness can drive it by label.
class BurnBodyMap extends StatefulWidget {
  const BurnBodyMap({
    super.key,
    required this.profile,
    required this.shaded,
    required this.onChanged,
  });

  final BurnProfile profile;
  final Set<(BodySide, BurnRegion)> shaded;
  final ValueChanged<Set<(BodySide, BurnRegion)>> onChanged;

  @override
  State<BurnBodyMap> createState() => _BurnBodyMapState();
}

class _BurnBodyMapState extends State<BurnBodyMap> {
  BodySide _side = BodySide.front;

  double get _percent {
    var tbsa = 0.0;
    for (final (side, region) in widget.shaded) {
      tbsa += widget.profile.weight(side, region);
    }
    return double.parse(tbsa.toStringAsFixed(1));
  }

  void _toggle(BodySide side, BurnRegion region) {
    final next = Set<(BodySide, BurnRegion)>.from(widget.shaded);
    if (!next.remove((side, region))) next.add((side, region));
    widget.onChanged(next);
  }

  void _clear() => widget.onChanged({});

  @override
  Widget build(BuildContext context) {
    final shadedHere =
        widget.shaded.where((e) => e.$1 == _side).map((e) => e.$2).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            SegmentedButton<BodySide>(
              segments: [
                for (final s in BodySide.values)
                  ButtonSegment(value: s, label: Text(s.label)),
              ],
              selected: {_side},
              onSelectionChanged: (sel) => setState(() => _side = sel.first),
            ),
            const Spacer(),
            Text(
              'Burned: ${_percent.toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 100 / 150,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scale = constraints.maxWidth / 100;
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    CustomPaint(
                      size: Size.infinite,
                      painter: _BodyMapPainter(side: _side, shaded: shadedHere),
                    ),
                    for (final part in _partsFor(_side))
                      Positioned(
                        left: part.rect.left * scale,
                        top: part.rect.top * scale,
                        width: part.rect.width * scale,
                        height: part.rect.height * scale,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _toggle(_side, part.region),
                          child: Semantics(
                            label: '${_side.label}: ${part.region.label}',
                            button: true,
                            child: const ColoredBox(color: Colors.transparent),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton.icon(
              onPressed: _clear,
              icon: const Icon(Icons.palette_outlined, size: 18),
              label: const Text('Clear'),
            ),
            const Spacer(),
            Text(
              'The patient\u2019s palm \u2248 1% of the body',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}