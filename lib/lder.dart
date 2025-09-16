import 'dart:math' as rnd;

import 'package:flutter/material.dart';

/// ==================
/// Неоновый круговой лоадер
/// ==================
class NeonDialLoader extends StatefulWidget {
  const NeonDialLoader({super.key});

  @override
  State<NeonDialLoader> createState() => _NeonDialLoaderState();
}

class _NeonDialLoaderState extends State<NeonDialLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController spinCtrl;

  @override
  void initState() {
    super.initState();
    spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    spinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const neonColor = Color(0xFF00FFFF);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: AnimatedBuilder(
          animation: spinCtrl,
          builder: (context, _) {
            final angle = spinCtrl.value * 2 * rnd.pi;
            return CustomPaint(
              painter: _NeonDialPainter(angle, neonColor),
              size: const Size(160, 160),
            );
          },
        ),
      ),
    );
  }
}

class _NeonDialPainter extends CustomPainter {
  final double angle;
  final Color neonColor;
  _NeonDialPainter(this.angle, this.neonColor);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w / 2 - 8;

    // фон
    canvas.drawRect(
        Offset.zero & size, Paint()..color = Colors.transparent);

    // неоновый круг
    final circlePaint = Paint()
      ..color = neonColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(center, radius, circlePaint);

    // стрелка
    final needleLen = radius - 12;
    final needlePaint = Paint()
      ..color = neonColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final end = Offset(center.dx + needleLen * rnd.cos(angle),
        center.dy + needleLen * rnd.sin(angle));
    canvas.drawLine(center, end, needlePaint);

    // центральная белая точка
    canvas.drawCircle(center, 6,
        Paint()..color = Colors.white..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
  }

  @override
  bool shouldRepaint(covariant _NeonDialPainter old) =>
      old.angle != angle || old.neonColor != neonColor;
}