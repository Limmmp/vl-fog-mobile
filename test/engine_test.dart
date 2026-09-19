// Прохождение сюжетных миссий «на автомате»: телепортируем игрока по точкам и крутим тики.
// Сеть в тестах недоступна, поэтому маршрут NPC строится по прямой (fallback) — это тоже проверка.

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vl_fog/core/geo.dart';
import 'package:vl_fog/core/storage.dart';
import 'package:vl_fog/game/game.dart';
import 'package:vl_fog/game/quests/engine.dart';

Future<Game> _newGame() async {
  SharedPreferences.setMockInitialValues({});
  final game = await Game.start(store: await Store.inMemory());
  game.hud.say([]); // субтитры в тестах не нужны
  return game;
}

/// Крутить игру, пока условие не выполнится (игровые секунды ускорены ×8 в симуляции).
Future<void> _run(Game g, bool Function() until, {int maxTicks = 20000, void Function()? each}) async {
  for (var i = 0; i < maxTicks && !until(); i++) {
    each?.call();
    g.tick(0.1);
    if (i % 50 == 0) await Future<void>.delayed(Duration.zero); // дать отработать async (маршруты, ответ на карточку)
  }
}

Future<void> _acceptOfferAt(Game g, LatLng at) async {
  g.player.teleport(at);
  await _run(g, () => g.hud.offerOpen, maxTicks: 200);
  expect(g.hud.offerOpen, isTrue, reason: 'карточка задания должна открыться у метки');
  g.hud.answer(true);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('сюжетная метка появляется и первая миссия проходится', () async {
    final g = await _newGame();
    await _run(g, () => g.quests.offers.any((o) => o.quest.storyId == 'gt1'), maxTicks: 200);
    final gt1 = g.quests.offers.firstWhere((o) => o.quest.storyId == 'gt1').quest;

    await _acceptOfferAt(g, gt1.start.pos);
    expect(g.quests.activeQuest?.title, 'Возвращение на Миллионку');

    // goto Арбат → goto Миллионка → hold 20 с → goto Спортивная гавань (с лимитом 7 минут)
    g.player.teleport(g.pois.get('lm:arbat')!.pos);
    await _run(g, () => g.hud.objective?.text == 'Сверни во дворы Миллионки', maxTicks: 10);
    g.player.teleport(g.pois.get('lm:millionka')!.pos);
    await _run(g, () => g.hud.objective?.text == 'Спускайся к Спортивной гавани', maxTicks: 200);
    expect(g.hud.objective?.text, 'Спускайся к Спортивной гавани');
    g.player.teleport(g.pois.get('lm:sport')!.pos);
    await _run(g, () => g.quests.activeQuest == null, maxTicks: 10);

    expect(g.quests.cash, 500);
    expect(g.quests.storyDone, ['gt1']);
    expect(g.hud.banner?.big, 'Миссия пройдена');
  });

  test('слежка: NPC идёт к цели, игрок держит дистанцию — миссия засчитана', () async {
    final g = await _newGame();
    g.quests.storyDone.add('gt1'); // открыть вторую миссию
    await _run(g, () => g.quests.offers.any((o) => o.quest.storyId == 'gt2'), maxTicks: 200);
    final gt2 = g.quests.offers.firstWhere((o) => o.quest.storyId == 'gt2').quest;
    await _acceptOfferAt(g, gt2.start.pos);

    // Держимся в 40 м позади NPC
    LatLng? npc() {
      final b = g.quests.blips().where((b) => b.kind == BlipKind.tail);
      return b.isEmpty ? null : b.first.pos;
    }

    final station = g.pois.get('lm:station')!.pos;
    await _run(g, () => g.hud.objective?.text != 'Следи за матросом в жёлтой куртке', each: () {
      final n = npc();
      if (n != null) g.player.teleport(move(n, bearing(station, n), 40));
    });
    expect(g.hud.banner?.fail ?? false, isFalse, reason: 'слежка не должна провалиться: ${g.hud.banner?.small}');
    expect(g.hud.objective?.text, 'Матрос кому-то звонит. Слушай');
  });

  test('слежка проваливается, если отстать', () async {
    final g = await _newGame();
    g.quests.storyDone.add('gt1');
    await _run(g, () => g.quests.offers.any((o) => o.quest.storyId == 'gt2'), maxTicks: 200);
    final gt2 = g.quests.offers.firstWhere((o) => o.quest.storyId == 'gt2').quest;
    await _acceptOfferAt(g, gt2.start.pos);
    // Стоим на месте — NPC уходит дальше 170 м
    await _run(g, () => g.quests.activeQuest == null);
    expect(g.hud.banner?.big, 'Миссия провалена');
    expect(g.hud.banner?.small, 'Цель потеряна');
    expect(g.quests.offers.any((o) => o.quest.storyId == 'gt2'), isTrue, reason: 'метка возвращается для повтора');
  });

  test('туман открывается по пути и сохраняется', () async {
    final g = await _newGame();
    final before = g.fog.cells.length;
    g.player.walkTo(move(g.player.pos, 90, 200));
    await _run(g, () => g.player.walkTarget == null, maxTicks: 1000);
    expect(g.fog.cells.length, greaterThan(before + 20));
    expect(distance(g.player.pos, move(const LatLng(43.1155, 131.8855), 90, 200)), lessThan(1));
  });
}
