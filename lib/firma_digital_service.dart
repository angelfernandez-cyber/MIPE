import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class FirmaDigitalService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _modoFirmaKey = 'firma_aseguramiento_modo';
  static const String _modoPredeterminada = 'predeterminada';
  static const String _modoPorRegistro = 'por_registro';

  static String _cacheKey(String identificacion) =>
      'firmas_aseguramiento_$identificacion';

  static Future<String> leerModoFirma({
    String? supabaseUrl,
    String? apiKey,
    String? identificacion,
    String? password,
  }) async {
    if (identificacion == null || identificacion.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_modoFirmaKey) == _modoPorRegistro
          ? _modoPorRegistro
          : _modoPredeterminada;
    }

    final firmas =
        supabaseUrl != null &&
                apiKey != null &&
                password != null &&
                password.isNotEmpty
            ? await obtenerFirmas(
              supabaseUrl: supabaseUrl,
              apiKey: apiKey,
              identificacion: identificacion,
              password: password,
            )
            : await leerCache(identificacion);
    final usuario = firmas.cast<Map<String, dynamic>?>().firstWhere(
      (firma) => firma?['identificacion']?.toString() == identificacion,
      orElse: () => null,
    );
    return usuario?['usar_firma_predeterminada'] == false
        ? _modoPorRegistro
        : _modoPredeterminada;
  }

  static Future<void> guardarModoFirma(
    String modo, {
    String? supabaseUrl,
    String? apiKey,
    String? identificacion,
    String? password,
  }) async {
    final modoNormalizado =
        modo == _modoPorRegistro ? _modoPorRegistro : _modoPredeterminada;
    if (identificacion == null || identificacion.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modoFirmaKey, modoNormalizado);
      return;
    }
    if (supabaseUrl == null ||
        apiKey == null ||
        password == null ||
        password.isEmpty) {
      throw Exception('Se requiere iniciar sesión para guardar esta opción.');
    }

    final response = await http
        .post(
          Uri.parse('$supabaseUrl/rest/v1/rpc/guardar_preferencia_firma_usuario'),
          headers: {
            'apikey': apiKey,
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'p_identificacion': identificacion,
            'p_password': password,
            'p_usar_firma_predeterminada':
                modoNormalizado == _modoPredeterminada,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('No se pudo guardar la preferencia: ${response.body}');
    }

    final firmas = await leerCache(identificacion);
    final index = firmas.indexWhere(
      (firma) => firma['identificacion']?.toString() == identificacion,
    );
    if (index >= 0) {
      firmas[index]['usar_firma_predeterminada'] =
          modoNormalizado == _modoPredeterminada;
    } else {
      firmas.add({
        'identificacion': identificacion,
        'usar_firma_predeterminada': modoNormalizado == _modoPredeterminada,
      });
    }
    await _secureStorage.write(
      key: _cacheKey(identificacion),
      value: jsonEncode(firmas),
    );
    await obtenerFirmas(
      supabaseUrl: supabaseUrl,
      apiKey: apiKey,
      identificacion: identificacion,
      password: password,
    );
  }

  static Future<List<Map<String, dynamic>>> obtenerFirmas({
    required String supabaseUrl,
    required String apiKey,
    required String identificacion,
    required String password,
  }) async {
    // Con firmas en caché solo se esperan 4 s a internet; así los formularios
    // no se quedan esperando cuando la señal es mala.
    final tieneCache =
        await _secureStorage.containsKey(key: _cacheKey(identificacion));
    try {
      final response = await http
          .post(
            Uri.parse('$supabaseUrl/rest/v1/rpc/obtener_firmas_aseguramiento'),
            headers: {
              'apikey': apiKey,
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'p_identificacion': identificacion,
              'p_password': password,
            }),
          )
          .timeout(Duration(seconds: tieneCache ? 4 : 10));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final firmas = decoded is List
            ? decoded.whereType<Map>().map(Map<String, dynamic>.from).toList()
            : <Map<String, dynamic>>[];
        await _secureStorage.write(
          key: _cacheKey(identificacion),
          value: jsonEncode(firmas),
        );
        return firmas;
      }
    } catch (_) {}
    return leerCache(identificacion);
  }

  static Future<void> guardarFirma({
    required String supabaseUrl,
    required String apiKey,
    required String identificacion,
    required String password,
    required String firmaPngBase64,
  }) async {
    final response = await http
        .post(
          Uri.parse('$supabaseUrl/rest/v1/rpc/guardar_firma_usuario'),
          headers: {
            'apikey': apiKey,
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'p_identificacion': identificacion,
            'p_password': password,
            'p_firma_png_base64': firmaPngBase64,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('No se pudo guardar la firma: ${response.body}');
    }
    await obtenerFirmas(
      supabaseUrl: supabaseUrl,
      apiKey: apiKey,
      identificacion: identificacion,
      password: password,
    );
  }

  static Future<void> eliminarFirma({
    required String supabaseUrl,
    required String apiKey,
    required String identificacion,
    required String password,
  }) async {
    final response = await http
        .post(
          Uri.parse('$supabaseUrl/rest/v1/rpc/eliminar_firma_usuario'),
          headers: {
            'apikey': apiKey,
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'p_identificacion': identificacion,
            'p_password': password,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('No se pudo eliminar la firma: ${response.body}');
    }

    final firmas = await leerCache(identificacion);
    firmas.removeWhere(
      (firma) => firma['identificacion']?.toString() == identificacion,
    );
    await _secureStorage.write(
      key: _cacheKey(identificacion),
      value: jsonEncode(firmas),
    );
  }

  static Future<List<Map<String, dynamic>>> leerCache(
    String identificacion,
  ) async {
    final raw = await _secureStorage.read(key: _cacheKey(identificacion));
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List
          ? decoded.whereType<Map>().map(Map<String, dynamic>.from).toList()
          : [];
    } catch (_) {
      return [];
    }
  }
}
