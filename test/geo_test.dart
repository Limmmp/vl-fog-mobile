import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:vl_fog/core/geo.dart';

void main() {
  // Эталонные значения посчитаны js/geo.js веб-версии: ключи должны совпадать,
  // иначе открытую в браузере карту нельзя будет перенести в приложение.
  test('ключи ячеек тумана совпадают с веб-версией', () {
    final c = cellOf(const LatLng(43.1155, 131.8855));
    expect(cellKey(c.row, c.col), '239980:535858');
    expect(cellsInRadius(const LatLng(43.1155, 131.8855), 45).length, 16);
    final keys = cellsInRadius(const LatLng(43.13, 131.9), 60)..sort();
    expect(keys.take(3), ['240059:535791', '240059:535792', '240059:535793']);
  });

  test('distance и move согласованы', () {
    const a = LatLng(43.1155, 131.8855);
    final b = move(a, 90, 100);
    expect(distance(a, b), closeTo(100, 0.5));
    expect(bearing(a, b), closeTo(90, 0.5));
  });
}
