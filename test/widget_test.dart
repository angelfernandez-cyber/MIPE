import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/firma_digital_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('firma predeterminada y por registro se persisten correctamente', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await FirmaDigitalService.leerModoFirma(), 'predeterminada');

    await FirmaDigitalService.guardarModoFirma('por_registro');
    expect(await FirmaDigitalService.leerModoFirma(), 'por_registro');

    await FirmaDigitalService.guardarModoFirma('predeterminada');
    expect(await FirmaDigitalService.leerModoFirma(), 'predeterminada');
  });
}
