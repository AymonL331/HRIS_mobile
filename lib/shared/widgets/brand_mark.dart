import 'package:flutter/material.dart';

import '../tokens.dart';

enum BrandMarkSize { bar, auth }

/// The ATLAS brand block, as the website draws it (AtlasLogo.jsx): the Meridian
/// mark, then the monoline "ATLAS" wordmark to its right. [BrandMarkSize.bar] is
/// the top-bar / drawer size; [BrandMarkSize.auth] the larger, centred version
/// the login and splash use.
///
/// Both are drawn from the guideline geometry (ATLAS Meridian Logo Guidelines),
/// not from image files, so they stay sharp at any size. The word is never set
/// in a font: the guidelines forbid typing "ATLAS" beside the mark.
class BrandMark extends StatelessWidget {
  final BrandMarkSize size;

  const BrandMark({super.key, this.size = BrandMarkSize.bar});

  /// The wordmark ink per surface (guidelines: ink on light, mist on dark).
  static const inkLight = Color(0xFF1B1F22);
  static const inkDark = Color(0xFFE7ECEC);

  @override
  Widget build(BuildContext context) {
    final auth = size == BrandMarkSize.auth;
    final mark = auth ? HrisSize.brandMarkAuth : HrisSize.brandMark;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // The wordmark's cap height is half the mark, as the web lockup.
    final wordHeight = mark * 0.5;
    return Semantics(
      label: 'ATLAS',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: auth ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          AtlasMark(size: mark),
          SizedBox(width: auth ? HrisSpace.s3 : HrisSpace.s2),
          CustomPaint(
            size: Size(wordHeight * 90 / 24, wordHeight),
            painter: _WordmarkPainter(dark ? inkDark : inkLight),
          ),
        ],
      ),
    );
  }
}

/// The Meridian mark alone: a red globe whose two meridians meet at the pole to
/// draw an A, an equator crossbar, and a pole dot. Brand red appears only here.
class AtlasMark extends StatelessWidget {
  final double size;

  const AtlasMark({super.key, required this.size});

  static const red = Color(0xFFED0C2C);

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: const _MarkPainter());
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48);
    final globe = Path()..addOval(Rect.fromCircle(center: const Offset(24, 24), radius: 22));
    canvas.drawPath(globe, Paint()..color = AtlasMark.red);
    canvas.save();
    canvas.clipPath(globe);
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(24, 17.6)
        ..cubicTo(18, 22, 14.2, 30, 12.6, 47)
        ..moveTo(24, 17.6)
        ..cubicTo(30, 22, 33.8, 30, 35.4, 47)
        ..moveTo(15, 32.4)
        ..quadraticBezierTo(24, 37, 33, 32.4),
      stroke,
    );
    canvas.restore();
    canvas.drawCircle(const Offset(24, 10.6), 3.6, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => false;
}

class _WordmarkPainter extends CustomPainter {
  final Color ink;

  const _WordmarkPainter(this.ink);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.height / 24);
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // The two A's echo the mark's meridians (viewBox 90 × 24, as the web).
    Path a(double x) => Path()
      ..moveTo(x, 3)
      ..cubicTo(x - 3, 5.5, x - 5.2, 12, x - 6.4, 21)
      ..moveTo(x, 3)
      ..cubicTo(x + 3, 5.5, x + 5.2, 12, x + 6.4, 21)
      ..moveTo(x - 5.1, 14.5)
      ..quadraticBezierTo(x, 17, x + 5.1, 14.5);
    canvas.drawPath(a(8), stroke);
    canvas.drawPath(
      Path()
        ..moveTo(22.4, 3)
        ..lineTo(35.4, 3)
        ..moveTo(28.9, 3)
        ..lineTo(28.9, 21),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(41.4, 3)
        ..lineTo(41.4, 21)
        ..lineTo(51.9, 21),
      stroke,
    );
    canvas.drawPath(a(62.3), stroke);
    canvas.drawPath(
      Path()
        ..moveTo(88.1, 6)
        ..cubicTo(87.1, 3.9, 85.1, 3, 82.6, 3)
        ..cubicTo(79.5, 3, 77.3, 4.7, 77.3, 7.4)
        ..cubicTo(77.3, 13.2, 88.5, 10.6, 88.5, 16.4)
        ..cubicTo(88.5, 19.3, 86.1, 21, 82.6, 21)
        ..cubicTo(79.7, 21, 77.6, 19.9, 76.7, 17.6),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_WordmarkPainter oldDelegate) => oldDelegate.ink != ink;
}
