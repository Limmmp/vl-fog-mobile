// Слои заданий на карте: метки (выдачи, цели, NPC) и пунктир от игрока к цели.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../game/player.dart';
import '../game/quests/engine.dart';
import '../ui/palette.dart';

class QuestBlipLayer extends StatelessWidget {
  const QuestBlipLayer({super.key, required this.quests});

  final QuestEngine quests;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: quests,
      builder: (context, _) => MarkerLayer(
        markers: [
          for (final b in quests.blips())
            Marker(point: b.pos, width: 34, height: 34, child: BlipView(kind: b.kind, letter: b.letter)),
        ],
      ),
    );
  }
}

/// Пунктир от игрока к текущей цели (как в веб-версии — прямой; по улицам — в планах).
class GuideLineLayer extends StatelessWidget {
  const GuideLineLayer({super.key, required this.quests, required this.player});

  final QuestEngine quests;
  final Player player;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([quests, player]),
      builder: (context, _) {
        final t = quests.target;
        if (t == null) return const SizedBox.shrink();
        return PolylineLayer(polylines: [
          Polyline(
            points: [player.pos, t],
            color: Palette.gold.withValues(alpha: 0.75),
            strokeWidth: 3,
            pattern: StrokePattern.dotted(spacingFactor: 3),
          ),
        ]);
      },
    );
  }
}

class BlipView extends StatefulWidget {
  const BlipView({super.key, required this.kind, required this.letter});

  final BlipKind kind;
  final String letter;

  @override
  State<BlipView> createState() => _BlipViewState();
}

class _BlipViewState extends State<BlipView> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.kind == BlipKind.target) _pulse.repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tail = widget.kind == BlipKind.tail;
    final bg = tail ? Palette.red : Palette.gold;
    final fg = tail ? Colors.white : const Color(0xFF111111);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        // Пульс: кольцо расходится и гаснет (только у целей)
        final v = widget.kind == BlipKind.target ? _pulse.value : 0.0;
        return Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF111111), width: 2),
            boxShadow: [
              const BoxShadow(color: Color(0x99000000), blurRadius: 12),
              if (v > 0) BoxShadow(color: Palette.gold.withValues(alpha: 0.3 * (1 - v)), spreadRadius: 8 * v),
            ],
          ),
          child: child,
        );
      },
      // У NPC вместо буквы — значок: в шрифте Russo One нет символа ◉
      child: tail
          ? Icon(Icons.visibility, size: 14, color: fg)
          : Text(widget.letter, style: TextStyle(fontFamily: Palette.display, fontSize: 13, color: fg, height: 1)),
    );
  }
}
