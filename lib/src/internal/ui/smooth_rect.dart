/// CONTRACT §18.2 (`vectors/corner_smoothing.json`): Figma's corner
/// smoothing, as in the MIT `figma-squircle` algorithm with
/// `preserveSmoothing` false, for the rounded rectangles the SDK draws: the
/// card form's fields and card box, the brand mark box, the Pay button and
/// the card badges. With smoothing 0 the shape is the circular-arc rounded
/// rectangle, and the widgets keep the plain [BoxDecoration] and [ClipRRect]
/// they had before revision 8.
library;

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

/// [smoothing] clamped to 0…1; NaN counts as 0.
double clampSmoothing(double smoothing) =>
    smoothing.isNaN ? 0 : smoothing.clamp(0.0, 1.0);

double _radians(double degrees) => degrees * math.pi / 180;

/// The shape of one corner of a smooth rectangle (`corner_smoothing.json` →
/// `expect`). All four corners of a rectangle share it.
@immutable
final class SmoothCorner {
  const SmoothCorner._({
    required this.radius,
    required this.smoothing,
    required this.p,
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.arcSectionLength,
    required this.arcMeasure,
  });

  /// The corner of a [width] × [height] rectangle with [radius] and
  /// [smoothing] (clamped to 0…1). The radius is limited to half the shorter
  /// side, and the smoothing to the room the sides leave.
  factory SmoothCorner.of({
    required double width,
    required double height,
    required double radius,
    required double smoothing,
  }) {
    final double budget = math.max(0, math.min(width, height) / 2);
    final double r = radius.isNaN ? 0 : radius.clamp(0.0, budget);
    double s = clampSmoothing(smoothing);
    if (r == 0) {
      // A square corner.
      return SmoothCorner._(
        radius: 0,
        smoothing: s,
        p: 0,
        a: 0,
        b: 0,
        c: 0,
        d: 0,
        arcSectionLength: 0,
        arcMeasure: 90,
      );
    }
    double p = (1 + s) * r;
    s = math.min(s, budget / r - 1);
    p = math.min(p, budget);
    final double arcMeasure = 90 * (1 - s);
    final double arcSectionLength =
        math.sin(_radians(arcMeasure / 2)) * r * math.sqrt2;
    final double alpha = (90 - arcMeasure) / 2;
    final double p3ToP4 = r * math.tan(_radians(alpha / 2));
    final double beta = 45 * s;
    final double c = p3ToP4 * math.cos(_radians(beta));
    final double d = c * math.tan(_radians(beta));
    final double b = (p - arcSectionLength - c - d) / 3;
    return SmoothCorner._(
      radius: r,
      smoothing: s,
      p: p,
      a: 2 * b,
      b: b,
      c: c,
      d: d,
      arcSectionLength: arcSectionLength,
      arcMeasure: arcMeasure,
    );
  }

  /// The radius of the corner's arc.
  final double radius;

  /// The smoothing that fits.
  final double smoothing;

  /// How far from the corner, along each side, the curve starts.
  final double p;

  /// The cubic's parameters, as in `figma-squircle`.
  final double a, b, c, d;

  /// The width and height of the arc's chord.
  final double arcSectionLength;

  /// The angle the arc spans, in degrees.
  final double arcMeasure;
}

/// One corner of a smooth rectangle in screen coordinates (y down, angles
/// in degrees from +x, clockwise): from [start] on one side, a cubic by
/// [cubic1], the arc of [radius] around [center] from [startAngle] to
/// [endAngle], and a cubic by [cubic2] that ends on the next side.
typedef SmoothCornerPath = ({
  Offset start,
  List<Offset> cubic1,
  Offset center,
  double radius,
  double startAngle,
  double endAngle,
  List<Offset> cubic2,
});

/// Corner [index] of [rect] (0 top-right, 1 bottom-right, 2 bottom-left, 3
/// top-left, clockwise) with the shape [corner]: the top-right corner
/// turned by `90° × index`.
SmoothCornerPath smoothCornerPath(Rect rect, SmoothCorner corner, int index) {
  // The direction along the side the corner starts on, and towards the
  // next side.
  final (Offset u, Offset v, Offset point) = switch (index) {
    0 => (const Offset(1, 0), const Offset(0, 1), rect.topRight),
    1 => (const Offset(0, 1), const Offset(-1, 0), rect.bottomRight),
    2 => (const Offset(-1, 0), const Offset(0, -1), rect.bottomLeft),
    _ => (const Offset(0, -1), const Offset(1, 0), rect.topLeft),
  };
  final SmoothCorner k = corner;
  final Offset start = point - u * k.p;
  final Offset arcStart = start + u * (k.a + k.b + k.c) + v * k.d;
  final Offset arcEnd = arcStart + (u + v) * k.arcSectionLength;
  final double startAngle = -90 + (90 - k.arcMeasure) / 2 + 90.0 * index;
  return (
    start: start,
    cubic1: <Offset>[start + u * k.a, start + u * (k.a + k.b), arcStart],
    center: point - u * k.radius + v * k.radius,
    radius: k.radius,
    startAngle: startAngle,
    endAngle: startAngle + k.arcMeasure,
    cubic2: <Offset>[
      arcEnd + u * k.d + v * k.c,
      arcEnd + u * k.d + v * (k.b + k.c),
      arcEnd + u * k.d + v * (k.a + k.b + k.c),
    ],
  );
}

