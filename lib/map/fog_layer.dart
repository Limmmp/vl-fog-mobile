// Слой тумана поверх карты: сплошная заливка, из которой вырезаны размытые круги открытых ячеек.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../core/geo.dart';
import '../game/fog.dart';
import '../ui/palette.dart';

class FogLayer extends StatelessWidget {
  const FogLayer({super.key, required this.fog});

  final FogOfWar fog;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return ListenableBuilder(
      listenable: fog,
      builder: (context, _) => IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          painter: _FogPainter(fog: fog, camera: camera, version: fog.version),
        ),
      ),
    );
  }
}

class _FogPainter extends CustomPainter {
  _FogPainter({required this.fog, required this.camera, required this.version});

  final FogOfWar fog;
  final MapCamera camera;
  final int version;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Метров на пиксель в центре экрана (Web Mercator, тайл 256)
    final mPerPx = 40075016.686 * math.cos(camera.center.latitude * math.pi / 180) / math.pow(2, camera.zoom + 8);
    final r = math.max(1.2, cell * 0.95 / mPerPx);

    // Запас за краем экрана, чтобы размытые края не обрезались
    final pad = r * 2;
    final nw = camera.screenOffsetToLatLng(Offset(-pad, -pad));
    final se = camera.screenOffsetToLatLng(Offset(size.width + pad, size.height + pad));
    final rh = cellRowHeightDeg();
    final rowMin = (se.latitude / rh).floor() - 1;
    final rowMax = (nw.latitude / rh).floor() + 1;

    final holes = Path();
    void addCell(int row, int col) {
      final c = cellCenter(row, col);
      final pt = camera.latLngToScreenOffset(c);
      holes.addOval(Rect.fromCircle(center: pt, radius: r));
    }

    // Маленькая видимая область — перебираем её ячейки, иначе — открытые ячейки
    final estVisible = (rowMax - rowMin) * ((se.longitude - nw.longitude) / cellColWidthDeg(rowMin));
    if (estVisible < fog.cells.length) {
      for (var row = rowMin; row <= rowMax; row++) {
        final cw = cellColWidthDeg(row);
        final colMin = (nw.longitude / cw).floor() - 1;
        final colMax = (se.longitude / cw).floor() + 1;
        for (var col = colMin; col <= colMax; col++) {
          if (fog.cells.contains(cellKey(row, col))) addCell(row, col);
        }
      }
    } else {
      for (final k in fog.cells) {
        final i = k.indexOf(':');
        final row = int.parse(k.substring(0, i));
        if (row < rowMin || row > rowMax) continue;
        addCell(row, int.parse(k.substring(i + 1)));
      }
    }

    canvas.saveLayer(rect, Paint());
    canvas.drawRect(rect, Paint()..color = Palette.fog);
    canvas.drawPath(
      holes,
      Paint()
        ..blendMode = BlendMode.dstOut
        ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, math.max(2, r * 0.8)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FogPainter old) =>
      old.version != version || old.camera.center != camera.center || old.camera.zoom != camera.zoom ||
      old.camera.size != camera.size;
}
