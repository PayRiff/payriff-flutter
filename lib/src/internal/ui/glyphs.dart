import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Icons drawn by the SDK itself, so it needs neither the Material Icons nor
/// the Cupertino Icons font from the host app.
enum Glyph {
  /// ✕ for the close button.
  close,

  /// ! for errors.
  exclamation,

  /// A padlock outline with a keyhole dot, before the payment view's
  /// secure line.
  lock,
}

/// Paints a [Glyph] in [color].
class GlyphIcon extends StatelessWidget {
  /// Creates a glyph of [size] logical pixels.
  const GlyphIcon(this.glyph, {super.key, required this.color, this.size = 24});

  /// What to draw.
  final Glyph glyph;

  /// The stroke and fill color.
  final Color color;

  /// The width and height.
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: _GlyphPainter(glyph, color),
    ),
  );
}

/// A tinted circle with a [Glyph], used on the page-load error.
class GlyphBadge extends StatelessWidget {
  /// Creates a badge.
  const GlyphBadge(this.glyph, {super.key, required this.color});

  /// What to draw.
  final Glyph glyph;

  /// The tint.
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 72,
    height: 72,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      shape: BoxShape.circle,
    ),
    alignment: Alignment.center,
    child: GlyphIcon(glyph, color: color, size: 40),
  );
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph, this.color);

  final Glyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.shortestSide;
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(1.5, s * 0.1);
    final Paint fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    Offset p(double x, double y) => Offset(x * s, y * s);

    switch (glyph) {
      case Glyph.close:
        canvas
          ..drawLine(p(0.3, 0.3), p(0.7, 0.7), stroke)
          ..drawLine(p(0.7, 0.3), p(0.3, 0.7), stroke);
      case Glyph.exclamation:
        canvas
          ..drawLine(p(0.5, 0.2), p(0.5, 0.58), stroke)
          ..drawCircle(p(0.5, 0.78), s * 0.065, fill);
      case Glyph.lock:
        // Drawn for small sizes (15), so a thinner line than the others.
        stroke.strokeWidth = s * 0.085;
        final Path shackle = Path()
          ..moveTo(0.32 * s, 0.45 * s)
          ..lineTo(0.32 * s, 0.31 * s)
          ..addArc(
            Rect.fromCircle(center: p(0.5, 0.31), radius: 0.18 * s),
            math.pi,
            math.pi,
          )
          ..lineTo(0.68 * s, 0.45 * s);
        canvas
          ..drawPath(shackle, stroke)
          ..drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTRB(0.17 * s, 0.45 * s, 0.83 * s, 0.92 * s),
              Radius.circular(0.13 * s),
            ),
            stroke,
          )
          ..drawCircle(p(0.5, 0.665), s * 0.075, fill);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}
