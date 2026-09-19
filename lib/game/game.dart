// Сборка игры: хранилище, туман, игрок, места, задания. Экран вызывает tick() каждый кадр.

import '../core/storage.dart';
import 'fog.dart';
import 'hud.dart';
import 'player.dart';
import 'poi.dart';
import 'quests/engine.dart';

class Game {
  Game._(this.store, this.fog, this.player, this.pois, this.hud, this.quests);

  final Store store;
  final FogOfWar fog;
  final Player player;
  final PoiService pois;
  final Hud hud;
  final QuestEngine quests;

  static Future<Game> start({Store? store}) async {
    store ??= await Store.open();
    final fog = FogOfWar(store);
    await fog.load();
    final player = Player(store);
    final pois = PoiService(store);
    final hud = Hud();
    final quests = QuestEngine(store: store, pois: pois, fog: fog, player: player, hud: hud);
    final game = Game._(store, fog, player, pois, hud, quests);

    player.onMove((pos, prev, jump) {
      if (jump || prev == null) {
        fog.reveal(pos);
      } else {
        fog.revealPath(prev, pos);
      }
      pois.ensureAround(pos);
    });
    fog.reveal(player.pos);
    pois.ensureAround(player.pos);
    return game;
  }

  /// [dt] — секунды реального времени с прошлого кадра.
  void tick(double dt) {
    player.tick(dt);
    quests.tick(dt);
  }

  /// Сбросить отложенные сохранения на диск (приложение уходит в фон).
  void flush() {
    fog.flush();
    player.flush();
  }

  Future<void> resetProgress() async {
    quests.reset();
    fog.reset();
    await store.clearAll();
    fog.reveal(player.pos);
  }
}
