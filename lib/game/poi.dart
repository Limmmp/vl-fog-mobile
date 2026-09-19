// Точки интереса: реальные места из OpenStreetMap (Overpass API) + встроенные достопримечательности.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/geo.dart';
import '../core/storage.dart';

const _overpass = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
];
const double _radius = 1500; // м вокруг игрока
const _cacheTtl = Duration(days: 7);
const double _tileDeg = 0.02; // кэшируем кусками ~2×1.6 км

class Poi {
  const Poi({required this.id, required this.name, required this.pos, required this.kind});

  final String id;
  final String name;
  final LatLng pos;
  final String kind; // food|bar|park|view|water|culture|landmark|shop|auto|misc

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'lat': pos.latitude, 'lon': pos.longitude, 'kind': kind};

  factory Poi.fromJson(Map<String, dynamic> j) => Poi(
        id: j['id'] as String,
        name: j['name'] as String,
        pos: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        kind: j['kind'] as String,
      );
}

/// Встроенные достопримечательности. Координаты приблизительные (±50–100 м).
/// Эти id используются сюжетной аркой в quests/story.dart.
const landmarks = [
  Poi(id: 'lm:square', name: 'Центральная площадь', pos: LatLng(43.1155, 131.8855), kind: 'landmark'),
  Poi(id: 'lm:arbat', name: 'Арбат (ул. Адмирала Фокина)', pos: LatLng(43.1170, 131.8818), kind: 'landmark'),
  Poi(id: 'lm:sport', name: 'Спортивная гавань', pos: LatLng(43.1178, 131.8775), kind: 'water'),
  Poi(id: 'lm:station', name: 'Ж/д вокзал', pos: LatLng(43.1112, 131.8818), kind: 'landmark'),
  Poi(id: 'lm:s56', name: 'Подлодка С-56', pos: LatLng(43.1142, 131.8937), kind: 'culture'),
  Poi(id: 'lm:korabelnaya', name: 'Корабельная набережная', pos: LatLng(43.1133, 131.8900), kind: 'water'),
  Poi(id: 'lm:funicular', name: 'Фуникулёр (нижняя станция)', pos: LatLng(43.1178, 131.8950), kind: 'landmark'),
  Poi(id: 'lm:eagle', name: 'Смотровая «Орлиное гнездо»', pos: LatLng(43.1210, 131.8925), kind: 'view'),
  Poi(id: 'lm:goldbridge', name: 'Золотой мост', pos: LatLng(43.1105, 131.8905), kind: 'landmark'),
  Poi(id: 'lm:millionka', name: 'Миллионка', pos: LatLng(43.1178, 131.8868), kind: 'landmark'),
  Poi(id: 'lm:dinamo', name: 'Стадион «Динамо»', pos: LatLng(43.1195, 131.8795), kind: 'landmark'),
  Poi(id: 'lm:pokrovsky', name: 'Покровский парк', pos: LatLng(43.1272, 131.8960), kind: 'park'),
  Poi(id: 'lm:tokarevsky', name: 'Токаревский маяк', pos: LatLng(43.0737, 131.8425), kind: 'view'),
  Poi(id: 'lm:russkybridge', name: 'Русский мост (смотровая)', pos: LatLng(43.0620, 131.9050), kind: 'view'),
];

const kindLabel = {
  'food': 'еда', 'bar': 'бар', 'park': 'парк', 'view': 'вид', 'water': 'у воды',
  'culture': 'культура', 'landmark': 'место', 'shop': 'магазин', 'auto': 'авто', 'misc': 'место',
};

class PoiService {
  PoiService(this._store) {
    for (final p in landmarks) {
      pois[p.id] = p;
    }
  }

  final Store _store;
  final Map<String, Poi> pois = {};
  final Set<String> _loadedTiles = {};
  String? _loadingKey; // занимаем сразу, до чтения кэша — иначе параллельные вызовы шлют два запроса

  Poi? get(String id) => pois[id];

  /// Точки в радиусе от точки, от ближних к дальним, вместе с расстоянием.
  List<(Poi, double)> near(LatLng p, [double maxDist = _radius, bool Function(Poi)? filter]) {
    final out = <(Poi, double)>[];
    for (final poi in pois.values) {
      if (filter != null && !filter(poi)) continue;
      final d = distance(p, poi.pos);
      if (d <= maxDist) out.add((poi, d));
    }
    out.sort((a, b) => a.$2.compareTo(b.$2));
    return out;
  }

