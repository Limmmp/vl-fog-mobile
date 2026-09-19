// Туман войны: набор открытых ячеек сетки 20 м (см. core/geo.dart).

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../core/geo.dart';
import '../core/storage.dart';

const double revealRadius = 45; // метров вокруг игрока

/// Слушатель получает ключи только что открытых ячеек; пустой список — туман сброшен.
typedef FogListener = void Function(List<String> fresh);

class FogOfWar extends ChangeNotifier {
  FogOfWar(this._store) {
    _persist = Debouncer(const Duration(seconds: 2), () => _store.saveBlob('fog.json', jsonCells()));
  }

  final Store _store;
  final Set<String> cells = {};
  final List<FogListener> _listeners = [];
  late final Debouncer _persist;

  /// Сколько раз туман менялся — слой тумана перерисовывается по этому счётчику.
  int version = 0;

  Future<void> load() async {
    final raw = await _store.loadBlob('fog.json');
    if (raw == null || raw.isEmpty) return;
    cells.addAll(raw.split(','));
    version++;
  }

  String jsonCells() => cells.join(',');

  void onReveal(FogListener fn) => _listeners.add(fn);

  bool isRevealed(String key) => cells.contains(key);

  /// Открыть круг вокруг точки. Возвращает число новых ячеек.
  int reveal(LatLng p, [double radius = revealRadius]) {
    final fresh = <String>[];
    for (final k in cellsInRadius(p, radius)) {
      if (cells.add(k)) fresh.add(k);
    }
    if (fresh.isNotEmpty) _changed(fresh);
    return fresh.length;
  }

  /// Открыть «коридор» между двумя точками — чтобы между редкими GPS-фиксами не оставалось дыр.
  int revealPath(LatLng a, LatLng b, [double radius = revealRadius]) {
    final d = distance(a, b);
    if (d > 2000) return reveal(b, radius); // телепорт или скачок GPS — не рисуем полосу через весь город
    final steps = (d / (radius * 0.6)).ceil().clamp(1, 1 << 20);
    final fresh = <String>[];
    for (var i = 1; i <= steps; i++) {
      for (final k in cellsInRadius(lerpLatLng(a, b, i / steps), radius)) {
        if (cells.add(k)) fresh.add(k);
      }
    }
    if (fresh.isNotEmpty) _changed(fresh);
    return fresh.length;
  }

  /// Площадь открытой территории, км².
  double get areaKm2 => cells.length * cell * cell / 1e6;

  void reset() {
    cells.clear();
    _store.saveBlob('fog.json', '');
    _changed(const []);
  }

  void flush() => _persist.flush();

  void _changed(List<String> fresh) {
    version++;
    _persist();
    for (final fn in _listeners) {
      fn(fresh);
    }
    notifyListeners();
  }
}
