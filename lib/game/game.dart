// Сборка игры: хранилище, туман, игрок, места, задания, районы. Экран вызывает tick() каждый кадр.

import '../core/storage.dart';
import 'districts.dart';
import 'fog.dart';
import 'hud.dart';
import 'player.dart';
import 'poi.dart';
import 'quests/engine.dart';

class Game {
  Game._(this.store, this.fog, this.player, this.pois, this.hud, this.quests, this.districts);

  final Store store;
  final FogOfWar fog;
  final Player player;
  final PoiService pois;
  final Hud hud;
  final QuestEngine quests;
  final DistrictService districts;

  static Future<Game> start({Store? store}) async {
    store ??= await Store.open();
    final fog = FogOfWar(store);
    await fog.load();
    final player = Player(store);
    final pois = PoiService(store);
    final hud = Hud();
    final quests = QuestEngine(store: store, pois: pois, fog: fog, player: player, hud: hud);
    final districts = DistrictService(store, fog);
    final game = Game._(store, fog, player, pois, hud, quests, districts);

    districts.onMilestone = (d, m) {
      quests.grant(m.cash, m.rep);
      hud.showBanner(m.pct >= 90 ? 'Район открыт' : '${d.name}: ${m.pct}%', '${d.name} · +\$${money(m.cash)}');
    };

    player.onMove((pos, prev, jump) {
      if (jump || prev == null) {
        fog.reveal(pos);
      } else {
        fog.revealPath(prev, pos);
      }
      pois.ensureAround(pos);
      districts.update(pos);
    });
    fog.reveal(player.pos);
    pois.ensureAround(player.pos);
    districts.update(player.pos);
    // Заставку с названием района показываем только при переходе, не при запуске
    districts.onEnter = (d) {
      if (d != null) hud.showArea(d.name);
    };
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
    districts.reset();
    fog.reset();
    await store.clearAll();
    fog.reveal(player.pos);
  }
}
