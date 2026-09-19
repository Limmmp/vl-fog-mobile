// Районы: к какому микрорайону относится точка и сколько его улиц открыто.
//
// В OSM микрорайоны материковой части Владивостока почти не размечены полигонами,
// поэтому район — «ближайший центр» (диаграмма Вороного) не дальше maxR.
// Прогресс считается не по площади (в неё попадали бы море и сопки), а по «уличным»
// ячейкам тумана: через них проходит пешеходная дорога из OSM. 100 % — прошёл все улицы района.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/geo.dart';
import '../core/storage.dart';
import 'fog.dart';

class District {
  const District(this.id, this.name, this.pos);
  final String id;
  final String name;
  final LatLng pos;
}

/// Центры микрорайонов. Координаты — по остановкам/станциям из OSM (Nominatim), ±300 м.
/// Остров Русский и Щитовая — по точкам place=suburb из OSM.
const districts = [
  District('center', 'Центр', LatLng(43.1165, 131.8860)),
  District('eagle', 'Орлиная сопка', LatLng(43.1225, 131.8950)),
  District('egersheld', 'Эгершельд', LatLng(43.0952, 131.8647)),
  District('churkin', 'Чуркин', LatLng(43.0960, 131.9100)),
  District('zmeinka', 'Змеинка', LatLng(43.0859, 131.8939)),
  District('dalzavod', 'Дальзавод', LatLng(43.1130, 131.9120)),
  District('gniloy', 'Гнилой Угол', LatLng(43.1305, 131.9080)),
  District('rechka1', 'Первая Речка', LatLng(43.1371, 131.9027)),
  District('morgorodok', 'Моргородок', LatLng(43.1477, 131.9045)),
  District('rechka2', 'Вторая Речка', LatLng(43.1640, 131.9080)),
  District('zarya', 'Заря', LatLng(43.1802, 131.9205)),
  District('chaika', 'Чайка', LatLng(43.1960, 131.9210)),
  District('sedanka', 'Седанка', LatLng(43.2132, 131.9567)),
  District('okeanskaya', 'Океанская', LatLng(43.2352, 132.0071)),
  District('sadgorod', 'Садгород', LatLng(43.2627, 132.0407)),
  District('snegovaya', 'Снеговая Падь', LatLng(43.1633, 131.9569)),
  District('balyaeva', 'Баляева', LatLng(43.1280, 131.9420)),
  District('lugovaya', 'Луговая', LatLng(43.1110, 131.9380)),
  District('zeleny', 'Зелёный Угол', LatLng(43.1190, 131.9650)),
  District('neybuta', 'Нейбута', LatLng(43.1040, 131.9603)),
  District('borisenko', 'Борисенко', LatLng(43.0977, 131.9543)),
  District('tikhaya', 'Тихая', LatLng(43.0930, 131.9700)),
  District('patrokl', 'Патрокл', LatLng(43.0780, 131.9620)),
  District('shitovaya', 'Щитовая', LatLng(43.1268, 132.0149)),
  District('rybachy', 'Рыбачий', LatLng(43.1347, 132.0378)),
  District('ajax', 'Аякс (ДВФУ)', LatLng(43.0281, 131.8941)),
  District('melkovodny', 'Мелководный', LatLng(43.0170, 131.8877)),
  District('paris', 'Парис', LatLng(43.0115, 131.8967)),
  District('ekipazhny', 'Экипажный', LatLng(43.0106, 131.8705)),
  District('minka', 'Минка', LatLng(43.0300, 131.8734)),
  District('shigino', 'Шигино', LatLng(43.0351, 131.8531)),
  District('ket', 'КЭТ', LatLng(43.0265, 131.8594)),
  District('kanal', 'Канал', LatLng(43.0576, 131.8501)),
  District('pospelovo', 'Поспелово', LatLng(43.0581, 131.8835)),
  District('podnozhye', 'Подножье', LatLng(43.0448, 131.8227)),
  District('rynda', 'Рында', LatLng(43.0323, 131.8049)),
  District('zhitkova', 'Житкова', LatLng(43.0232, 131.9283)),
];

const double _maxR = 1800; // м — дальше любого центра считаем «окраиной» без района
const _retry = Duration(minutes: 2); // до повторной загрузки улиц после ошибки Overpass
final _byId = {for (final d in districts) d.id: d};

class Milestone {
  const Milestone(this.pct, this.cash, this.rep);
  final int pct;
  final int cash;
  final int rep;
}

/// Пороги открытия и награды. 90 % — «район открыт»: часть улиц всегда за заборами.
const milestones = [Milestone(25, 200, 0), Milestone(50, 500, 1), Milestone(75, 1000, 1), Milestone(90, 2500, 2)];

const _overpass = ['https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter'];
// Пешеходные улицы. Тротуары и переходы дублируют проезжую часть, проезды к парковкам — мусор.
const _highways = 'primary|secondary|tertiary|unclassified|residential|living_street|pedestrian|footway|steps|service';

