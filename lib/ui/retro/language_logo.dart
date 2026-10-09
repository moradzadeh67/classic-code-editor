import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A language logo widget that tries to load a raster asset image
/// from [assets/icons/{language}.png] first, and gracefully falls back
/// to precision vector [CustomPainter] if the asset file is not found.
class LanguageLogo extends StatelessWidget {
  final String language;
  final double size;

  const LanguageLogo({super.key, required this.language, this.size = 24});

  @override
  Widget build(BuildContext context) {
    final langKey = switch (language.toLowerCase()) {
      'dart' => 'dart',
      'py' || 'python' => 'python',
      'c' => 'c',
      'cpp' || 'c++' => 'cpp',
      _ => '',
    };

    if (langKey.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/icons/$langKey.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          final CustomPainter? painter = switch (langKey) {
            'dart' => const _DartLogoPainter(),
            'python' => const _PythonLogoPainter(),
            'c' => const _CLogoPainter(),
            'cpp' => const _CppLogoPainter(),
            _ => null,
          };
          if (painter == null) return const SizedBox.shrink();
          return CustomPaint(painter: painter);
        },
      ),
    );
  }
}

abstract class _LogoPainter extends CustomPainter {
  const _LogoPainter();

  @override
  bool shouldRepaint(covariant _LogoPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Fallback Vector Painters
// ---------------------------------------------------------------------------

class _DartLogoPainter extends _LogoPainter {
  const _DartLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);

    canvas.drawPath(
      Path()
        ..moveTo(0, 48)
        ..lineTo(32, 10)
        ..lineTo(48, 50)
        ..lineTo(22, 92)
        ..close(),
      Paint()..color = const Color(0xFF00B4AB),
    );
    canvas.drawPath(
      Path()
        ..moveTo(32, 10)
        ..lineTo(68, 0)
        ..lineTo(100, 48)
        ..lineTo(48, 50)
        ..close(),
      Paint()..color = const Color(0xFF01B5F0),
    );
    canvas.drawPath(
      Path()
        ..moveTo(48, 50)
        ..lineTo(100, 48)
        ..lineTo(76, 100)
        ..lineTo(22, 92)
        ..close(),
      Paint()..color = const Color(0xFF0175C2),
    );
    canvas.drawPath(
      Path()
        ..moveTo(48, 50)
        ..lineTo(100, 48)
        ..lineTo(76, 100)
        ..close(),
      Paint()..color = const Color(0xFF02569B),
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, 48)
        ..lineTo(32, 10)
        ..lineTo(48, 50)
        ..close(),
      Paint()..color = const Color(0xFF40C4FF),
    );

    canvas.restore();
  }
}

class _PythonLogoPainter extends _LogoPainter {
  const _PythonLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);

    const blue = Color(0xFF3776AB);
    const yellow = Color(0xFFFFD43B);

    final bluePath = Path()
      ..addRRect(RRect.fromLTRBR(8, 0, 68, 48, const Radius.circular(20)))
      ..addRRect(RRect.fromLTRBR(28, 24, 92, 48, const Radius.circular(16)));

    canvas.save();
    canvas.clipPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(100, 0)
        ..lineTo(0, 100)
        ..close(),
    );
    canvas.drawPath(bluePath, Paint()..color = blue);
    canvas.restore();

    final yellowPath = Path()
      ..addRRect(RRect.fromLTRBR(32, 52, 92, 100, const Radius.circular(20)))
      ..addRRect(RRect.fromLTRBR(8, 52, 72, 76, const Radius.circular(16)));

    canvas.save();
    canvas.clipPath(
      Path()
        ..moveTo(100, 100)
        ..lineTo(100, 0)
        ..lineTo(0, 100)
        ..close(),
    );
    canvas.drawPath(yellowPath, Paint()..color = yellow);
    canvas.restore();

    canvas.drawCircle(const Offset(28, 14), 5.5, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(72, 86), 5.5, Paint()..color = Colors.white);

    canvas.restore();
  }
}

class _CLogoPainter extends _LogoPainter {
  const _CLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    _drawIsoHexagon(canvas, withPlusPlus: false);
    canvas.restore();
  }
}

class _CppLogoPainter extends _LogoPainter {
  const _CppLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    _drawIsoHexagon(canvas, withPlusPlus: true);
    canvas.restore();
  }
}

void _drawIsoHexagon(Canvas canvas, {required bool withPlusPlus}) {
  const isoBlue = Color(0xFF00599C);
  const lightBlue = Color(0xFF659AD2);
  const darkBlue = Color(0xFF004482);

  final hexPath = _hexagon(50, 50, 48, -math.pi / 6);
  canvas.drawPath(hexPath, Paint()..color = isoBlue);

  final topLeftFacet = Path()
    ..moveTo(50, 2)
    ..lineTo(8.5, 26)
    ..lineTo(8.5, 74)
    ..lineTo(50, 50)
    ..close();
  canvas.drawPath(topLeftFacet, Paint()..color = lightBlue);

  final bottomFacet = Path()
    ..moveTo(50, 98)
    ..lineTo(91.5, 74)
    ..lineTo(91.5, 26)
    ..lineTo(50, 50)
    ..close();
  canvas.drawPath(bottomFacet, Paint()..color = darkBlue);

  final cRing = Path()
    ..addOval(Rect.fromCircle(center: const Offset(46, 50), radius: 32))
    ..addOval(Rect.fromCircle(center: const Offset(46, 50), radius: 18));
  cRing.fillType = PathFillType.evenOdd;
  canvas.drawPath(cRing, Paint()..color = Colors.white);

  final wedge = Path()
    ..moveTo(91.5, 26)
    ..lineTo(38, 50)
    ..lineTo(91.5, 74)
    ..close();
  canvas.drawPath(wedge, Paint()..color = darkBlue);

  if (withPlusPlus) {
    _drawPlus(canvas, const Offset(66, 48), 6);
    _drawPlus(canvas, const Offset(82, 50), 6);
  }
}

Path _hexagon(double x, double y, double radius, double rotation) {
  final path = Path();
  for (int i = 0; i < 6; i++) {
    final angle = (math.pi / 3) * i + rotation;
    final px = x + radius * math.cos(angle);
    final py = y + radius * math.sin(angle);
    if (i == 0) {
      path.moveTo(px, py);
    } else {
      path.lineTo(px, py);
    }
  }
  path.close();
  return path;
}

void _drawPlus(Canvas canvas, Offset center, double radius) {
  final paint = Paint()
    ..color = Colors.white
    ..strokeWidth = 3.5
    ..strokeCap = StrokeCap.square;

  canvas.drawLine(
    Offset(center.dx - radius, center.dy),
    Offset(center.dx + radius, center.dy),
    paint,
  );
  canvas.drawLine(
    Offset(center.dx, center.dy - radius),
    Offset(center.dx, center.dy + radius),
    paint,
  );
}
