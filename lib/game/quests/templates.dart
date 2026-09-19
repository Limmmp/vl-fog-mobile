// Шаблонные квесты: механика фиксирована, места и детали подставляются из реальных точек вокруг игрока.
// Тексты и персонажи — стартовый набор из веб-версии; их легко дополнять.

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../poi.dart';

class Character {
  const Character(this.name, this.about);
  final String name;
  final String about;
}

const characters = {
  'gosha': Character('Дядя Гоша', 'старый контрабандист с Миллионки, говорит загадками, помнит 90-е'),
  'liza': Character('Лиза «Волна»', 'велокурьер, вечно опаздывает, дерзкая и весёлая'),
  'krab': Character('Артём Краб', 'торгует крабом «с чёрного хода», параноик'),
  'kenji': Character('Кэндзи', 'перегонщик праворульных японок с Зелёного угла, мешает русский и японский'),
  'somov': Character('Капитан Сомов', 'отставной моряк, картограф-любитель, ворчит про туман'),
  'nina': Character('Нина из ларька', 'знает все сплетни района, ревнивая'),
  'syoma': Character('Сёма Хайп', 'блогер-миллионник (по его словам), охотится за кадрами'),
  'vera': Character('Баба Вера', 'пенсионерка, у неё снова сбежал кот Адмирал'),
};

class GenContext {
  GenContext({required this.player, required this.pois, required this.rnd});
  final LatLng player;
  final PoiService pois;
  final math.Random rnd;

  T pickOne<T>(List<T> list) => list[rnd.nextInt(list.length)];

  /// Точка нужных категорий на расстоянии [min, max] от [origin], кроме [exclude].
  Poi? pick(List<String>? kinds, LatLng origin, double min, double max, [List<Poi> exclude = const []]) {
    final ex = exclude.map((p) => p.id).toSet();
    final list = pois
        .near(origin, max, (p) => (kinds == null || kinds.contains(p.kind)) && !ex.contains(p.id))
        .where((e) => e.$2 >= min)
        .map((e) => e.$1)
        .toList();
    return list.isEmpty ? null : pickOne(list);
  }
}

/// Время на дорогу пешком с запасом, в секундах.
int _walkTime(Poi a, Poi b, [double slack = 1.6]) => (distance(a.pos, b.pos) / 1.4 * slack + 45).round();

typedef QuestBuilder = Map<String, dynamic>? Function(GenContext ctx);

