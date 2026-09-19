// Пешеходные маршруты: OSRM с профилем foot на сервере FOSSGIS (routing.openstreetmap.de).
// Если сервер недоступен, маршрут — прямая, игра продолжает работать.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/geo.dart';

const _osrm = 'https://routing.openstreetmap.de/routed-foot/route/v1/driving/';
final _cache = <String, GeoPath>{};

/// Маршрут пешком a → b. Всегда завершается: при ошибке вернёт прямую с [GeoPath.fallback].
Future<GeoPath> walkRoute(LatLng a, LatLng b) async {
  final key = [a.latitude, a.longitude, b.latitude, b.longitude].map((v) => v.toStringAsFixed(5)).join(',');
  final hit = _cache[key];
  if (hit != null) return hit;
  try {
    final url = '$_osrm${a.longitude},${a.latitude};${b.longitude},${b.latitude}?overview=full&geometries=geojson';
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final coords = (((json['routes'] as List?)?.firstOrNull as Map?)?['geometry'] as Map?)?['coordinates'] as List?;
    if (coords == null || coords.isEmpty) throw Exception(json['code'] ?? 'нет маршрута');
    // OSRM привязывает концы к ближайшей дороге — добавляем исходные точки, чтобы NPC начинал и заканчивал у места
    final path = GeoPath([
      a,
      ...coords.map((c) => LatLng(((c as List)[1] as num).toDouble(), (c[0] as num).toDouble())),
      b,
    ]);
    _cache[key] = path;
    return path;
  } catch (e) {
    debugPrint('[route] маршрут не построен, иду по прямой: $e');
    return GeoPath([a, b], fallback: true); // не кэшируем: в следующий раз попробуем снова
  }
}

/// Полилиния с накопленной длиной: позиция по пройденному расстоянию.
class GeoPath {
  GeoPath(List<LatLng> points, {this.fallback = false}) {
    for (final p in points) {
      if (pts.isEmpty || distance(pts.last, p) > 0.01) pts.add(p);
    }
    if (pts.length < 2) pts.add(pts.first);
    cum.add(0);
    for (var i = 1; i < pts.length; i++) {
      cum.add(cum[i - 1] + distance(pts[i - 1], pts[i]));
    }
  }

  final List<LatLng> pts = [];
  final List<double> cum = [];
  final bool fallback;

  double get length => cum.last;

  /// Точка и направление на расстоянии [d] от начала.
  ({LatLng pos, double heading}) at(double d) {
    final n = pts.length;
    if (d <= 0) return (pos: pts[0], heading: bearing(pts[0], pts[1]));
    if (d >= length) return (pos: pts[n - 1], heading: bearing(pts[n - 2], pts[n - 1]));
    var lo = 0, hi = n - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (cum[mid] <= d) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final seg = cum[hi] - cum[lo];
    return (pos: lerpLatLng(pts[lo], pts[hi], seg > 0 ? (d - cum[lo]) / seg : 0), heading: bearing(pts[lo], pts[hi]));
  }
}
