// Сохранение прогресса. Мелкое (деньги, настройки, позиция) — в SharedPreferences как JSON,
// крупное (туман, кэш мест и улиц) — в файлы приложения. Ошибки хранилища игру не роняют.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Store {
  Store._(this._prefs, this._dir);

  final SharedPreferences _prefs;
  final Directory? _dir; // null в вебе: файлы недоступны, крупное тоже кладём в prefs

  static const _prefix = 'vlfog:';

  static Future<Store> open() async {
    final prefs = await SharedPreferences.getInstance();
    Directory? dir;
    if (!kIsWeb) {
      dir = Directory('${(await getApplicationSupportDirectory()).path}/save');
      await dir.create(recursive: true);
    }
    return Store._(prefs, dir);
  }

  T load<T>(String key, T fallback) {
    try {
      final raw = _prefs.getString(_prefix + key);
      return raw == null ? fallback : jsonDecode(raw) as T;
    } catch (e) {
      debugPrint('[store] не прочитал $key: $e');
      return fallback;
    }
  }

  void save(String key, Object? value) {
    _prefs.setString(_prefix + key, jsonEncode(value)).catchError((Object e) {
      debugPrint('[store] не сохранил $key: $e');
      return false;
    });
  }

  /// Крупные данные: файл на телефоне, prefs в вебе.
  Future<String?> loadBlob(String name) async {
    try {
      if (_dir == null) return _prefs.getString('${_prefix}blob:$name');
      final f = File('${_dir.path}/$name');
      return await f.exists() ? await f.readAsString() : null;
    } catch (e) {
      debugPrint('[store] не прочитал файл $name: $e');
      return null;
    }
  }

  Future<void> saveBlob(String name, String data) async {
    try {
      if (_dir == null) {
        await _prefs.setString('${_prefix}blob:$name', data);
        return;
      }
      // Пишем во временный файл и переименовываем — чтобы не потерять сохранение, если приложение убьют посреди записи
      final tmp = File('${_dir.path}/$name.tmp');
      await tmp.writeAsString(data, flush: true);
      await tmp.rename('${_dir.path}/$name');
    } catch (e) {
      debugPrint('[store] не сохранил файл $name: $e');
    }
  }

  Future<void> clearAll() async {
    for (final k in _prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      await _prefs.remove(k);
    }
    if (_dir != null && await _dir.exists()) {
      await for (final f in _dir.list()) {
        await f.delete(recursive: true);
      }
    }
  }
}

/// Отложенный вызов: не пишем на диск на каждый шаг.
class Debouncer {
  Debouncer(this.delay, this.action);
  final Duration delay;
  final void Function() action;
  Timer? _t;

  void call() {
    _t?.cancel();
    _t = Timer(delay, action);
  }

  void flush() {
    if (_t?.isActive ?? false) {
      _t!.cancel();
      action();
    }
  }
}