final Map<String, QuestBuilder> templates = {
  // 1. Курьерская доставка на время
  'courier': (ctx) {
    final start = ctx.pick(['food', 'bar'], ctx.player, 80, 700);
    if (start == null) return null;
    final dest = ctx.pick(null, start.pos, 250, 900, [start]);
    if (dest == null) return null;
    final g = characters['liza']!.name;
    final cargo = ctx.pickOne(['пакет с пянсе', 'термосумку с рамёном', 'коробку пирожных «Птичье молоко»', 'сорок порций хе из рыбы', 'чей-то забытый зонт']);
    final t = _walkTime(start, dest);
    return {
      'title': 'Горячая доставка',
      'giver': g,
      'start': start.id,
      'intro': '$g: «Цепь слетела, а у меня $cargo остывает. Точка — «${dest.name}». Уложишься в ${(t / 60).ceil()} мин — чаевые твои».',
      'reward': {'cash': 150 + (distance(start.pos, dest.pos) / 3).round(), 'rep': 1},
      'steps': [
        {
          'type': 'goto', 'poi': dest.id, 'timeLimit': t, 'text': 'Доставь $cargo к «${dest.name}»',
          'say': ['Клиент: Наконец-то! Я уже думал, вы через Русский мост пешком шли.'],
        },
      ],
      'outro': ['$g: Красавчик! Если что — у меня ещё полгорода заказов.'],
    };
  },

  // 2. Слежка
  'tail': (ctx) {
    final start = ctx.pick(['shop', 'food', 'misc', 'landmark'], ctx.player, 80, 700);
    if (start == null) return null;
    final a = ctx.pick(['food', 'bar', 'shop'], start.pos, 120, 450, [start]);
    if (a == null) return null;
    final b = ctx.pick(['park', 'water', 'view', 'landmark', 'bar'], a.pos, 300, 800, [start, a]);
    if (b == null) return null;
    final g = characters['nina']!.name;
    return {
      'title': 'Куда он ходит по вечерам',
      'giver': g,
      'start': start.id,
      'intro': '$g: «Мой Толик опять «к другу в гараж». Он сейчас у «${a.name}». Проследи, куда пойдёт. Только не спались — он пугливый».',
      'reward': {'cash': 400, 'rep': 2},
      'steps': [
        {'type': 'goto', 'poi': a.id, 'text': 'Найди Толика у «${a.name}»'},
        {'type': 'tail', 'from': a.id, 'to': b.id, 'text': 'Следуй за Толиком. Не отставай и не подходи слишком близко'},
        {
          'type': 'hold', 'poi': b.id, 'seconds': 15, 'text': 'Понаблюдай, с кем он встречается',
          'say': ['Толик: …да я ж говорю, лучший чебурек в городе, только Нине не говори!'],
        },
      ],
      'outro': ['$g: Чебуреки?! Ну я ему устрою «гараж». Держи, заслужил.'],
    };
  },

  // 3. Сбор нескольких точек
  'crab': (ctx) {
    final start = ctx.pick(['water', 'shop', 'food'], ctx.player, 80, 700);
    if (start == null) return null;
    final pts = <Poi>[];
    for (var i = 0; i < 3; i++) {
      final p = ctx.pick(['shop', 'food', 'water', 'misc', 'auto'], start.pos, 150, 800, [start, ...pts]);
      if (p != null) pts.add(p);
    }
    if (pts.length < 2) return null;
    final g = characters['krab']!.name;
    return {
      'title': 'Краб-экспресс',
      'giver': g,
      'start': start.id,
      'intro': '$g: «Тс-с. Мои ребята раскидали ящики по точкам — рыбнадзор на хвосте. Собери всё, пока не хватились. Никаких вопросов».',
      'reward': {'cash': 250 * pts.length, 'rep': 2},
      'steps': [
        {'type': 'collect', 'pois': pts.map((p) => p.id).toList(), 'text': 'Забери ящики: ${pts.map((p) => '«${p.name}»').join(', ')}'},
        {'type': 'goto', 'poi': start.id, 'text': 'Верни улов Артёму', 'timeLimit': 600},
      ],
      'outro': ['$g: Все клешни на месте. Ты ничего не видел, я ничего не давал.'],
    };
  },

  // 4. Праворульная тайна: дойти, подождать
  'kenji': (ctx) {
    final start = ctx.pick(['auto', 'shop', 'misc', 'food'], ctx.player, 80, 700);
    if (start == null) return null;
    final meet = ctx.pick(['park', 'landmark', 'water', 'view'], start.pos, 250, 900, [start]);
    if (meet == null) return null;
    final g = characters['kenji']!.name;
    return {
      'title': 'Документы на «Марк II»',
      'giver': g,
      'start': start.id,
      'intro': '$g: «Коннитива! Покупатель ждёт у «${meet.name}». Передай бумаги, постой, пока он проверит VIN. Только не торопи его — дзэн».',
      'reward': {'cash': 600, 'rep': 2},
      'steps': [
        {'type': 'goto', 'poi': meet.id, 'text': 'Встреться с покупателем у «${meet.name}»'},
        {
          'type': 'hold', 'poi': meet.id, 'seconds': 25, 'text': 'Жди, пока покупатель сверяет номер кузова',
          'say': ['Покупатель: Пробег 40 тысяч? Ну-ну. Ладно, беру.'],
        },
      ],
      'outro': ['$g: Аригато! Будет тебе скидка на тонировку.'],
    };
  },

  // 5. Разведка тумана
  'somov': (ctx) {
    final start = ctx.pick(['water', 'view', 'park', 'landmark'], ctx.player, 80, 900);
    if (start == null) return null;
    final cells = ctx.pickOne([60, 80, 120]);
    final g = characters['somov']!.name;
    final km2 = (cells * 400 / 1e6).toStringAsFixed(2).replaceAll('.', ',');
    return {
      'title': 'Белое пятно',
      'giver': g,
      'start': start.id,
      'intro': '$g: «Туман, салага, — он не над заливом, он в головах. Пройдись по кварталам, которых ещё не видел, открой мне $km2 км² карты».',
      'reward': {'cash': cells * 6, 'rep': 1},
      'steps': [
        {'type': 'explore', 'cells': cells, 'text': 'Открой $cells новых участков карты (≈$km2 км²)'},
      ],
      'outro': ['$g: Вот теперь карта похожа на карту. Держи на курево… то есть на мороженое.'],
    };
  },

  // 6. Фотоохота
  'syoma': (ctx) {
    final start = ctx.pick(['food', 'bar', 'culture', 'misc'], ctx.player, 80, 700);
    if (start == null) return null;
    final spot = ctx.pick(['view', 'landmark', 'culture', 'water', 'park'], start.pos, 200, 1000, [start]);
    if (spot == null) return null;
    final g = characters['syoma']!.name;
    return {
      'title': 'Контент сам себя не снимет',
      'giver': g,
      'start': start.id,
      'intro': '$g: «Братан, нужен кадр у «${spot.name}», пока свет золотой. Постоишь с телефоном 20 секунд — и ты в сторис на 300 тыщ… ну, на 3 тыщи».',
      'reward': {'cash': 350, 'rep': 1},
      'steps': [
        {'type': 'goto', 'poi': spot.id, 'text': 'Доберись до «${spot.name}»', 'timeLimit': _walkTime(start, spot, 2)},
        {'type': 'hold', 'poi': spot.id, 'seconds': 20, 'text': 'Снимай! Не уходи из кадра'},
      ],
      'outro': ['$g: Огонь! Отмечу тебя. Наверное.'],
    };
  },

  // 7. Потерянный кот
  'vera': (ctx) {
    final start = ctx.pick(['shop', 'park', 'misc', 'food'], ctx.player, 80, 700);
    if (start == null) return null;
    final pts = <Poi>[];
    for (var i = 0; i < 2; i++) {
      final p = ctx.pick(['park', 'food', 'shop', 'misc', 'water'], start.pos, 120, 600, [start, ...pts]);
      if (p != null) pts.add(p);
    }
    if (pts.length < 2) return null;
    final g = characters['vera']!.name;
    return {
      'title': 'Адмирал в самоволке',
      'giver': g,
      'start': start.id,
      'intro': '$g: «Сынок, Адмирал опять удрал! Рыжий, толстый, отзывается на «кис-кис» и на шуршание пакета. Его видели у «${pts[0].name}»».',
      'reward': {'cash': 200, 'rep': 2},
      'steps': [
        {'type': 'goto', 'poi': pts[0].id, 'text': 'Проверь «${pts[0].name}»', 'say': ['Дворник: Рыжий? Туда побежал, за ним собаки.']},
        {'type': 'tail', 'from': pts[0].id, 'to': pts[1].id, 'speed': 1.6, 'text': 'Не упусти кота из виду!'},
        {'type': 'goto', 'poi': start.id, 'text': 'Верни Адмирала хозяйке'},
      ],
      'outro': ['$g: Адмиральчик! Спасибо, родной, вот тебе на пирожки.'],
    };
  },
};

/// Случайный шаблонный квест или null, если рядом не нашлось подходящих мест.
Map<String, dynamic>? generateFromTemplates(GenContext ctx, [int attempts = 8]) {
  final pool = templates.keys.toList();
  for (var i = 0; i < attempts && pool.isNotEmpty; i++) {
    final id = pool.removeAt(ctx.rnd.nextInt(pool.length));
    final q = templates[id]!(ctx);
    if (q != null) return {...q, 'templateId': id};
  }
  return null;
}
