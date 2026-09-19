// Сборка игры: хранилище, туман, игрок. Экран вызывает tick() каждый кадр.

import '../core/storage.dart';
import 'fog.dart';
import 'player.dart';

class Game {
  Game._(this.store, this.fog, this.player);

  final Store store;
  final FogOfWar fog;
  final Player player;

  static Future<Game> start() async {
    final store = await Store.open();
    final fog = FogOfWar(store);
    await fog.load();
    final player = Player(store);
    final game = Game._(store, fog, player);

    player.onMove((pos, prev, jump) {
      if (jump || prev == null) {
        fog.reveal(pos);
      } else {
        fog.revealPath(prev, pos);
      }
    });
    fog.reveal(player.pos);
    return game;
  }

  /// [dt] — секунды реального времени с прошлого кадра.
  void tick(double dt) {
    player.tick(dt);
  }

  /// Сбросить отложенные сохранения на диск (приложение уходит в фон).
  void flush() {
    fog.flush();
    player.flush();
  }

  Future<void> resetProgress() async {
    fog.reset();
    await store.clearAll();
    fog.reveal(player.pos);
  }
}
