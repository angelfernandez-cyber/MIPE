import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class FirmaDigitalService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static String _cacheKey(String identificacion) =>
      'firmas_aseguramiento_$identificacion';

  static Future<List<Map<String, dynamic>>> obtenerFirmas({
    required String supabaseUrl,
    required String apiKey,
    required String identificacion,
    required String password,
  }) async {
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
          .timeout(const Duration(seconds: 10));
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
