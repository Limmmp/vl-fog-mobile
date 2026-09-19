// Игрок: позиция, курс, режимы передвижения.
// sim — ходишь по нажатию на карту (на компьютере ещё WASD), игровое время ускорено ×8;
// gps — настоящая геопозиция, в том числе с выключенным экраном (foreground-сервис на Android).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../core/geo.dart';
import '../core/storage.dart';

const double _walk = 1.5; // м/с — шаг
const double _runMult = 4; // бег/самокат
const double simSpeedup = 8; // в симуляции игровое время ускорено, чтобы не ходить по 10 минут
const double _gpsMaxAccuracy = 60; // м — фиксы хуже этого игнорируем

/// Старт по умолчанию — Центральная площадь Владивостока.
const defaultStart = LatLng(43.1155, 131.8855);

enum MoveMode { sim, gps }

/// (новая позиция, предыдущая, скачок без «коридора» тумана)
typedef MoveListener = void Function(LatLng pos, LatLng? prev, bool jump);

class Player extends ChangeNotifier {
  Player(this._store) {
    final saved = _store.load<List<dynamic>?>('player', null);
    pos = saved != null && saved.length == 2
        ? LatLng((saved[0] as num).toDouble(), (saved[1] as num).toDouble())
        : defaultStart;
    _persist = Debouncer(const Duration(seconds: 1), () => _store.save('player', [pos.latitude, pos.longitude]));
  }

  final Store _store;
  late LatLng pos;
  double heading = 0;
  MoveMode mode = MoveMode.sim;
  LatLng? walkTarget;
  bool running = false;
  final Set<String> keys = {}; // up/down/left/right — клавиатура в симуляции
  final List<MoveListener> _listeners = [];
  late final Debouncer _persist;
  StreamSubscription<Position>? _gps;

  /// Во сколько раз игровое время быстрее реального (для таймеров и NPC).
  double get timeScale => mode == MoveMode.sim ? simSpeedup : 1;

  void onMove(MoveListener fn) => _listeners.add(fn);

  /// Нажатие на карту в симуляции — идти туда.
  void walkTo(LatLng p) {
    if (mode == MoveMode.sim) walkTarget = p;
  }

  /// Вызывается игровым циклом. [dt] — секунды реального времени.
  void tick(double dt) {
    if (mode != MoveMode.sim) return;
    final speed = _walk * (running ? _runMult : 1);
    var dx = 0.0, dy = 0.0;
    if (keys.contains('up')) dy += 1;
    if (keys.contains('down')) dy -= 1;
    if (keys.contains('right')) dx += 1;
    if (keys.contains('left')) dx -= 1;

    final step = speed * dt * simSpeedup;
    if (dx != 0 || dy != 0) {
      walkTarget = null;
      final deg = math.atan2(dx, dy) * 180 / math.pi;
      _setPos(move(pos, deg, step), deg);
    } else if (walkTarget != null) {
      final d = distance(pos, walkTarget!);
      if (d <= step) {
        _setPos(walkTarget!, heading);
        walkTarget = null;
      } else {
        final deg = bearing(pos, walkTarget!);
        _setPos(move(pos, deg, step), deg);
      }
    }
  }

  void teleport(LatLng p) => _setPos(p, heading, jump: true);

  void _setPos(LatLng p, double h, {bool jump = false}) {
    final prev = pos;
    pos = p;
    heading = h;
    _persist();
    for (final fn in _listeners) {
      fn(pos, prev, jump);
    }
    notifyListeners();
  }

  /// Переключить режим. Бросает [GpsException] с понятным текстом, если GPS недоступен.
  Future<void> setMode(MoveMode next) async {
    if (next == MoveMode.gps) {
      await _ensurePermission();
      walkTarget = null;
      final first = Completer<void>();
      _gps = Geolocator.getPositionStream(locationSettings: _settings()).listen(
        (p) {
          if (p.accuracy > _gpsMaxAccuracy && first.isCompleted) return;
          final at = LatLng(p.latitude, p.longitude);
          final h = p.heading.isFinite && p.heading > 0 ? p.heading : bearing(pos, at);
          _setPos(at, h, jump: !first.isCompleted);
          if (!first.isCompleted) first.complete();
        },
        onError: (Object e) {
          if (!first.isCompleted) first.completeError(GpsException('Не удалось определить позицию: $e'));
        },
      );
      try {
        await first.future.timeout(const Duration(seconds: 25));
      } on TimeoutException {
        await _gps?.cancel();
        _gps = null;
        throw GpsException('GPS не ответил вовремя — попробуй на улице');
      } catch (_) {
        await _gps?.cancel();
        _gps = null;
        rethrow;
      }
      mode = MoveMode.gps;
    } else {
      await _gps?.cancel();
      _gps = null;
      mode = MoveMode.sim;
    }
    notifyListeners();
  }

  LocationSettings _settings() {
    if (kIsWeb) return const LocationSettings(accuracy: LocationAccuracy.best);
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 3,
          intervalDuration: const Duration(seconds: 2),
          // Уведомление держит GPS живым, пока экран выключен и телефон в кармане
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'Туман открывается',
            notificationText: 'Игра отмечает, где ты прошёл',
            notificationChannelName: 'Прогулка',
            enableWakeLock: true,
            setOngoing: true,
          ),
        );
      case TargetPlatform.iOS:
        return AppleSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 3,
          activityType: ActivityType.fitness,
          pauseLocationUpdatesAutomatically: false,
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
        );
      default:
        return const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 3);
    }
  }

  Future<void> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw GpsException('Включи геолокацию в настройках телефона');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied) throw GpsException('Без доступа к геопозиции туман не откроется');
    if (perm == LocationPermission.deniedForever) {
      throw GpsException('Доступ к геопозиции запрещён — разреши его в настройках приложения');
    }
  }

  void flush() => _persist.flush();

  @override
  void dispose() {
    _gps?.cancel();
    super.dispose();
  }
}

class GpsException implements Exception {
  GpsException(this.message);
  final String message;
  @override
  String toString() => message;
}