  /// Подгрузить места из OSM вокруг игрока (с кэшем). Безопасно вызывать часто.
  Future<void> ensureAround(LatLng p) async {
    final key = '${(p.latitude / _tileDeg).floor()}_${(p.longitude / _tileDeg).floor()}';
    if (_loadedTiles.contains(key) || _loadingKey != null) return;
    _loadingKey = key;
    try {
      final cached = await _store.loadBlob('poi_$key.json');
      if (cached != null) {
        try {
          final j = jsonDecode(cached) as Map<String, dynamic>;
          final age = DateTime.now().millisecondsSinceEpoch - (j['t'] as num).toInt();
          if (age < _cacheTtl.inMilliseconds) {
            _add((j['items'] as List).map((e) => Poi.fromJson(e as Map<String, dynamic>)));
            _loadedTiles.add(key);
            return;
          }
        } catch (_) {/* битый кэш — перекачаем */}
      }
      final items = await _fetch(p);
      _add(items);
      _store.saveBlob('poi_$key.json',
          jsonEncode({'t': DateTime.now().millisecondsSinceEpoch, 'items': items.map((e) => e.toJson()).toList()}));
      _loadedTiles.add(key);
    } catch (e) {
      debugPrint('[poi] Overpass недоступен, работаем на встроенных точках: $e');
      _loadedTiles.add(key); // не долбим сервер повторно в эту сессию
    } finally {
      _loadingKey = null;
    }
  }

  void _add(Iterable<Poi> items) {
    for (final it in items) {
      pois[it.id] = it;
    }
  }

  Future<List<Poi>> _fetch(LatLng p) async {
    final a = 'around:${_radius.round()},${p.latitude},${p.longitude}';
    final q = '''[out:json][timeout:25];
(
  nwr($a)["amenity"~"^(cafe|restaurant|bar|pub|fast_food|pharmacy|theatre|cinema|marketplace|ferry_terminal|fuel|library|university)\$"]["name"];
  nwr($a)["tourism"~"^(attraction|viewpoint|museum|artwork|gallery)\$"];
  nwr($a)["historic"~"^(memorial|monument|ship|fort|building)\$"]["name"];
  nwr($a)["man_made"~"^(lighthouse|pier)\$"];
  nwr($a)["leisure"~"^(park|garden|stadium|playground)\$"]["name"];
  nwr($a)["shop"~"^(convenience|supermarket|mall|seafood|car_parts|car)\$"]["name"];
);
out center 500;''';
    Object? lastErr;
    for (final url in _overpass) {
      try {
        final res = await http
            .post(Uri.parse(url), body: {'data': q}, headers: {'User-Agent': 'vl-fog/1.0 (street game)'})
            .timeout(const Duration(seconds: 30));
        if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
        final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return (json['elements'] as List).map((e) => _toPoi(e as Map<String, dynamic>)).whereType<Poi>().toList();
      } catch (e) {
        lastErr = e;
      }
    }
    throw lastErr ?? Exception('Overpass недоступен');
  }
}

Poi? _toPoi(Map<String, dynamic> el) {
  final center = el['center'] as Map<String, dynamic>?;
  final lat = (el['lat'] ?? center?['lat']) as num?;
  final lon = (el['lon'] ?? center?['lon']) as num?;
  if (lat == null || lon == null) return null;
  final t = (el['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
  final kind = _classify(t);
  final name = (t['name'] ?? t['name:ru'] ?? _defaultName(t)) as String?;
  if (name == null) return null;
  return Poi(id: '${(el['type'] as String)[0]}${el['id']}', name: name, pos: LatLng(lat.toDouble(), lon.toDouble()), kind: kind);
}

/// Сводим теги OSM к игровым категориям.
String _classify(Map<String, dynamic> t) {
  final amenity = t['amenity'], tourism = t['tourism'], manMade = t['man_made'], shop = t['shop'];
  if (const {'cafe', 'restaurant', 'fast_food'}.contains(amenity)) return 'food';
  if (const {'bar', 'pub'}.contains(amenity)) return 'bar';
  if (t['leisure'] != null) return t['leisure'] == 'stadium' ? 'landmark' : 'park';
  if (tourism == 'viewpoint' || manMade == 'lighthouse') return 'view';
  if (manMade == 'pier' || amenity == 'ferry_terminal') return 'water';
  if (const {'museum', 'gallery', 'artwork'}.contains(tourism) || const {'theatre', 'cinema', 'library'}.contains(amenity)) {
    return 'culture';
  }
  if (t['historic'] != null || tourism == 'attraction') return 'landmark';
  if (amenity == 'fuel' || shop == 'car' || shop == 'car_parts') return 'auto';
  if (shop != null || amenity == 'marketplace') return 'shop';
  return 'misc';
}

String? _defaultName(Map<String, dynamic> t) {
  if (t['man_made'] == 'pier') return 'Причал';
  if (t['man_made'] == 'lighthouse') return 'Маяк';
  if (t['tourism'] == 'viewpoint') return 'Смотровая площадка';
  if (t['tourism'] == 'artwork') return 'Арт-объект';
  return null;
}
