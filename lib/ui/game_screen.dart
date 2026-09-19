// Главный экран: карта (подложка, туман, метки, игрок), HUD и кнопки. Здесь же игровой цикл.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../game/game.dart';
import '../game/player.dart';
import '../map/basemap.dart';
import '../map/fog_layer.dart';
import '../map/quest_layers.dart';
import '../map/tile_cache.dart';
import 'overlays.dart';
import 'palette.dart';
import 'widgets.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.game, required this.basemap});

  final Game game;
  final Basemap basemap;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  final _map = MapController();
  late final Ticker _ticker;
  late final AppLifecycleListener _lifecycle;
  Duration _last = Duration.zero;
  bool _follow = true;
  bool _modeBusy = false;
  bool _mapReady = false;
  StreamSubscription<String>? _toasts;

  Game get game => widget.game;
  Player get player => game.player;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_frame)..start();
    player.onMove((pos, _, _) {
      if (_follow && _mapReady) _map.move(pos, _map.camera.zoom);
    });
    // Ушли в фон — сохраняем сразу, система может выгрузить приложение
    _lifecycle = AppLifecycleListener(onPause: game.flush, onDetach: game.flush);
    _toasts = game.hud.toasts.listen((t) {
      if (mounted) toast(context, t);
    });
    // Первое знакомство
    if (!game.store.load<bool>('seenIntro', false)) {
      game.hud.say([
        'Владивосток. Туман пришёл с залива и забрал с собой всю карту.',
        'Жёлтые метки — люди, у которых есть для тебя работа. Иди к ним.',
        'Дядя Гоша ждёт на Центральной площади.',
      ]);
      game.store.save('seenIntro', true);
    }
  }

  void _frame(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = now;
    game.tick(dt);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _lifecycle.dispose();
    _toasts?.cancel();
    super.dispose();
  }

  Future<void> _toggleMode() async {
    setState(() => _modeBusy = true);
    final next = player.mode == MoveMode.sim ? MoveMode.gps : MoveMode.sim;
    try {
      await player.setMode(next);
      _follow = true;
      _map.move(player.pos, _map.camera.zoom < 16.5 ? 16.5 : _map.camera.zoom);
      if (mounted) toast(context, next == MoveMode.gps ? 'GPS включён. Иди гулять!' : 'Режим симуляции');
    } on GpsException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => _modeBusy = false);
    }
  }

  void _center() {
    _follow = true;
    _map.move(player.pos, _map.camera.zoom < 16 ? 16 : _map.camera.zoom);
  }

  // Клавиатура — только для симуляции на компьютере/в браузере
  static final _keyMap = {
    LogicalKeyboardKey.keyW: 'up', LogicalKeyboardKey.arrowUp: 'up',
    LogicalKeyboardKey.keyS: 'down', LogicalKeyboardKey.arrowDown: 'down',
    LogicalKeyboardKey.keyA: 'left', LogicalKeyboardKey.arrowLeft: 'left',
    LogicalKeyboardKey.keyD: 'right', LogicalKeyboardKey.arrowRight: 'right',
  };

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e.logicalKey == LogicalKeyboardKey.shiftLeft || e.logicalKey == LogicalKeyboardKey.shiftRight) {
      player.running = e is! KeyUpEvent;
      return KeyEventResult.handled;
    }
    final k = _keyMap[e.logicalKey];
    if (k == null) return KeyEventResult.ignored;
    if (e is KeyUpEvent) {
      player.keys.remove(k);
    } else {
      player.keys.add(k);
      _follow = true;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Palette.ground,
        body: Stack(
          children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: player.pos,
                initialZoom: 16.5,
                minZoom: 12,
                maxZoom: 19,
                backgroundColor: Palette.ground,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                onMapReady: () => _mapReady = true,
                onTap: (_, latLng) => player.walkTo(latLng),
                onPositionChanged: (_, hasGesture) {
                  if (hasGesture) _follow = false;
                },
              ),
              children: [
                VectorTileLayer(
                  tileProviders: widget.basemap.providers,
                  theme: widget.basemap.theme,
                  maximumZoom: 19,
                  cacheFolder: tileCacheFolder as dynamic,
                  fileCacheTtl: const Duration(days: 60),
                  fileCacheMaximumSizeInBytes: 200 * 1024 * 1024,
                ),
                FogLayer(fog: game.fog),
                GuideLineLayer(quests: game.quests, player: player),
                QuestBlipLayer(quests: game.quests),
                ListenableBuilder(
                  listenable: player,
                  builder: (context, _) => MarkerLayer(markers: [
                    Marker(
                      point: player.pos,
                      width: 30,
                      height: 30,
                      child: Transform.rotate(
                        angle: player.heading * 3.141592653589793 / 180,
                        child: const CustomPaint(painter: PlayerArrowPainter()),
                      ),
                    ),
                  ]),
                ),
              ],
            ),

            // HUD — справа сверху, как в GTA
            Positioned(right: 16, top: safe.top + 10, child: HudPanel(game: game)),

            // Цель — под HUD, чтобы на узком экране они не наезжали друг на друга
            Positioned(left: 16, right: 16, top: safe.top + 104, child: Align(alignment: Alignment.topLeft, child: ObjectiveBox(hud: game.hud))),

            // Субтитры — над кнопками
            Positioned(left: 16, right: 16, bottom: safe.bottom + 80, child: SubtitleView(hud: game.hud)),

            Positioned.fill(child: BannerView(hud: game.hud)),

            // Кнопки — внизу, под большой палец
            Positioned(
              left: 16,
              bottom: safe.bottom + 22,
              child: ListenableBuilder(
                listenable: player,
                builder: (context, _) => Row(children: [
                  GameChip(
                    label: _modeBusy
                        ? 'Ищу GPS…'
                        : player.mode == MoveMode.gps ? 'Режим: GPS' : 'Режим: симуляция',
                    color: player.mode == MoveMode.gps ? Palette.blue : null,
                    onTap: _modeBusy ? null : _toggleMode,
                  ),
                  const SizedBox(width: 6),
                  GameChip(icon: Icons.my_location, tooltip: 'Центрировать на игроке', onTap: _center),
                  const SizedBox(width: 6),
                  GameChip(label: 'Задания', onTap: () => showJournal(context, game)),
                ]),
              ),
            ),

            // Источники карты — обязательная подпись, мелко в углу
            Positioned(
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  color: const Color(0x8C000000),
                  padding: EdgeInsets.fromLTRB(6, 2, 6, 2 + safe.bottom),
                  child: const Text('© OpenStreetMap · OpenMapTiles · OpenFreeMap',
                      style: TextStyle(color: Color(0xFF8A95A0), fontSize: 9)),
                ),
              ),
            ),

            // Карточка задания — поверх кнопок
            Positioned(
              left: 16,
              right: 16,
              bottom: safe.bottom + 16,
              child: Center(child: OfferCard(hud: game.hud)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Стрелка игрока: белая, с тёмной обводкой, смотрит вверх (поворот — снаружи).
class PlayerArrowPainter extends CustomPainter {
  const PlayerArrowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 28;
    final path = Path()
      ..moveTo(14 * s, 2 * s)
      ..lineTo(24 * s, 25 * s)
      ..lineTo(14 * s, 19 * s)
      ..lineTo(4 * s, 25 * s)
      ..close();
    canvas.drawShadow(path, Colors.black, 3, false);
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF111111)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * s
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(PlayerArrowPainter old) => false;
}
