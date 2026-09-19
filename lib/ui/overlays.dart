// Элементы поверх карты: HUD, цель, субтитры, баннер, карточка задания, журнал.

import 'package:flutter/material.dart';

import '../game/game.dart';
import '../game/hud.dart';
import '../game/quests/engine.dart';
import 'palette.dart';
import 'widgets.dart';

const _shadow = HudRow.shadow;

/// Правый верхний угол: деньги, открытая площадь, уважение.
class HudPanel extends StatelessWidget {
  const HudPanel({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([game.quests, game.fog]),
      builder: (context, _) {
        final q = game.quests;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('\$${money(q.cash)}',
                style: const TextStyle(
                    fontFamily: Palette.display, fontSize: 34, color: Palette.cash, height: 1.1, shadows: _shadow)),
            HudRow(label: 'Исследовано', value: formatKm2(game.fog.areaKm2)),
            const SizedBox(height: 2),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('УВАЖЕНИЕ',
                  style: TextStyle(color: Palette.inkDim, fontSize: 11, letterSpacing: 0.9, shadows: _shadow)),
              const SizedBox(width: 6),
              for (var i = 0; i < 5; i++)
                Icon(i < q.stars ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 16, color: Palette.gold, shadows: _shadow),
            ]),
          ],
        );
      },
    );
  }
}

String formatKm2(double km2) => '${km2.toStringAsFixed(km2 < 1 ? 3 : 2).replaceAll('.', ',')} км²';

/// Текущая цель: заголовок задания, что делать, прогресс.
class ObjectiveBox extends StatelessWidget {
  const ObjectiveBox({super.key, required this.hud});