/// The outline of [rect] with smooth corners of [radius] and [smoothing].
/// Smoothing 0 gives the circular-arc rounded rectangle, radius 0 the
/// rectangle.
Path smoothRectPath(Rect rect, double radius, double smoothing) {
  final SmoothCorner corner = SmoothCorner.of(
    width: rect.width,
    height: rect.height,
    radius: radius,
    smoothing: smoothing,
  );
  if (corner.radius == 0) return Path()..addRect(rect);
  final Path path = Path();
  for (int i = 0; i < 4; i++) {
    final SmoothCornerPath c = smoothCornerPath(rect, corner, i);
    if (i == 0) {
      path.moveTo(c.start.dx, c.start.dy);
    } else {
      path.lineTo(c.start.dx, c.start.dy);
    }
    path
      ..cubicTo(
        c.cubic1[0].dx,
        c.cubic1[0].dy,
        c.cubic1[1].dx,
        c.cubic1[1].dy,
        c.cubic1[2].dx,
        c.cubic1[2].dy,
      )
      ..arcTo(
        Rect.fromCircle(center: c.center, radius: c.radius),
        _radians(c.startAngle),
        _radians(c.endAngle - c.startAngle),
        false,
      )
      ..cubicTo(
        c.cubic2[0].dx,
        c.cubic2[0].dy,
        c.cubic2[1].dx,
        c.cubic2[1].dy,
        c.cubic2[2].dx,
        c.cubic2[2].dy,
      );
  }
  return path..close();
}

/// A rectangle with smooth corners (CONTRACT §18.2): every corner has
/// [radius] and [smoothing]. The fill and clipping use the outline; the
/// [side] is stroked along the same shape inset by half its width, with the
/// radius less half the width, so it stays inside the bounds.
class SmoothRectangleBorder extends OutlinedBorder {
  /// Creates the border.
  const SmoothRectangleBorder({
    super.side,
    this.radius = 0,
    this.smoothing = 0,
  });

  /// The radius of the corners.
  final double radius;

  /// The corner smoothing, 0…1.
  final double smoothing;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.strokeInset);

  @override
  SmoothRectangleBorder scale(double t) => SmoothRectangleBorder(
    side: side.scale(t),
    radius: radius * t,
    smoothing: smoothing,
  );

  @override
  SmoothRectangleBorder copyWith({
    BorderSide? side,
    double? radius,
    double? smoothing,
  }) => SmoothRectangleBorder(
    side: side ?? this.side,
    radius: radius ?? this.radius,
    smoothing: smoothing ?? this.smoothing,
  );

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is SmoothRectangleBorder) {
      return SmoothRectangleBorder(
        side: BorderSide.lerp(a.side, side, t),
        radius: lerpDouble(a.radius, radius, t)!,
        smoothing: lerpDouble(a.smoothing, smoothing, t)!,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is SmoothRectangleBorder) {
      return SmoothRectangleBorder(
        side: BorderSide.lerp(side, b.side, t),
        radius: lerpDouble(radius, b.radius, t)!,
        smoothing: lerpDouble(smoothing, b.smoothing, t)!,
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      smoothRectPath(rect, radius, smoothing);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    final double inset = side.strokeInset;
    return smoothRectPath(
      rect.deflate(inset),
      math.max(0, radius - inset),
      smoothing,
    );
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    final double half = side.width / 2;
    canvas.drawPath(
      smoothRectPath(rect.deflate(half), math.max(0, radius - half), smoothing),
      side.toPaint(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SmoothRectangleBorder &&
      other.side == side &&
      other.radius == radius &&
      other.smoothing == smoothing;

  @override
  int get hashCode => Object.hash(side, radius, smoothing);

  @override
  String toString() =>
      'SmoothRectangleBorder($side, radius: $radius, smoothing: $smoothing)';
}

/// The decoration of a rounded rectangle the SDK draws (CONTRACT §18.2): a
/// [BoxDecoration] with circular corners while [smoothing] is 0, exactly as
/// before revision 8; otherwise a [ShapeDecoration] with a
/// [SmoothRectangleBorder].
Decoration roundedRectDecoration({
  Color? color,
  BorderSide side = BorderSide.none,
  required double radius,
  required double smoothing,
}) {
  if (clampSmoothing(smoothing) == 0) {
    return BoxDecoration(
      color: color,
      border: side == BorderSide.none ? null : Border.fromBorderSide(side),
      borderRadius: BorderRadius.circular(radius),
    );
  }
  return ShapeDecoration(
    color: color,
    shape: SmoothRectangleBorder(
      side: side,
      radius: radius,
      smoothing: smoothing,
    ),
  );
}

/// Clips [child] to a rounded rectangle of [radius]: a [ClipRRect] while
/// [smoothing] is 0, as before revision 8; otherwise the smooth outline.
Widget clipRoundedRect({
  required double radius,
  required double smoothing,
  required Widget child,
}) => clampSmoothing(smoothing) == 0
    ? ClipRRect(borderRadius: BorderRadius.circular(radius), child: child)
    : ClipPath(
        clipper: ShapeBorderClipper(
          shape: SmoothRectangleBorder(radius: radius, smoothing: smoothing),
        ),
        child: child,
      );
