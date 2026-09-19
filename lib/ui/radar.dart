// Радар в углу (как в GTA) и стрелка у края экрана, когда цель за его пределами.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../core/geo.dart';
import '../game/fog.dart';
import '../game/player.dart';
import '../game/quests/engine.dart';
import 'palette.dart';

const double _range = 350; // м от центра до края радара

class Radar extends StatelessWidget {
  const Radar({super.key, required this.fog, required this.player, required this.quests, this.size = 150, this.onTap});

  final FogOfWar fog;
  final Player player;
  final QuestEngine quests;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Радар: открытая территория и метки вокруг',
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF0B0F15),
            boxShadow: [BoxShadow(color: Color(0x8C000000), blurRadius: 24, offset: Offset(0, 6))],
          ),
          foregroundDecoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xD9000000), width: 3),
          ),
          child: ClipOval(
            child: ListenableBuilder(
              listenable: Listenable.merge([player, fog, quests]),
              builder: (context, _) => CustomPaint(painter: _RadarPainter(fog, player, quests.blips())),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.fog, this.player, this.blips);

  final FogOfWar fog;
  final Player player;
  final List<Blip> blips;

  @override
  void paint(Canvas canvas, Size size) {
    final p = player.pos;
    final c = size.width / 2;
    final k = (c - 2) / _range; // px на метр
    final center = Offset(c, c);

    // Открытые ячейки
    final cellPaint = Paint()..color = const Color(0xFF3B4756);
    final cs = cell * k + 0.6; // чуть внахлёст, чтобы не было швов
    final rows = (_range / cell).ceil() + 1;
    final r0 = cellOf(p).row;
    for (var r = r0 - rows; r <= r0 + rows; r++) {
      final c0 = (p.longitude / cellColWidthDeg(r)).floor();
      for (var col = c0 - rows; col <= c0 + rows; col++) {
        if (!fog.cells.contains(cellKey(r, col))) continue;
        final o = offsetMeters(p, cellCenter(r, col));
        canvas.drawRect(Rect.fromCenter(center: Offset(c + o.dx * k, c - o.dy * k), width: cs, height: cs), cellPaint);
      }
    }

    // Кольцо на половине дальности
    canvas.drawCircle(center, c / 2,
        Paint()
          ..color = const Color(0x14FFFFFF)
          ..style = PaintingStyle.stroke);

    // Метки: за пределами дальности прижимаем к краю
    final order = [BlipKind.offer, BlipKind.story, BlipKind.target, BlipKind.tail];
    final sorted = [...blips]..sort((a, b) => order.indexOf(a.kind).compareTo(order.indexOf(b.kind)));
    for (final b in sorted) {
      final (color, radius, ring) = switch (b.kind) {
        BlipKind.offer => (Palette.gold, 3.5, false),
        BlipKind.story => (Palette.gold, 4.5, true),
        BlipKind.target => (Palette.gold, 5.0, true),
        BlipKind.tail => (Palette.red, 4.5, true),
      };
      final o = offsetMeters(p, b.pos);
      final d = math.sqrt(o.dx * o.dx + o.dy * o.dy);
      final maxPx = c - radius - 3;
      var x = o.dx * k, y = -o.dy * k;
      final far = d * k > maxPx;
      if (far) {
        x = x / (d * k) * maxPx;
        y = y / (d * k) * maxPx;
      }
      final pt = center + Offset(x, y);
      final rr = far ? radius * 0.8 : radius;
      canvas.drawCircle(pt, rr, Paint()..color = color);
      if (ring) {
        canvas.drawCircle(pt, rr,
            Paint()
              ..color = Colors.black
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5);
      }
    }

    // Игрок — стрелка по курсу
    canvas.save();
    canvas.translate(c, c);
    canvas.rotate(player.heading * math.pi / 180);
    final arrow = Path()
      ..moveTo(0, -7)
      ..lineTo(5, 6)
      ..lineTo(0, 3)
      ..lineTo(-5, 6)
      ..close();
    canvas.drawPath(arrow, Paint()..color = Colors.white);
    canvas.drawPath(
        arrow,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    canvas.restore();

    // Север
    final tp = TextPainter(
      text: const TextSpan(text: 'С', style: TextStyle(color: Palette.inkDim, fontSize: 10, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(c - tp.width / 2, 3));
  }

  @override
  bool shouldRepaint(_RadarPainter old) => true; // перерисовка по ListenableBuilder — дёшево, ~1000 ячеек
}

/// Стрелка у края экрана на цель вне видимой области. Кладётся в Stack поверх карты.
class EdgeArrow extends StatelessWidget {
  const EdgeArrow({super.key, required this.camera, required this.quests, required this.player, required this.insets, this.avoid});

  final MapCamera camera;
  final QuestEngine quests;
  final Player player;

  /// Отступы рамки, по которой ездит стрелка.
  final EdgeInsets insets;

  /// Прямоугольник, под который стрелка не должна заезжать (радар).
  final Rect? avoid;

  @override
  Widget build(BuildContext context) {
    final t = quests.guideTarget();
    if (t == null) return const SizedBox.shrink();
    final size = camera.size;
    final pt = camera.latLngToScreenOffset(t.pos);
    final l = insets.left, r = size.width - insets.right, top = insets.top, b = size.height - insets.bottom;
    if (pt.dx >= l && pt.dx <= r && pt.dy >= top && pt.dy <= b) return const SizedBox.shrink();

    // Луч из центра экрана к цели, пересечение с рамкой отступов
    final cx = size.width / 2, cy = size.height / 2;
    final dx = pt.dx - cx, dy = pt.dy - cy;
    final s = math.min(
      dx > 0 ? (r - cx) / dx : dx < 0 ? (l - cx) / dx : double.infinity,
      dy > 0 ? (b - cy) / dy : dy < 0 ? (top - cy) / dy : double.infinity,
    );
    var x = cx + dx * s, y = cy + dy * s;

    // Радар — препятствие: сдвигаем стрелку вдоль того же края, пока она не выйдет из-под него
    final a = avoid?.inflate(22);
    if (a != null && a.contains(Offset(x, y))) {
      final onSide = x <= l + 0.5 || x >= r - 0.5;
      if (onSide) {
        y = a.top;
      } else {
        x = a.left > size.width / 2 ? a.left : a.right;
      }
    }

    final color = t.isOffer ? Palette.gold.withValues(alpha: 0.6) : Palette.gold;
    return Positioned(
      left: x - 30,
      top: y - 16,
      width: 60,
      child: IgnorePointer(
        child: Column(children: [
          Transform.rotate(
            angle: math.atan2(dx, -dy),
            child: CustomPaint(size: const Size(28, 28), painter: _ArrowPainter(color)),
          ),
          Text(formatDistance(distance(player.pos, t.pos)),
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                shadows: const [Shadow(color: Colors.black, offset: Offset(0, 1)), Shadow(color: Colors.black, blurRadius: 4)],
              )),
        ]),
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final path = Path()
      ..moveTo(s.width / 2, 0)
      ..lineTo(s.width, s.height)
      ..lineTo(s.width / 2, s.height * 0.72)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawShadow(path, Colors.black, 2, false);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.color != color;
}
