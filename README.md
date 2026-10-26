<div align="center">

# Туман Владивостока — мобильная версия

**Flutter-приложение: туман открывается, даже когда телефон лежит в кармане.**

<img src="https://img.shields.io/badge/Flutter-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter"> <img src="https://img.shields.io/badge/Dart-0175C2?style=flat-square&logo=dart&logoColor=white" alt="Dart"> <img src="https://img.shields.io/badge/OpenStreetMap-7EBC6F?style=flat-square&logo=openstreetmap&logoColor=white" alt="OpenStreetMap">

</div>

> Веб-прототип и скриншоты игры: [vl-fog](https://github.com/Limmmp/vl-fog)

<!-- header:end -->
Уличная игра на реальной карте города: как в GTA, карта скрыта туманом и открывается там, где ты
прошёл ногами. По городу разбросаны жёлтые метки — заказчики с заданиями, которые собираются из
настоящих мест вокруг: кафе, парков, причалов, памятников.

Приложение на Flutter для Android и iOS. Веб-прототип, с которого всё начиналось, лежит в
[vl-fog](https://github.com/Limmmp/vl-fog); там же [CONCEPT.md](https://github.com/Limmmp/vl-fog/blob/main/CONCEPT.md) с описанием игры.

## Зачем приложение, если есть браузерная версия

GPS в браузере работает, только пока экран включён и вкладка открыта. Приложение ведёт тебя
и с выключенным экраном: туман открывается, пока телефон лежит в кармане.

## Запуск

Нужен [Flutter](https://docs.flutter.dev/get-started/install) 3.44+.

```bash
flutter pub get
flutter run -d <id телефона>     # flutter devices покажет список
```

Собрать и поставить APK вручную:

```bash
flutter build apk --debug
flutter install -d <id телефона>
```

`flutter install` сам не пересобирает — сначала `build`.

## Управление

| | |
|---|---|
| Нажатие по карте | идти к точке (режим симуляции, время ускорено ×8) |
| WASD / стрелки, Shift | идти и бежать — на компьютере и в браузере |
| «Режим» | переключение симуляция ↔ GPS |
| «◎» или нажатие на радар | центрировать карту на игроке |
| «Задания» | журнал, районы, сброс прогресса |

## Районы

Город разбит на микрорайоны (Центр, Эгершельд, Первая Речка, Чуркин и другие). Процент
района — доля его улиц, по которым ты прошёл. За 25, 50, 75 и 90 % дают деньги и уважение.

## Тесты

```bash
flutter test
```

Проверяются совместимость ячеек тумана с веб-версией, прохождение сюжетной миссии, слежка
(успех и провал) и формат кэша улиц.

## Карта

Векторные тайлы [OpenFreeMap](https://openfreemap.org) (без ключа и регистрации), отрисовка —
`flutter_map` + `vector_map_tiles`. Стиль `assets/map/style.json` собирается скриптом
`tools/build-map-style.py` из [vl-fog](https://github.com/Limmmp/vl-fog).

Карта © участники OpenStreetMap, тайлы — OpenFreeMap / © OpenMapTiles, маршруты — OSRM на
сервере FOSSGIS. Шрифты Rubik и Russo One — лицензия OFL.
