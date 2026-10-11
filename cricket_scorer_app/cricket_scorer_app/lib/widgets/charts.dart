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
        Row(children: [
          const Icon(Icons.show_chart, size: 14, color: Colors.amber),
          const SizedBox(width: 4),
          Text(label1, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 12),
          const Icon(Icons.show_chart, size: 14, color: Colors.lightBlue),
          const SizedBox(width: 4),
          Text(label2, style: const TextStyle(fontSize: 12)),
        ]),
        const SizedBox(height: 6),
        SizedBox(
          height: 160,
          width: double.infinity,
          child: CustomPaint(
            painter: _WormPainter(innings1, innings2),
          ),
        ),
      ],
    );
  }
}

class _WormPainter extends CustomPainter {
  final List<int> a;
  final List<int> b;
  _WormPainter(this.a, this.b);

  void _drawLine(Canvas canvas, List<int> data, Color color, double maxX, double maxY, Size size) {
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
        a.isEmpty ? 0 : a.reduce(math.max), b.isEmpty ? 0 : b.reduce(math.max));
    _drawLine(canvas, a, Colors.amber, maxLen.toDouble(),
        (maxY == 0 ? 1 : maxY).toDouble(), size);
    _drawLine(canvas, b, Colors.lightBlue, maxLen.toDouble(),
        (maxY == 0 ? 1 : maxY).toDouble(), size);
  }

  @override
  bool shouldRepaint(covariant _WormPainter old) =>
      old.a != a || old.b != b;
}

/// Over comparison (Manhattan): bars of runs per over.
class ManhattanChart extends StatelessWidget {
  final List<int> innings1;
  final List<int> innings2;
  const ManhattanChart({super.key, required this.innings1, required this.innings2});

  @override
  Widget build(BuildContext context) {
    final maxLen = math.max(innings1.length, innings2.length);
    final maxVal = [
      ...innings1,
      ...innings2,
      1
    ].reduce(math.max);
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

/// Wagon wheel: 8 zones around the pitch with shot counts / runs.
class WagonWheel extends StatelessWidget {
  final Map<int, ZoneStat> zones;
  const WagonWheel({super.key, required this.zones});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 240,
      width: 240,
      child: CustomPaint(painter: _WagonPainter(zones)),
    );
  }
}

class _WagonPainter extends CustomPainter {
  final Map<int, ZoneStat> zones;
  _WagonPainter(this.zones);

  // Zone layout: 8 sectors; labels drawn as numbers 1-8.

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    final maxRuns = zones.values.fold<int>(1, (m, z) => math.max(m, z.runs));
    final linePaint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, linePaint);
    canvas.drawCircle(center, radius * 0.45, linePaint);
    for (var z = 1; z <= 8; z++) {
      // zone z occupies a 45-degree sector; zone 4 (long off) at bottom-right
      final start = (z - 1) * math.pi / 4 + math.pi / 8;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(center.dx + radius * math.cos(start),
            center.dy + radius * math.sin(start));
      canvas.drawPath(path, linePaint);
      final stat = zones[z];
      if (stat != null && stat.balls > 0) {
        final mid = start + math.pi / 8;
        final intensity = 0.25 + 0.65 * (stat.runs / maxRuns);
        final fill = Paint()
          ..color = Colors.green.withValues(alpha: intensity)
          ..style = PaintingStyle.fill;
        final sector = Path()
          ..moveTo(center.dx, center.dy)
          ..arcTo(
              Rect.fromCircle(center: center, radius: radius), start, math.pi / 4, false)
          ..close();
        canvas.drawPath(sector, fill);
        final tx = center.dx + radius * 0.72 * math.cos(mid);
        final ty = center.dy + radius * 0.72 * math.sin(mid);
        final tp = TextPainter(
          text: TextSpan(
            text: '${stat.runs}r\n${stat.balls}b',
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        )..layout();
        tp.paint(canvas, Offset(tx - tp.width / 2, ty - tp.height / 2));
      }
      final lx = center.dx + (radius + 2) * math.cos(start + math.pi / 8);
      final ly = center.dy + (radius + 2) * math.sin(start + math.pi / 8);
      final label = TextPainter(
        text: TextSpan(
          text: '$z',
          style: const TextStyle(color: Colors.white70, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(lx - label.width / 2, ly - label.height / 2));
    }
    // pitch
    final pitch = Paint()..color = Colors.brown.shade300;
    canvas.drawRect(
        Rect.fromCenter(center: center, width: 14, height: 60), pitch);
  }

  @override
  bool shouldRepaint(covariant _WagonPainter old) => old.zones != zones;
}
