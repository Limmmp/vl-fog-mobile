import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:vl_fog/game/districts.dart';

void main() {
  test('кэш улиц кодируется так же, как в веб-версии, и читается обратно', () {
    final keys = {'240059:535793', '240059:535791', '240060:535800', '240059:535799'};
    final enc = encodeKeys(keys);
    expect(enc, '240059:535791,2,6;240060:535800');
    expect(decodeKeys(enc).toSet(), keys);
  });

  test('район по ближайшему центру, за городом — никакого', () {
    expect(districtAt(const LatLng(43.1155, 131.8855))?.name, 'Центр');
    expect(districtAt(const LatLng(43.1368, 131.9030))?.name, 'Первая Речка');
    expect(districtAt(const LatLng(43.5, 131.9)), isNull);
  });
}