  final Hud hud;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: hud,
      builder: (context, _) {
        final o = hud.objective;
        if (o == null) return const SizedBox.shrink();
        return Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: const BoxDecoration(
            color: Color(0xB8000000),
            border: Border(left: BorderSide(color: Palette.gold, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(o.title.toUpperCase(),
                  style: const TextStyle(fontFamily: Palette.display, color: Palette.gold, fontSize: 14, letterSpacing: 0.5)),
              const SizedBox(height: 4),
              Text(o.text, style: const TextStyle(color: Palette.ink, fontSize: 14, height: 1.35)),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(children: [
                  for (var i = 0; i < o.meta.length; i++) ...[
                    if (i > 0) const TextSpan(text: ' · '),
                    TextSpan(
                      text: o.meta[i].text,
                      style: o.meta[i].warn ? const TextStyle(color: Palette.red, fontWeight: FontWeight.w700) : null,
                    ),
                  ],
                ]),
                style: const TextStyle(
                    color: Palette.inkDim, fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Субтитры. Формат реплики "Имя: текст" — имя подсвечиваем золотым.
class SubtitleView extends StatelessWidget {
  const SubtitleView({super.key, required this.hud});

  final Hud hud;

  static final _speaker = RegExp(r'^([^:]{1,24}):\s(.+)$', dotAll: true);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: hud,
      builder: (context, _) {
        final line = hud.subtitle;
        if (line == null) return const SizedBox.shrink();
        final m = _speaker.firstMatch(line);
        return Text.rich(
          TextSpan(children: [
            if (m != null) TextSpan(text: '${m[1]}: ', style: const TextStyle(color: Palette.gold, fontWeight: FontWeight.w700)),
            TextSpan(text: m != null ? m[2] : line),
          ]),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Palette.ink,
            fontSize: 16,
            height: 1.4,
            shadows: [Shadow(color: Colors.black, offset: Offset(0, 2)), Shadow(color: Colors.black, blurRadius: 8)],
          ),
        );
      },
    );
  }
}

/// Крупная надпись «МИССИЯ ПРОЙДЕНА / ПРОВАЛЕНА».
class BannerView extends StatelessWidget {
  const BannerView({super.key, required this.hud});

  final Hud hud;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: hud,
      builder: (context, _) {
        final b = hud.banner;
        if (b == null) return const SizedBox.shrink();
        return IgnorePointer(
          child: Center(
            child: TweenAnimationBuilder<double>(
              key: ValueKey(b),
              tween: Tween(begin: 1.4, end: 1),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              builder: (context, scale, child) =>
                  Opacity(opacity: ((1.4 - scale) / 0.4).clamp(0, 1), child: Transform.scale(scale: scale, child: child)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(b.big.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: Palette.display,
                        fontSize: 40,
                        color: b.fail ? Palette.red : Palette.gold,
                        shadows: const [Shadow(color: Colors.black, offset: Offset(0, 4)), Shadow(color: Colors.black, blurRadius: 20)],
                      )),
                  const SizedBox(height: 6),
                  Text(b.small,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontFamily: Palette.display,
                          fontSize: 22,
                          color: Palette.cash,
                          shadows: [Shadow(color: Colors.black, offset: Offset(0, 3))])),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Карточка предложения задания.
class OfferCard extends StatelessWidget {
  const OfferCard({super.key, required this.hud});

  final Hud hud;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: hud,
      builder: (context, _) {
        final q = hud.offer;
        if (q == null) return const SizedBox.shrink();
        final source = q.source == 'story' ? ' · сюжет' : q.source == 'ollama' ? ' · локальная модель' : '';
        return Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Palette.panel,
            border: Border(top: BorderSide(color: Palette.gold, width: 3)),
            boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 40, offset: Offset(0, 10))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${q.giver}$source'.toUpperCase(),
                  style: const TextStyle(color: Palette.inkDim, fontSize: 11, letterSpacing: 1.1)),
              const SizedBox(height: 4),
              Text(q.title, style: const TextStyle(fontFamily: Palette.display, color: Palette.gold, fontSize: 22)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.3),
                child: SingleChildScrollView(
                  child: Text(q.intro, style: const TextStyle(color: Palette.ink, fontSize: 14, height: 1.45)),
                ),
              ),
              const SizedBox(height: 10),
              Text('Награда: \$${money(q.cash)} · +${q.rep} уважения',
                  style: const TextStyle(color: Palette.cash, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Row(children: [
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Palette.gold,
                    foregroundColor: const Color(0xFF111111),
                    minimumSize: const Size(88, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  onPressed: () => hud.answer(true),
                  child: const Text('Взять'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Palette.ink,
                    side: const BorderSide(color: Palette.line),
                    minimumSize: const Size(88, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  onPressed: () => hud.answer(false),
                  child: const Text('Позже'),
                ),
              ]),
            ],
          ),
        );
      },
    );
  }
}

/// Журнал: активное задание, пройденные, сброс прогресса.
Future<void> showJournal(BuildContext context, Game game) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Palette.panel,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, scroll) {
        final q = game.quests;
        final active = q.activeQuest;
        Widget section(String t) => Padding(
              padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
              child: Text(t.toUpperCase(), style: const TextStyle(color: Palette.inkDim, fontSize: 11, letterSpacing: 1.1)),
            );
        Widget item(String title, String sub, {bool on = false}) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: const Color(0x0AFFFFFF),
                border: Border(left: BorderSide(color: on ? Palette.gold : Palette.line, width: 2)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(color: Palette.ink, fontSize: 13)),
                Text(sub, style: const TextStyle(color: Palette.inkDim, fontSize: 12)),
              ]),
            );
        const empty = TextStyle(color: Palette.inkDim, fontSize: 13);
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            const Text('Журнал', style: TextStyle(fontFamily: Palette.display, color: Palette.gold, fontSize: 24)),
            section('Активное'),
            if (active != null)
              item(active.title, active.giver, on: true)
            else
              const Text('Нет активного задания. Ищи жёлтые метки на карте.', style: empty),
            section('Пройдено'),
            if (q.done.isEmpty) const Text('Пока пусто.', style: empty),
            for (final d in q.done.reversed) item(d.title, '${d.giver} · \$${money(d.cash)}'),
            section('Сохранение'),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Palette.red,
                  side: const BorderSide(color: Color(0x66FF4D5A)),
                  minimumSize: const Size(0, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Сбросить прогресс?'),
                      content: const Text('Карта, деньги и пройденные задания будут стёрты.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Стереть')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await game.resetProgress();
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                child: const Text('Сбросить прогресс'),
              ),
            ),
          ],
        );
      },
    ),
  );
}
