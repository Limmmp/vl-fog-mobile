// Мелкие элементы интерфейса: кнопки-«чипы», строки HUD, всплывающие сообщения.

import 'package:flutter/material.dart';

import 'palette.dart';

/// Тёмная кнопка в духе веб-версии (.chip).
class GameChip extends StatelessWidget {
  const GameChip({super.key, this.label, this.icon, this.onTap, this.color, this.tooltip});

  final String? label;
  final IconData? icon;
  final String? tooltip;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Palette.ink;
    return Material(
      color: Palette.chip,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: color ?? Palette.line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: ConstrainedBox(
          // Не меньше 44 pt — удобно попадать пальцем на ходу
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              widthFactor: 1,
              child: icon != null
                  ? Icon(icon, size: 20, color: onTap == null ? Palette.inkDim : c, semanticLabel: tooltip)
                  : Text(label ?? '', style: TextStyle(color: onTap == null ? Palette.inkDim : c, fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Строка HUD: подпись капсом и значение.
class HudRow extends StatelessWidget {
  const HudRow({super.key, required this.label, required this.value, this.valueColor = Palette.ink});

  final String label;
  final String value;
  final Color valueColor;

  static const shadow = [Shadow(color: Colors.black, offset: Offset(0, 2)), Shadow(color: Colors.black, blurRadius: 6)];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(color: Palette.inkDim, fontSize: 11, letterSpacing: 0.9, shadows: shadow)),
        const SizedBox(width: 8),
        Text(value,
            style: TextStyle(
                color: valueColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                shadows: shadow)),
      ],
    );
  }
}

void toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text, style: const TextStyle(color: Palette.ink)),
      backgroundColor: const Color(0xE6000000),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
}
