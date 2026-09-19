// Геометрия: расстояния, азимуты, сетка тумана. Перенос js/geo.js один в один —
// ключи ячеек "row:col" совпадают с веб-версией, прогресс можно будет перенести.

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

const double earthR = 6371000;
double _rad(double d) => d * math.pi / 180;
double _deg(double r) => r * 180 / math.pi;

/// Расстояние между точками в метрах (haversine).
double distance(LatLng a, LatLng b) {
  final dLat = _rad(b.latitude - a.latitude);
  final dLon = _rad(b.longitude - a.longitude);
  final s = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.latitude)) * math.cos(_rad(b.latitude)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * earthR * math.asin(math.sqrt(s));
}

/// Азимут a→b в градусах (0 = север, по часовой).
double bearing(LatLng a, LatLng b) {
  final y = math.sin(_rad(b.longitude - a.longitude)) * math.cos(_rad(b.latitude));
  final x = math.cos(_rad(a.latitude)) * math.sin(_rad(b.latitude)) -
      math.sin(_rad(a.latitude)) * math.cos(_rad(b.latitude)) * math.cos(_rad(b.longitude - a.longitude));
  return (_deg(math.atan2(y, x)) + 360) % 360;
}

/// Сместить точку на [meters] по азимуту [deg]. Плоское приближение для коротких дистанций.
LatLng move(LatLng p, double deg, double meters) {
  final dNorth = math.cos(_rad(deg)) * meters;
  final dEast = math.sin(_rad(deg)) * meters;
  return LatLng(
    p.latitude + _deg(dNorth / earthR),
    p.longitude + _deg(dEast / (earthR * math.cos(_rad(p.latitude)))),
  );
}

/// Смещение b относительно a в метрах: dx — на восток, dy — на север.
({double dx, double dy}) offsetMeters(LatLng a, LatLng b) => (
      dx: _rad(b.longitude - a.longitude) * earthR * math.cos(_rad(a.latitude)),
      dy: _rad(b.latitude - a.latitude) * earthR,
    );

LatLng lerpLatLng(LatLng a, LatLng b, double t) =>
    LatLng(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t);

// ---------- Сетка тумана ----------
// Строка зависит только от широты, столбец — от долготы с учётом широты строки,
// так что ячейки примерно квадратные и ключи стабильны.
const double cell = 20; // метров
const double _mPerDegLat = 111320;

double cellRowHeightDeg() => cell / _mPerDegLat;

double cellColWidthDeg(int row) {
  final lat = (row + 0.5) * cellRowHeightDeg();
  return cell / (_mPerDegLat * math.cos(_rad(lat)));
}

({int row, int col}) cellOf(LatLng p) {
  final row = (p.latitude / cellRowHeightDeg()).floor();
  final col = (p.longitude / cellColWidthDeg(row)).floor();
  return (row: row, col: col);
}

String cellKey(int row, int col) => '$row:$col';

LatLng cellCenter(int row, int col) =>
    LatLng((row + 0.5) * cellRowHeightDeg(), (col + 0.5) * cellColWidthDeg(row));

/// Ключи ячеек в радиусе [radius] метров от точки.
List<String> cellsInRadius(LatLng p, double radius) {
  final out = <String>[];
  final h = cellRowHeightDeg();
  final rows = (radius / cell).ceil() + 1;
  final r0 = cellOf(p).row;
  for (var r = r0 - rows; r <= r0 + rows; r++) {
    final w = cellColWidthDeg(r);
    final c0 = (p.longitude / w).floor();
    for (var c = c0 - rows; c <= c0 + rows; c++) {
      final cc = LatLng((r + 0.5) * h, (c + 0.5) * w);
      if (distance(p, cc) <= radius) out.add(cellKey(r, c));
    }
  }
  return out;
}

String formatDistance(double m) =>
    m < 1000 ? '${m.round()} м' : '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} км';
