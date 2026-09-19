// Квестовый движок: метки-выдачи на карте, активное задание, шаги, награды.
// Движок только считает; метки, линию к цели и NPC рисует карта по данным отсюда.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/storage.dart';
import '../fog.dart';
import '../hud.dart';
import '../player.dart';
import '../poi.dart';
import '../route.dart';
import 'schema.dart';
import 'story.dart';
import 'templates.dart';

const double _offerRadius = 35; // м — подойди к метке, чтобы получить задание
const int _maxTemplateOffers = 3;
const double _offerDropDist = 1800; // м — дальние случайные метки исчезают
const double _tailLose = 170, _tailWarn = 120, _tailClose = 12, _tailStart = 150;
const _repStars = [2, 6, 12, 20, 32];

class Offer {
  Offer(this.quest);
  final Quest quest;
  bool declined = false;
}

/// Метка на карте и радаре.
enum BlipKind { offer, story, target, tail }

class Blip {
  const Blip(this.pos, this.kind, this.letter);
  final LatLng pos;
  final BlipKind kind;
  final String letter;
}

class _Active {
  _Active(this.quest);
  final Quest quest;
  int i = -1;
  // состояние шага
  double t = 0;
  LatLng? npc;
  bool started = false;
  double sus = 0;
  double walked = 0;
  GeoPath? path;
  Set<String> left = {};
  int base = 0;
}

class DoneQuest {
  DoneQuest(this.title, this.giver, this.cash);
  final String title;
  final String giver;
  final int cash;
  Map<String, dynamic> toJson() => {'title': title, 'giver': giver, 'cash': cash};
  factory DoneQuest.fromJson(Map<String, dynamic> j) =>
      DoneQuest(j['title'] as String, j['giver'] as String, (j['cash'] as num).toInt());
}

class QuestEngine extends ChangeNotifier {
  QuestEngine({required this.store, required this.pois, required this.fog, required this.player, required this.hud}) {
    final s = store.load<Map<String, dynamic>?>('quests', null) ?? const {};
    cash = (s['cash'] as num?)?.toInt() ?? 0;
    rep = (s['rep'] as num?)?.toInt() ?? 0;
    done = ((s['done'] as List?) ?? const []).map((e) => DoneQuest.fromJson(e as Map<String, dynamic>)).toList();
    storyDone = ((s['storyDone'] as List?) ?? const []).cast<String>().toList();
  }

  final Store store;
  final PoiService pois;
  final FogOfWar fog;
  final Player player;
  final Hud hud;
  final _rnd = math.Random();

  int cash = 0;
  int rep = 0;
  List<DoneQuest> done = [];
  List<String> storyDone = [];

  final List<Offer> offers = [];
  _Active? _active;
  bool _generating = false;
  bool _asking = false;
  double _offerClock = 4; // первые метки — через пару секунд после старта

  /// Текущая цель для линии, радара и стрелки у края экрана.
  LatLng? target;

  Quest? get activeQuest => _active?.quest;
  int get stars => _repStars.where((t) => rep >= t).length;

  // ---------- публичное ----------

  void tick(double dt) {
    final gdt = dt * player.timeScale; // игровое время
    _offerClock -= dt;
    if (_offerClock <= 0) {
      _offerClock = 2.5;
      _maintainOffers();
    }
    _checkOfferProximity();
    if (_active != null) _updateStep(gdt);
  }

  /// Начислить награду не за задание (например, за открытие района).
  void grant(int addCash, [int addRep = 0]) {
    cash += addCash;
    rep += addRep;
    _save();
    notifyListeners();
  }

  void reset() {
    _clearActive();
    offers.clear();
    cash = 0;
    rep = 0;
    done = [];
    storyDone = [];
    _save();
    notifyListeners();
  }

  /// Метки для карты и радара.
  List<Blip> blips() {
    final out = [
      for (final o in offers)
        Blip(o.quest.start.pos, o.quest.source == 'story' ? BlipKind.story : BlipKind.offer, o.quest.giver.isEmpty ? '?' : o.quest.giver.substring(0, 1)),
    ];
    final a = _active;
    if (a == null || a.i < 0 || a.i >= a.quest.steps.length) return out;
    switch (a.quest.steps[a.i]) {
      case GotoStep(:final poi) || HoldStep(:final poi):
        out.add(Blip(poi.pos, BlipKind.target, '!'));
      case TailStep():
        if (a.npc != null) out.add(Blip(a.npc!, BlipKind.tail, '◉'));
      case CollectStep(:final pois):
        for (final p in pois.where((p) => a.left.contains(p.id))) {
          out.add(Blip(p.pos, BlipKind.target, '\$'));
        }
      case ExploreStep():
        break;
    }
    return out;
  }

