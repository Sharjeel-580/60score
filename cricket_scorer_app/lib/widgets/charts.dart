// Simple charts drawn with CustomPainter — no chart package needed.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../scoring.dart';

/// Runs comparison (worm): cumulative runs per over for two innings.
class WormChart extends StatelessWidget {
  final List<int> innings1;
  final List<int> innings2;
  final String label1;
  final String label2;
  const WormChart({
    super.key,
    required this.innings1,
    required this.innings2,
    required this.label1,
    required this.label2,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.show_chart, size: 14, color: Colors.amber),
            const SizedBox(width: 4),
            Text(label1, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 12),
            const Icon(Icons.show_chart, size: 14, color: Colors.lightBlue),
            const SizedBox(width: 4),
            Text(label2, style: const TextStyle(fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 160,
          width: double.infinity,
          child: CustomPaint(painter: _WormPainter(innings1, innings2)),
        ),
      ],
    );
  }
}

class _WormPainter extends CustomPainter {
  final List<int> a;
  final List<int> b;
  _WormPainter(this.a, this.b);

  void _drawLine(
    Canvas canvas,
    List<int> data,
    Color color,
    double maxX,
    double maxY,
    Size size,
  ) {
    if (data.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < data.length; i++) {
      final x = (i + 1) / maxX * size.width;
      final y = size.height - (data[i] / maxY * size.height);
      if (i == 0) {
        path.moveTo(0, size.height);
        path.lineTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
    final dot = Paint()..color = color;
    for (var i = 0; i < data.length; i++) {
      final x = (i + 1) / maxX * size.width;
      final y = size.height - (data[i] / maxY * size.height);
      canvas.drawCircle(Offset(x, y), 2.5, dot);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white24
      ..strokeWidth = 0.5;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final maxLen = math.max(a.length, b.length);
    if (maxLen == 0) return;
    final maxY = math.max(
      a.isEmpty ? 0 : a.reduce(math.max),
      b.isEmpty ? 0 : b.reduce(math.max),
    );
    _drawLine(
      canvas,
      a,
      Colors.amber,
      maxLen.toDouble(),
      (maxY == 0 ? 1 : maxY).toDouble(),
      size,
    );
    _drawLine(
      canvas,
      b,
      Colors.lightBlue,
      maxLen.toDouble(),
      (maxY == 0 ? 1 : maxY).toDouble(),
      size,
    );
  }

  @override
  bool shouldRepaint(covariant _WormPainter old) => old.a != a || old.b != b;
}

/// Over comparison (Manhattan): bars of runs per over.
class ManhattanChart extends StatelessWidget {
  final List<int> innings1;
  final List<int> innings2;
  const ManhattanChart({
    super.key,
    required this.innings1,
    required this.innings2,
  });

  @override
  Widget build(BuildContext context) {
    final maxLen = math.max(innings1.length, innings2.length);
    final maxVal = [...innings1, ...innings2, 1].reduce(math.max);
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < maxLen; i++)
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (i < innings1.length)
                    Container(
                      width: 10,
                      height: 130 * innings1[i] / maxVal + 2,
                      color: Colors.amber,
                    ),
                  if (i < innings2.length)
                    Container(
                      width: 10,
                      height: 130 * innings2[i] / maxVal + 2,
                      color: Colors.lightBlue,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Wagon wheel: free-touch shot plot drawn as trajectory lines.
/// The scorer taps the wheel where the ball went; each shot becomes a line
/// from the pitch (center) in that direction. Line length/shape per outcome:
/// - 6: green, curved (in the air), extends beyond the boundary
/// - 4: blue, straight to the boundary (ground shot)
/// - 1/2/3: straight line to the tapped point inside the ground
/// - 0: grey dot at the tapped point
/// - wicket: red line to the tapped point
/// No score text is drawn — color carries the meaning (see [WagonLegend]).
class WagonWheel extends StatelessWidget {
  final List<ShotPlot> shots;
  final double diameter;
  const WagonWheel({super.key, required this.shots, this.diameter = 240});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: diameter,
      width: diameter,
      child: CustomPaint(painter: _WagonPainter(shots)),
    );
  }
}

/// Color for a wagon-wheel shot: six = green, wicket = red, others split.
Color wagonShotColor(int runs, bool isWicket) {
  if (isWicket) return const Color(0xFFEF5350);
  switch (runs) {
    case 6:
      return const Color(0xFF66BB6A);
    case 4:
      return const Color(0xFF42A5F5);
    case 3:
      return const Color(0xFFAB47BC);
    case 2:
      return const Color(0xFFFFA726);
    case 1:
      return const Color(0xFFFFD54F);
    default:
      return const Color(0xFF9E9E9E);
  }
}

/// Compact color legend for the wagon wheel.
class WagonLegend extends StatelessWidget {
  const WagonLegend({super.key});

  @override
  Widget build(BuildContext context) {
    Widget item(int runs, String label, {bool wicket = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 4,
              decoration: BoxDecoration(
                color: wagonShotColor(runs, wicket),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        );
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        item(1, '1'),
        item(2, '2'),
        item(3, '3'),
        item(4, '4'),
        item(6, '6'),
        item(0, 'W', wicket: true),
      ],
    );
  }
}

class _WagonPainter extends CustomPainter {
  final List<ShotPlot> shots;
  _WagonPainter(this.shots);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    final linePaint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    // boundary + inner circle
    canvas.drawCircle(center, radius, linePaint);
    canvas.drawCircle(center, radius * 0.45, linePaint);
    // crosshair guides
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      linePaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      linePaint,
    );
    // pitch
    final pitch = Paint()..color = Colors.brown.shade300;
    canvas.drawRect(
      Rect.fromCenter(center: center, width: 14, height: 60),
      pitch,
    );
    // shots as trajectory lines
    for (final s in shots) {
      final dist = math.sqrt(s.x * s.x + s.y * s.y);
      final ux = dist < 0.01 ? 1.0 : s.x / dist;
      final uy = dist < 0.01 ? 0.0 : s.y / dist;
      final color = wagonShotColor(s.runs, s.isWicket);
      final paint = Paint()
        ..color = color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      if (!s.isWicket && s.runs == 6) {
        // six: curved line beyond the boundary (in the air)
        final endDist = radius * 1.28;
        final end =
            Offset(center.dx + ux * endDist, center.dy + uy * endDist);
        final mid = Offset(
          center.dx + ux * endDist * 0.5,
          center.dy + uy * endDist * 0.5,
        );
        final ctrl = Offset(
          mid.dx - uy * radius * 0.4,
          mid.dy + ux * radius * 0.4,
        );
        final path = Path()
          ..moveTo(center.dx, center.dy)
          ..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);
        canvas.drawPath(path, paint);
        // landing dot beyond the rope
        canvas.drawCircle(end, 3.5, Paint()..color = color);
      } else if (!s.isWicket && s.runs == 0) {
        // dot ball: small dot where it went
        final p = Offset(
          center.dx + s.x.clamp(-1.0, 1.0) * radius,
          center.dy + s.y.clamp(-1.0, 1.0) * radius,
        );
        canvas.drawCircle(p, 4, Paint()..color = color);
      } else {
        // 4 to the boundary; 1/2/3/wicket to the tapped point
        var len = dist * radius;
        if (s.runs == 4) len = radius;
        if (dist < 0.05) len = radius * 0.8;
        len = len.clamp(0.0, radius * 1.02);
        canvas.drawLine(
          center,
          Offset(center.dx + ux * len, center.dy + uy * len),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WagonPainter old) => old.shots != shots;
}
