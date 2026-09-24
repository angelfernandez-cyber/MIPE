import 'dart:convert';
import 'package:http/http.dart' as http;

class VisitanteService {
  static Future<dynamic> _rpc({
    required String supabaseUrl,
    required String apiKey,
    required String function,
    required Map<String, dynamic> body,
  }) async {
    final response = await http.post(
      Uri.parse('$supabaseUrl/rest/v1/rpc/$function'),
      headers: {
        'apikey': apiKey,
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw Exception('No se pudo conectar con el servicio de visitantes.');
    }

    if (response.statusCode != 200) {
      final message = decoded is Map ? decoded['message']?.toString() : null;
      final code = decoded is Map ? decoded['code']?.toString() : null;
      final details = decoded is Map ? decoded['details']?.toString() : null;
      final error = message?.isNotEmpty == true
          ? '${code == null ? '' : '[$code] '}$message${details == null || details == 'null' ? '' : ' — $details'}'
          : 'Error HTTP ${response.statusCode} al conectar con el servicio de visitantes.';
      throw Exception(error);
    }

    if (decoded == null) {
      throw Exception('La respuesta del servicio de visitantes está vacía.');
    }

    if (decoded is Map && decoded['error'] != null) {
      throw Exception(decoded['error'].toString());
    }

    return decoded;
  }

  static Future<Map<String, dynamic>> generarCodigo({
    required String supabaseUrl,
    required String apiKey,
    required String identificacion,
    required String password,
  }) async {
    final result = await _rpc(
      supabaseUrl: supabaseUrl,
      apiKey: apiKey,
      function: 'codigo_visitante_admin',
      body: {'p_identificacion': identificacion, 'p_password': password},
    );
    if (result is! Map) {
      throw Exception('El servicio de código visitante no devolvió un objeto válido.');
    }
    return Map<String, dynamic>.from(result);
  }

  static Future<Map<String, dynamic>> validarCodigo({
    required String supabaseUrl,
    required String apiKey,
    required String codigo,
  }) async {
    final result = await _rpc(
      supabaseUrl: supabaseUrl,
      apiKey: apiKey,
      function: 'validar_codigo_visitante',
      body: {'p_codigo': codigo},
    );
    if (result is! Map) {
      throw Exception('El servicio de validación de visitante no devolvió un objeto válido.');
    }
    return Map<String, dynamic>.from(result);
  }

  static Future<void> configurar({
    required String supabaseUrl,
    required String apiKey,
    required String identificacion,
    required String password,
    required bool habilitado,
    required bool puedeInsertar,
    required bool puedeExportar,
    required bool puedeVerAspersiones,
  }) async {
    await _rpc(
      supabaseUrl: supabaseUrl,
      apiKey: apiKey,
      function: 'configurar_visitantes_admin',
      body: {
        'p_identificacion': identificacion,
        'p_password': password,
        'p_habilitado': habilitado,
        'p_puede_insertar': puedeInsertar,
        'p_puede_exportar': puedeExportar,
        'p_puede_ver_aspersiones': puedeVerAspersiones,
      },
    );
  }

  static Future<Map<String, dynamic>> obtenerConfiguracion({
    required String supabaseUrl,
    required String apiKey,
  }) async {
    final result = await _rpc(
      supabaseUrl: supabaseUrl,
      apiKey: apiKey,
      function: 'obtener_configuracion_visitantes',
      body: const {},
    );
    if (result is! Map) {
      return {
        'habilitado': false,
        'puede_insertar': false,
        'puede_exportar': false,
        'puede_ver_aspersiones': false,
      };
    }
    return {
      'habilitado': false,
      'puede_insertar': false,
      'puede_exportar': false,
      'puede_ver_aspersiones': false,
    }..addAll(Map<String, dynamic>.from(result));
  }
}