  /// Куда вести игрока: цель активного шага, а без задания — ближайшая метка-выдача.
  ({LatLng pos, bool isOffer})? guideTarget() {
    if (_active != null) return target == null ? null : (pos: target!, isOffer: false);
    LatLng? best;
    var bd = double.infinity;
    for (final o in offers) {
      final d = distance(player.pos, o.quest.start.pos);
      if (d < bd) {
        bd = d;
        best = o.quest.start.pos;
      }
    }
    return best == null ? null : (pos: best, isOffer: true);
  }

  // ---------- метки-выдачи ----------

  Future<void> _maintainOffers() async {
    final p = player.pos;
    var changed = false;

    // Сюжетные миссии: всегда видны, если открыты
    for (final s in story) {
      final id = s['storyId'] as String;
      if (storyDone.contains(id)) continue;
      if (!(s['requires'] as List).every(storyDone.contains)) continue;
      if (_active?.quest.storyId == id) continue;
      if (offers.any((o) => o.quest.storyId == id)) continue;
      try {
        offers.add(Offer(resolveQuest(s, pois, source: 'story')));
        changed = true;
      } on QuestError catch (e) {
        debugPrint('[story] $e');
      }
    }

    // Случайные метки далеко от игрока — убираем
    final before = offers.length;
    offers.removeWhere((o) => o.quest.source != 'story' && distance(p, o.quest.start.pos) > _offerDropDist);
    changed |= offers.length != before;
    if (changed) notifyListeners();

    final randomCount = offers.where((o) => o.quest.source != 'story').length;
    if (randomCount >= _maxTemplateOffers || _generating) return;

    _generating = true;
    try {
      final raw = generateFromTemplates(GenContext(player: player.pos, pois: pois, rnd: _rnd));
      if (raw == null) return;
      final q = resolveQuest(raw, pois, source: 'template');
      if (!offers.any((o) => o.quest.start.id == q.start.id || o.quest.title == q.title)) {
        offers.add(Offer(q));
        notifyListeners();
      }
    } on QuestError catch (e) {
      debugPrint('[template] $e');
    } finally {
      _generating = false;
    }
  }

  Future<void> _checkOfferProximity() async {
    if (_active != null || _asking || hud.offerOpen) return;
    final p = player.pos;
    for (final o in offers) {
      final d = distance(p, o.quest.start.pos);
      if (o.declined) {
        if (d > _offerRadius * 2.5) o.declined = false;
        continue;
      }
      if (d <= _offerRadius) {
        _asking = true;
        final yes = await hud.ask(o.quest);
        _asking = false;
        if (yes && _active == null) {
          offers.remove(o);
          _start(o.quest);
        } else {
          o.declined = true;
        }
        return;
      }
    }
  }

  // ---------- активное задание ----------

  void _start(Quest q) {
    _active = _Active(q);
    _nextStep();
  }

  void _nextStep() {
    final a = _active!;
    a.i++;
    if (a.i >= a.quest.steps.length) return _complete();

    final s = a.quest.steps[a.i];
    a
      ..t = 0
      ..npc = null
      ..started = false
      ..sus = 0
      ..walked = 0
      ..path = null;
    switch (s) {
      case TailStep(:final from, :final to):
        a.npc = from.pos;
        final step = a.i;
        // NPC тронется, когда маршрут по улицам будет готов
        walkRoute(from.pos, to.pos).then((path) {
          if (_active == a && a.i == step) a.path = path;
        });
        if (s.say.isNotEmpty) hud.say(s.say);
      case CollectStep(:final pois):
        a.left = pois.map((p) => p.id).toSet();
      case ExploreStep():
        a.base = fog.cells.length;
      case GotoStep() || HoldStep():
        break;
    }
    _drawObjective();
    notifyListeners();
  }

