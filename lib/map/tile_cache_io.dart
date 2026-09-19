import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Постоянная папка, а не временная: временную система чистит, и карта без связи пропадает.
Object? get tileCacheFolder => () async {
      final dir = Directory('${(await getApplicationSupportDirectory()).path}/tiles');
      await dir.create(recursive: true);
      return dir;
    };
