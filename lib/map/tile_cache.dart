// Папка файлового кэша тайлов (параметр VectorTileLayer.cacheFolder).
// vector_map_tiles объявляет свой тип Directory через условный импорт (dart:io на телефоне,
// String в вебе), а анализатор видит веб-вариант — поэтому отдаём функцию как Object?
// и передаём её через dynamic: при сборке под телефон типы совпадают.
export 'tile_cache_stub.dart' if (dart.library.io) 'tile_cache_io.dart';
