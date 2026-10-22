import 'package:flutter/widgets.dart';

import 'card_types.dart';

/// The card brand's mark on a white badge, or a neutral card
/// outline while the brand is unknown (CONTRACT §16.4).
class CardBrandMark extends StatelessWidget {
  /// Creates the mark for [brand]; [outline] colours the unknown state.
  const CardBrandMark({super.key, required this.brand, required this.outline});

  /// The detected brand, or `null`.
  final PayriffCardBrand? brand;

  /// The colour of the neutral outline.
  final Color outline;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 36,
    height: 24,
    child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: switch (brand) {
        PayriffCardBrand.visa => const _Badge(
          key: ValueKey<String>('visa'),
          painter: _VisaPainter(),
        ),
        PayriffCardBrand.mastercard => const _Badge(
          key: ValueKey<String>('mastercard'),
          painter: _MastercardPainter(),
        ),
        null => CustomPaint(
          key: const ValueKey<String>('unknown'),
          size: const Size(36, 24),
          painter: _OutlinePainter(outline),
        ),
      },
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({super.key, required this.painter});

  final CustomPainter painter;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFFFFFFF),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: const Color(0xFFD1D1D6)),
    ),
    child: CustomPaint(size: const Size(36, 24), painter: painter),
  );
}

/// The Visa wordmark (Simple Icons, CC0) in a 24-unit box, absolute
/// M/L/C/Z commands only.
const String _visaPathData =
    'M9.112 8.262 L5.97 15.758 L3.92 15.758 L2.374 9.775 C2.28 9.407 2.199 '
    '9.272 1.913 9.117 C1.447 8.864 0.677 8.627 0 8.479 L0.046 8.262 L3.346 '
    '8.262 C3.792 8.262 4.171 8.586 4.24 9.026 L5.057 13.364 L7.075 8.262 Z '
    'M17.145 13.311 C17.153 11.332 14.409 11.223 14.428 10.339 C14.434 10.07 '
    '14.69 9.784 15.25 9.711 C15.906 9.649 16.567 9.765 17.163 10.047 L17.503 '
    '8.457 C16.923 8.239 16.309 8.126 15.689 8.124 C13.772 8.124 12.423 9.144 '
    '12.411 10.603 C12.399 11.682 13.374 12.283 14.109 12.643 C14.865 13.01 '
    '15.119 13.246 15.115 13.574 C15.11 14.078 14.513 14.299 13.955 14.308 '
    'C12.98 14.323 12.415 14.045 11.963 13.835 L11.612 15.477 C12.065 15.685 '
    '12.901 15.867 13.768 15.875 C15.805 15.875 17.138 14.869 17.145 13.311 '
    'M22.206 15.758 L24 15.758 L22.435 8.262 L20.779 8.262 C20.417 8.259 '
    '20.09 8.477 19.953 8.812 L17.044 15.758 L19.08 15.758 L19.485 14.638 '
    'L21.973 14.638 Z M20.043 13.102 L21.063 10.287 L21.651 13.102 Z '
    'M11.883 8.262 L10.28 15.758 L8.34 15.758 L9.945 8.262 Z';

/// Builds a [Path] from absolute M/L/C/Z path data.
Path _parsePath(String data) {
  final Path path = Path();
  final List<String> t = data
      .replaceAllMapped(RegExp('[MLCZ]'), (Match m) => ' ${m[0]} ')
      .trim()
      .split(RegExp(r'\s+'));
  double n(int i) => double.parse(t[i]);
  for (int i = 0; i < t.length;) {
    switch (t[i]) {
      case 'M':
        path.moveTo(n(i + 1), n(i + 2));
        i += 3;
      case 'L':
        path.lineTo(n(i + 1), n(i + 2));
        i += 3;
      case 'C':
        path.cubicTo(
          n(i + 1),
          n(i + 2),
          n(i + 3),
          n(i + 4),
          n(i + 5),
          n(i + 6),
        );
        i += 7;
      case 'Z':
        path.close();
        i += 1;
      default:
        throw FormatException('Unexpected path token', t[i]);
    }
  }
  return path;
}

final Path _visaPath = _parsePath(_visaPathData);

/// The width of a mark inside the 36×24 badge.
const double _markWidth = 26;

class _VisaPainter extends CustomPainter {
  const _VisaPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // The wordmark spans x 0…24 and y 8.124…15.875 of its 24-unit box.
    const double scale = _markWidth / 24;
    const double height = (15.875 - 8.124) * scale;
    canvas
      ..save()
      ..translate(
        (size.width - _markWidth) / 2,
        (size.height - height) / 2 - 8.124 * scale,
      )
      ..scale(scale)
      ..drawPath(_visaPath, Paint()..color = const Color(0xFF1A1F71))
      ..restore();
  }

  @override
  bool shouldRepaint(_VisaPainter oldDelegate) => false;
}

class _MastercardPainter extends CustomPainter {
  const _MastercardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const double r = 0.309 * _markWidth;
    final double left = (size.width - _markWidth) / 2;
    final double y = size.height / 2;
    final Path red = Path()
      ..addOval(Rect.fromCircle(center: Offset(left + r, y), radius: r));
    final Path yellow = Path()
      ..addOval(
        Rect.fromCircle(center: Offset(left + _markWidth - r, y), radius: r),
      );
    canvas
      ..drawPath(red, Paint()..color = const Color(0xFFEB001B))
      ..drawPath(yellow, Paint()..color = const Color(0xFFF79E1B))
      ..drawPath(
        Path.combine(PathOperation.intersect, red, yellow),
        Paint()..color = const Color(0xFFFF5F00),
      );
  }

  @override
  bool shouldRepaint(_MastercardPainter oldDelegate) => false;
}

class _OutlinePainter extends CustomPainter {
  const _OutlinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final Rect card = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: 30,
      height: 20,
    );
    canvas
      ..drawRRect(RRect.fromRectAndRadius(card, const Radius.circular(4)), line)
      ..drawLine(
        Offset(card.left, card.top + 6),
        Offset(card.right, card.top + 6),
        line..strokeWidth = 3,
      );
  }

  @override
  bool shouldRepaint(_OutlinePainter oldDelegate) => oldDelegate.color != color;
}
