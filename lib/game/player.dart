// Игрок: позиция, курс, режимы передвижения.
// sim — ходишь по нажатию на карту (на компьютере ещё WASD), игровое время ускорено ×8;
// gps — настоящая геопозиция, в том числе с выключенным экраном (foreground-сервис на Android).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:latlong2/latlong.dart';

import '../core/geo.dart';
import '../core/storage.dart';

const double _walk = 1.5; // м/с — шаг
const double _runMult = 4; // бег/самокат
const double simSpeedup = 8; // в симуляции игровое время ускорено, чтобы не ходить по 10 минут
const double _gpsMaxAccuracy = 60; // м — фиксы хуже этого игнорируем
// Между фиксами стрелка едет к последней точке, а не прыгает: за это время проходит ~2/3 пути
const double _gpsSmoothTau = 0.35; // с
const double _gpsJumpDist = 80; // м — дальше считаем скачком GPS и переносим сразу

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
  LatLng? _gpsTarget; // последний фикс: к нему плавно подтягиваем позицию в tick()
  double _gpsHeading = 0;

  /// Точность последнего фикса в метрах (null в симуляции). Рисуем кругом вокруг игрока.
  double? accuracy;
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
    if (mode == MoveMode.gps) {
      _followGps(dt);
      return;
    }
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

  /// Плавно подтягиваем позицию к последнему фиксу — иначе стрелка стоит и рывком догоняет.
  void _followGps(double dt) {
    final target = _gpsTarget;
    if (target == null) return;
    final d = distance(pos, target);
    if (d < 0.3) {
      _gpsTarget = null;
      return;
    }
    final t = 1 - math.exp(-dt / _gpsSmoothTau);
    _setPos(lerpLatLng(pos, target, t.clamp(0, 1)), _gpsHeading);
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
      await _ensureNotifications();
      walkTarget = null;
      final first = Completer<void>();
      _gps = Geolocator.getPositionStream(locationSettings: _settings()).listen(
        (p) {
          if (p.accuracy > _gpsMaxAccuracy && first.isCompleted) return;
          accuracy = p.accuracy;
          final at = LatLng(p.latitude, p.longitude);
          final h = p.heading.isFinite && p.heading > 0 ? p.heading : bearing(pos, at);
          _gpsHeading = h;
          // Первый фикс и скачки GPS переносят сразу, остальное сглаживаем в tick()
          if (!first.isCompleted || distance(pos, at) > _gpsJumpDist) {
            _gpsTarget = null;
            _setPos(at, h, jump: !first.isCompleted);
          } else {
            _gpsTarget = at;
          }
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
      _gpsTarget = null;
      accuracy = null;
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
          // distanceFilter: 0 — иначе система придерживает обновления («delivery blocked - too close»)
          // и стрелка догоняет рывками. Сглаживание делаем сами в _followGps().
          distanceFilter: 0,
          intervalDuration: const Duration(seconds: 1),
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
          distanceFilter: 0,
          activityType: ActivityType.fitness,
          pauseLocationUpdatesAutomatically: false,
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
        );
      default:
        return const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 3);
    }
  }

  /// Постоянное уведомление держит GPS живым при выключенном экране.
  /// Без разрешения на уведомления (Android 13+) система относится к фоновому сервису строже.
  Future<void> _ensureNotifications() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final status = await Permission.notification.status;
    if (status.isDenied) await Permission.notification.request();
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
