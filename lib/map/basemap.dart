// Подложка: векторные тайлы OpenFreeMap (без ключа), тема — наш стиль assets/map/style.json
// (тот же, что в веб-версии; собирается vl-fog/tools/build-map-style.py).
// Тайлы кэширует vector_map_tiles в файлах приложения (см. tile_cache.dart) — так карта работает и без связи.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import '../core/storage.dart';

const _tileJsonUrl = 'https://tiles.openfreemap.org/planet';
const _maxTileZoom = 14; // глубже тайлы не нарезаны, крупнее рисуются из z14

class Basemap {
  Basemap({required this.theme, required this.providers});

  final vtr.Theme theme;
  final TileProviders providers;

  static Future<Basemap> load(Store store) async {
    final style = jsonDecode(await rootBundle.loadString('assets/map/style.json')) as Map<String, dynamic>;
    final theme = vtr.ThemeReader().read(style);
    final template = await _tileTemplate(store);
    return Basemap(
      theme: theme,
      providers: TileProviders({
        'openmaptiles': NetworkVectorTileProvider(urlTemplate: template, maximumZoom: _maxTileZoom),
      }),
    );
  }

  /// Адрес тайлов версионирован (planet/<дата>/{z}/{x}/{y}.pbf) и меняется при обновлении данных.
  /// Берём свежий из TileJSON, без сети — последний известный.
  static Future<String> _tileTemplate(Store store) async {
    try {
      final res = await http.get(Uri.parse(_tileJsonUrl)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final tiles = (jsonDecode(res.body) as Map<String, dynamic>)['tiles'] as List<dynamic>;
        final t = tiles.first as String;
        store.save('tileTemplate', t);
        return t;
      }
    } catch (e) {
      debugPrint('[basemap] TileJSON недоступен, беру сохранённый адрес: $e');
    }
    return store.load<String?>('tileTemplate', null) ??
        // Последняя известная версия на момент сборки: лучше старая карта, чем никакой
        'https://tiles.openfreemap.org/planet/20260913_164504_pt/{z}/{x}/{y}.pbf';
  }
}