/// Район точки или null.
District? districtAt(LatLng p) {
  District? best;
  var bd = _maxR;
  for (final d in districts) {
    final dist = distance(p, d.pos);
    if (dist < bd) {
      bd = dist;
      best = d;
    }
  }
  return best;
}

class DistrictService extends ChangeNotifier {
  DistrictService(this._store, this._fog) {
    _reached = (_store.load<Map<String, dynamic>?>('districtMilestones', null) ?? {})
        .map((k, v) => MapEntry(k, (v as num).toInt()));
    _fog.onReveal(_onReveal);
  }

  final Store _store;
  final FogOfWar _fog;
  final Map<String, Set<String>> _streets = {}; // id → ключи уличных ячеек
  final Map<String, int> _explored = {}; // id → сколько из них открыто
  late Map<String, int> _reached; // id → последний достигнутый порог, %
  final Map<String, DateTime> _retryAt = {};
  String? _loadingId;

  District? current;

  /// Вход в район (null — вышел за пределы всех районов).
  void Function(District? d)? onEnter;

  /// Пройден порог открытия (награды за несколько порогов сразу суммированы).
  void Function(District d, Milestone m)? onMilestone;

  bool isLoading(String id) => _loadingId == id;

  /// Вызывать при движении игрока.
  void update(LatLng p) {
    final d = districtAt(p);
    if (d?.id != current?.id) {
      current = d;
      onEnter?.call(d);
      notifyListeners();
    }
    if (d != null) _ensure(d);
  }

  /// Процент открытия района или null, если улицы ещё не загружены.
  double? percent(String id) {
    final total = _streets[id]?.length ?? 0;
    if (total == 0) return null;
    return 100 * (_explored[id] ?? 0) / total;
  }

  /// Районы, где игрок уже бывал (улицы в кэше), по убыванию прогресса.
  Future<List<({District d, double pct})>> summary() async {
    for (final d in districts) {
      if (!_streets.containsKey(d.id)) await _fromCache(d);
    }
    final out = [
      for (final d in districts)
        if (_streets.containsKey(d.id)) (d: d, pct: percent(d.id) ?? 0),
    ]..sort((a, b) => b.pct.compareTo(a.pct));
    return out;
  }

  void reset() {
    _reached = {};
    _store.save('districtMilestones', _reached);
    for (final id in _streets.keys) {
      _recount(id);
    }
    notifyListeners();
  }

  // ---------- внутреннее ----------