  void _updateStep(double gdt) {
    final a = _active!;
    final s = a.quest.steps[a.i];
    final p = player.pos;
    LatLng? tgt;

    switch (s) {
      case GotoStep(:final poi, :final radius, :final timeLimit):
        tgt = poi.pos;
        a.t += gdt;
        if (distance(p, poi.pos) <= radius) {
          hud.say(s.say);
          return _nextStep();
        }
        if (timeLimit != null && a.t > timeLimit) return _fail('Не успел');
      case HoldStep(:final poi, :final radius, :final seconds):
        tgt = poi.pos;
        if (distance(p, poi.pos) <= radius) {
          if (a.t == 0) hud.say(s.say);
          a.t += gdt;
          if (a.t >= seconds) return _nextStep();
        }
      case TailStep(:final speed):
        final npc = a.npc!;
        final d = distance(p, npc);
        tgt = npc;
        if (!a.started) {
          if (d <= _tailStart && a.path != null) {
            a.started = true;
            hud.toast('Цель двинулась. Держи дистанцию!');
          }
        } else {
          a.walked += speed * gdt;
          if (a.walked >= a.path!.length) return _nextStep();
          a.npc = a.path!.at(a.walked).pos;
          notifyListeners();
          if (d > _tailLose) return _fail('Цель потеряна');
          final realDt = gdt / player.timeScale;
          a.sus = d < _tailClose ? a.sus + realDt : math.max(0, a.sus - realDt / 2);
          if (a.sus > 3) return _fail('Тебя заметили');
        }
      case CollectStep(:final pois, :final radius):
        for (final poi in pois) {
          if (a.left.contains(poi.id) && distance(p, poi.pos) <= radius) {
            a.left.remove(poi.id);
            hud.toast('Забрал: ${poi.name}');
            notifyListeners();
          }
        }
        if (a.left.isEmpty) return _nextStep();
        // Ближайшая оставшаяся точка — для линии-подсказки
        final rest = pois.where((x) => a.left.contains(x.id)).toList()
          ..sort((x, y) => distance(p, x.pos).compareTo(distance(p, y.pos)));
        tgt = rest.first.pos;
      case ExploreStep(:final cells):
        if (fog.cells.length - a.base >= cells) return _nextStep();
    }
    if (tgt != target) {
      target = tgt;
      notifyListeners();
    }
    _drawObjective();
  }

  void _drawObjective() {
    final a = _active;
    if (a == null) return hud.setObjective(null);
    final s = a.quest.steps[a.i];
    final p = player.pos;
    final meta = <MetaPart>[(text: 'Шаг ${a.i + 1}/${a.quest.steps.length}', warn: false)];
    switch (s) {
      case GotoStep(:final poi, :final timeLimit):
        meta.add((text: formatDistance(distance(p, poi.pos)), warn: false));
        if (timeLimit != null) {
          final left = math.max(0.0, timeLimit - a.t);
          final txt = '${left ~/ 60}:${(left % 60).floor().toString().padLeft(2, '0')}';
          meta.add((text: txt, warn: left < 30));
        }
      case HoldStep(:final poi, :final radius, :final seconds):
        final inside = distance(p, poi.pos) <= radius;
        meta.add((
          text: inside ? '${a.t.floor()}/${seconds.round()} с' : 'Подойди ближе · ${formatDistance(distance(p, poi.pos))}',
          warn: false,
        ));
      case TailStep():
        final d = distance(p, a.npc!);
        if (!a.started) {
          meta.add((text: d <= _tailStart && a.path == null ? 'Цель вот-вот двинется…' : 'До цели ${formatDistance(d)}', warn: false));
        } else if (d > _tailWarn) {
          meta.add((text: 'Отстаёшь! ${formatDistance(d)}', warn: true));
        } else if (d < _tailClose * 1.5) {
          meta.add((text: 'Слишком близко!', warn: true));
        } else {
          meta.add((text: 'Дистанция ${formatDistance(d)}', warn: false));
        }
      case CollectStep():
        meta.add((text: 'Осталось ${a.left.length}', warn: false));
      case ExploreStep(:final cells):
        meta.add((text: '${fog.cells.length - a.base}/$cells', warn: false));
    }
    hud.setObjective(Objective(a.quest.title, s.text, meta));
  }

  void _complete() {
    final q = _active!.quest;
    cash += q.cash;
    rep += q.rep;
    done.add(DoneQuest(q.title, q.giver, q.cash));
    if (q.storyId != null) storyDone.add(q.storyId!);
    _save();
    _clearActive();
    hud.showBanner('Миссия пройдена', '+\$${money(q.cash)}');
    hud.say(q.outro);
    _offerClock = 0;
    notifyListeners();
  }

  void _fail(String reason) {
    final q = _active!.quest;
    _clearActive();
    hud.showBanner('Миссия провалена', reason, fail: true);
    // Задание можно повторить — возвращаем метку
    offers.add(Offer(q)..declined = true);
    notifyListeners();
  }

  void _clearActive() {
    _active = null;
    target = null;
    hud.setObjective(null);
  }

  void _save() => store.save('quests', {
        'cash': cash,
        'rep': rep,
        'done': done.map((d) => d.toJson()).toList(),
        'storyDone': storyDone,
      });
}

/// 12 500 — с неразрывным пробелом между разрядами, как в веб-версии.
String money(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}
