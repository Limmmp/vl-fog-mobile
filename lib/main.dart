// Туман Владивостока — точка входа: загрузка сохранения и карты, затем экран игры.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/game.dart';
import 'map/basemap.dart';
import 'ui/game_screen.dart';
import 'ui/palette.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const VlFogApp());
}

class VlFogApp extends StatelessWidget {
  const VlFogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Туман Владивостока',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Rubik',
        scaffoldBackgroundColor: Palette.ground,
        colorScheme: const ColorScheme.dark(primary: Palette.gold, surface: Palette.panel),
      ),
      home: const _Boot(),
    );
  }
}

/// Загружает игру и карту, пока показывает заставку.
class _Boot extends StatefulWidget {
  const _Boot();

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  late final Future<(Game, Basemap)> _loading = _load();

  Future<(Game, Basemap)> _load() async {
    final game = await Game.start();
    final basemap = await Basemap.load(game.store);
    return (game, basemap);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _loading,
      builder: (context, snap) {
        if (snap.hasData) return GameScreen(game: snap.data!.$1, basemap: snap.data!.$2);
        return Scaffold(
          body: Center(
            child: snap.hasError
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Не удалось запустить игру:\n${snap.error}',
                        textAlign: TextAlign.center, style: const TextStyle(color: Palette.red)),
                  )
                : const Text('ТУМАН ВЛАДИВОСТОКА',
                    style: TextStyle(color: Palette.gold, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2)),
          ),
        );
      },
    );
  }
}
