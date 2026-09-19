// Формат квеста — общий контракт для всех генераторов (шаблоны, сюжет, локальная модель).
//
// «Сырой» квест — Map с id точек (такой же JSON, как в веб-версии):
// {
//   "title": "Краб-экспресс", "giver": "Артём Краб", "start": "n123456",
//   "intro": "…", "reward": {"cash": 800, "rep": 2},
//   "steps": [
//     {"type": "goto",    "poi": "n1", "text": "Иди к …", "say": ["Имя: реплика"], "timeLimit": 300},
//     {"type": "hold",    "poi": "n2", "seconds": 30, "text": "Жди у …"},
//     {"type": "tail",    "from": "n3", "to": "n4", "text": "Проследи за …"},
//     {"type": "collect", "pois": ["n5","n6"], "text": "Собери …"},
//     {"type": "explore", "cells": 60, "text": "Разведай район"}
//   ],
//   "outro": "Реплика по завершении"
// }
// resolveQuest() превращает id в точки и проверяет, что задание играбельно. Модель — недоверенный
// источник, поэтому всё приводится к типам и ограничивается разумными пределами.

import '../poi.dart';

sealed class Step {
  Step(this.text, this.say);
  final String text;
  final List<String> say;
}

class GotoStep extends Step {
  GotoStep(super.text, super.say, {required this.poi, required this.radius, this.timeLimit});
  final Poi poi;
  final double radius;
  final double? timeLimit; // секунды игрового времени
}

class HoldStep extends Step {
  HoldStep(super.text, super.say, {required this.poi, required this.radius, required this.seconds});
  final Poi poi;
  final double radius;
  final double seconds;
}

class TailStep extends Step {
  TailStep(super.text, super.say, {required this.from, required this.to, required this.speed});
  final Poi from;
  final Poi to;
  final double speed; // м/с
}

class CollectStep extends Step {
  CollectStep(super.text, super.say, {required this.pois, required this.radius});
  final List<Poi> pois;
  final double radius;
}

class ExploreStep extends Step {
  ExploreStep(super.text, super.say, {required this.cells});
  final int cells;
}

class Quest {
  Quest({
    required this.id,
    required this.storyId,
    required this.source,
    required this.title,
    required this.giver,
    required this.intro,
    required this.outro,
    required this.cash,
    required this.rep,
    required this.start,
    required this.steps,
  });

  final String id;
  final String? storyId;
  final String source; // story | template | ollama
  final String title;
  final String giver;
  final String intro;
  final List<String> outro;
  final int cash;
  final int rep;
  final Poi start;
  final List<Step> steps;
}

class QuestError implements Exception {
  QuestError(this.message);
  final String message;
  @override
  String toString() => 'QuestError: $message';
}

int _seq = 0;

Quest resolveQuest(Map<String, dynamic> raw, PoiService pois, {String source = 'template'}) {
  Poi p(Object? id) {
    final poi = id is String ? pois.get(id) : null;
    if (poi == null) throw QuestError('Неизвестная точка: $id');
    return poi;
  }

  final title = raw['title'];
  final rawSteps = raw['steps'];
  if (title is! String || title.isEmpty || rawSteps is! List || rawSteps.isEmpty) {
    throw QuestError('Нет title или steps');
  }

  final steps = <Step>[];
  for (var i = 0; i < rawSteps.length; i++) {
    final s = rawSteps[i];
    if (s is! Map) throw QuestError('Шаг $i не объект');
    final text = '${s['text'] ?? ''}';
    final say = _lines(s['say']);
    final radius = _num(s['radius']);
    switch (s['type']) {
      case 'goto':
        final tl = _num(s['timeLimit']);
        steps.add(GotoStep(text, say, poi: p(s['poi']), radius: radius > 0 ? radius : 35, timeLimit: tl > 0 ? tl : null));
      case 'hold':
        final sec = _num(s['seconds']);
        steps.add(HoldStep(text, say,
            poi: p(s['poi']), radius: radius > 0 ? radius : 35, seconds: (sec > 0 ? sec : 20).clamp(5, 600).toDouble()));
      case 'tail':
        final speed = _num(s['speed']);
        steps.add(TailStep(text, say, from: p(s['from']), to: p(s['to']), speed: speed > 0 ? speed : 1.3));
      case 'collect':
        final list = (s['pois'] is List ? s['pois'] as List : const []).map(p).toList();
        if (list.isEmpty) throw QuestError('Шаг $i: пустой collect');
        steps.add(CollectStep(text, say, pois: list, radius: radius > 0 ? radius : 30));
      case 'explore':
        final cells = _num(s['cells']);
        steps.add(ExploreStep(text, say, cells: (cells > 0 ? cells : 50).clamp(10, 2000).round()));
      default:
        throw QuestError('Шаг $i: неизвестный тип ${s['type']}');
    }
  }

  final Poi start = raw['start'] != null
      ? p(raw['start'])
      : switch (steps.first) {
          GotoStep(:final poi) || HoldStep(:final poi) => poi,
          TailStep(:final from) => from,
          CollectStep(:final pois) => pois.first,
          ExploreStep() => throw QuestError('Не определена точка выдачи'),
        };

  final reward = raw['reward'] is Map ? raw['reward'] as Map : const {};
  final cash = _num(reward['cash']);
  final rep = _num(reward['rep']);
  return Quest(
    id: raw['id'] as String? ?? '$source-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${_seq++}',
    storyId: raw['storyId'] as String?,
    source: source,
    title: _clip(title, 80),
    giver: _clip('${raw['giver'] ?? 'Незнакомец'}', 40),
    intro: '${raw['intro'] ?? ''}',
    outro: _lines(raw['outro']),
    cash: (cash > 0 ? cash : 300).round().clamp(0, 50000),
    rep: (rep > 0 ? rep : 1).round().clamp(0, 10),
    start: start,
    steps: steps,
  );
}

double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
String _clip(String s, int n) => s.length > n ? s.substring(0, n) : s;
List<String> _lines(Object? v) {
  if (v == null) return const [];
  return (v is List ? v : [v]).map((e) => '$e').where((e) => e.isNotEmpty).toList();
}