  void _onReveal(List<String> fresh) {
    if (fresh.isEmpty) {
      // Туман сброшен — пересчитываем всё
      for (final id in _streets.keys) {
        _recount(id);
      }
      notifyListeners();
      return;
    }
    var changed = false;
    for (final e in _streets.entries) {
      var n = 0;
      for (final k in fresh) {
        if (e.value.contains(k)) n++;
      }
      if (n == 0) continue;
      _explored[e.key] = (_explored[e.key] ?? 0) + n;
      _checkMilestones(_byId[e.key]!);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void _recount(String id) {
    _explored[id] = _streets[id]!.where(_fog.cells.contains).length;
  }

  void _setStreets(District d, Set<String> set) {
    _streets[d.id] = set;
    _recount(d.id);
    // Уже пройденные пороги не награждаем повторно — только фиксируем
    if (!_reached.containsKey(d.id)) {
      final pct = percent(d.id) ?? 0;
      _reached[d.id] = milestones.where((m) => pct >= m.pct).map((m) => m.pct).fold(0, math.max);
      _store.save('districtMilestones', _reached);
    }
    notifyListeners();
  }

  void _checkMilestones(District d) {
    final pct = percent(d.id);
    if (pct == null) return;
    final prev = _reached[d.id] ?? 0;
    final crossed = milestones.where((m) => m.pct > prev && pct >= m.pct).toList();
    if (crossed.isEmpty) return;
    final m = Milestone(
      crossed.last.pct,
      crossed.fold(0, (s, x) => s + x.cash),
      crossed.fold(0, (s, x) => s + x.rep),
    );
    _reached[d.id] = m.pct;
    _store.save('districtMilestones', _reached);
    onMilestone?.call(d, m);
  }

  Future<bool> _fromCache(District d) async {
    final cached = await _store.loadBlob('streets_${d.id}.txt');
    if (cached == null || cached.isEmpty) return false;
    _setStreets(d, decodeKeys(cached).toSet());
    return true;
  }

  Future<void> _ensure(District d) async {
    if (_streets.containsKey(d.id) || _loadingId != null) return;
    final retry = _retryAt[d.id];
    if (retry != null && DateTime.now().isBefore(retry)) return;
    _loadingId = d.id;
    notifyListeners();
    try {
      if (await _fromCache(d)) return;
      final set = await _fetchStreets(d);
      await _store.saveBlob('streets_${d.id}.txt', encodeKeys(set));
      _setStreets(d, set);
    } catch (e) {
      debugPrint('[districts] улицы района «${d.name}» не загрузились, повторю через ${_retry.inSeconds} с: $e');
      _retryAt[d.id] = DateTime.now().add(_retry); // Overpass часто перегружен — не долбим его подряд
    } finally {
      _loadingId = null;
      notifyListeners();
    }
  }
}

/// Скачать пешеходные улицы района из Overpass и превратить их в ключи ячеек тумана.
Future<Set<String>> _fetchStreets(District d) async {
  final bb = _regionBbox(d);
  final q = '''[out:json][timeout:60];
way["highway"~"^($_highways)\$"]["access"!~"^(private|no)\$"]["foot"!="no"]["footway"!~"^(sidewalk|crossing)\$"]["service"!~"^(parking_aisle|driveway|drive-through)\$"](${bb.join(',')});
out skel geom qt;''';
  Object? lastErr;
  for (final url in _overpass) {
    try {
      final res = await http
          .post(Uri.parse(url), body: {'data': q}, headers: {'User-Agent': 'vl-fog/1.0 (street game)'})
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      // Растеризация сотен тысяч точек — в отдельном изоляте, чтобы не дёргался интерфейс
      return compute(_rasterize, (json['elements'] as List, d.id));
    } catch (e) {
      lastErr = e;
    }
  }
  throw lastErr ?? Exception('Overpass недоступен');
}

/// Ячейки, через которые проходят линии дорог и которые принадлежат району.
Set<String> _rasterize((List<dynamic>, String) args) {
  final (ways, id) = args;
  final out = <String>{};
  final owner = <String, String?>{}; // ключ ячейки → район (у соседних точек одна ячейка)
  const step = 8.0; // м — шаг выборки вдоль линии, меньше ячейки
  void add(LatLng p) {
    final c = cellOf(p);
    final k = cellKey(c.row, c.col);
    final o = owner.putIfAbsent(k, () => districtAt(p)?.id);
    if (o == id) out.add(k);
  }

  for (final w in ways) {
    final g = (w as Map)['geometry'] as List?;
    if (g == null || g.isEmpty) continue;
    LatLng pt(Object? e) => LatLng(((e as Map)['lat'] as num).toDouble(), (e['lon'] as num).toDouble());
    var a = pt(g.first);
    add(a);
    for (var i = 1; i < g.length; i++) {
      final b = pt(g[i]);
      final n = (distance(a, b) / step).ceil();
      for (var j = 1; j <= n; j++) {
        add(lerpLatLng(a, b, j / n));
      }
      a = b;
    }
  }
  return out;
}

/// Рамка [юг, запад, север, восток] вокруг области района: проверяем сетку 100 м в пределах maxR.
List<String> _regionBbox(District d) {
  final dLat = _maxR / 111320;
  final dLon = _maxR / (111320 * math.cos(d.pos.latitude * math.pi / 180));
  var s = double.infinity, w = double.infinity, n = -double.infinity, e = -double.infinity;
  final steps = (_maxR / 100).ceil();
  for (var i = -steps; i <= steps; i++) {
    for (var j = -steps; j <= steps; j++) {
      final p = LatLng(d.pos.latitude + dLat * i / steps, d.pos.longitude + dLon * j / steps);
      if (districtAt(p)?.id != d.id) continue;
      s = math.min(s, p.latitude);
      n = math.max(n, p.latitude);
      w = math.min(w, p.longitude);
      e = math.max(e, p.longitude);
    }
  }
  const padLat = 100 / 111320;
  final padLon = padLat / math.cos(d.pos.latitude * math.pi / 180);
  return [s - padLat, w - padLon, n + padLat, e + padLon].map((v) => v.toStringAsFixed(5)).toList();
}

// Компактное хранение: "row:c0,d1,d2;row:…" — столбцы по возрастанию, дальше разности.
// Формат тот же, что в веб-версии (districts.js), кэш улиц совместим.
@visibleForTesting
String encodeKeys(Set<String> set) {
  final rows = <String, List<int>>{};
  for (final k in set) {
    final i = k.indexOf(':');
    rows.putIfAbsent(k.substring(0, i), () => []).add(int.parse(k.substring(i + 1)));
  }
  final parts = <String>[];
  rows.forEach((r, cols) {
    cols.sort();
    parts.add('$r:${[for (var i = 0; i < cols.length; i++) i == 0 ? cols[i] : cols[i] - cols[i - 1]].join(',')}');
  });
  return parts.join(';');
}

@visibleForTesting
List<String> decodeKeys(String str) {
  final out = <String>[];
  if (str.isEmpty) return out;
  for (final part in str.split(';')) {
    final i = part.indexOf(':');
    final r = part.substring(0, i);
    var c = 0;
    final vals = part.substring(i + 1).split(',');
    for (var j = 0; j < vals.length; j++) {
      c = j == 0 ? int.parse(vals[j]) : c + int.parse(vals[j]);
      out.add('$r:$c');
    }
  }
  return out;
}
