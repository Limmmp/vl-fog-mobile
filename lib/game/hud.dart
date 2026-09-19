// Состояние интерфейса, которым управляет игра: реплики, баннеры, текущая цель, карточка задания.
// Экран подписывается на изменения и рисует; сама логика игры от виджетов не зависит.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'quests/schema.dart';

/// Кусок строки прогресса цели; [warn] — выделить красным.
typedef MetaPart = ({String text, bool warn});

class Objective {
  const Objective(this.title, this.text, this.meta);
  final String title;
  final String text;
  final List<MetaPart> meta;
}

class BannerMsg {
  BannerMsg(this.big, this.small, {this.fail = false});
  final String big;
  final String small;
  final bool fail;
}

class Hud extends ChangeNotifier {
  // --- Субтитры: очередь реплик ---
  final List<String> _subs = [];
  String? subtitle;
  Timer? _subTimer;

  void say(List<String> lines) {
    final add = lines.where((l) => l.isNotEmpty).toList();
    if (add.isEmpty) return;
    // Не копим длинный хвост старых реплик — новые события важнее
    if (_subs.length > 1) _subs.removeRange(0, _subs.length - 1);
    _subs.addAll(add);
    if (_subTimer == null) _nextSub();
  }

  void _nextSub() {
    subtitle = _subs.isEmpty ? null : _subs.removeAt(0);
    _subTimer = subtitle == null
        ? null
        : Timer(Duration(milliseconds: (1800 + subtitle!.length * 55).clamp(0, 9000)), _nextSub);
    notifyListeners();
  }

  // --- Баннер «МИССИЯ ПРОЙДЕНА» ---
  BannerMsg? banner;
  Timer? _bannerTimer;

  void showBanner(String big, String small, {bool fail = false}) {
    banner = BannerMsg(big, small, fail: fail);
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(milliseconds: 3200), () {
      banner = null;
      notifyListeners();
    });
    notifyListeners();
  }

  // --- Короткие уведомления ---
  final _toasts = StreamController<String>.broadcast();
  Stream<String> get toasts => _toasts.stream;
  void toast(String text) => _toasts.add(text);

  // --- Текущая цель ---
  Objective? objective;
  void setObjective(Objective? o) {
    objective = o;
    notifyListeners();
  }

  // --- Карточка задания ---
  Quest? offer;
  Completer<bool>? _offerAnswer;
  bool get offerOpen => offer != null;

  /// Показать предложение. true — взять, false — позже.
  Future<bool> ask(Quest q) {
    offer = q;
    _offerAnswer = Completer<bool>();
    notifyListeners();
    return _offerAnswer!.future;
  }

  void answer(bool yes) {
    final c = _offerAnswer;
    offer = null;
    _offerAnswer = null;
    notifyListeners();
    c?.complete(yes);
  }

  // --- Название района при входе ---
  String? areaName;
  Timer? _areaTimer;
  void showArea(String name) {
    areaName = name;
    _areaTimer?.cancel();
    _areaTimer = Timer(const Duration(milliseconds: 3500), () {
      areaName = null;
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _subTimer?.cancel();
    _bannerTimer?.cancel();
    _areaTimer?.cancel();
    _toasts.close();
    super.dispose();
  }
}
