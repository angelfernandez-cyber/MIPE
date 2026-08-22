import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class OfflineSyncService {
  static const String _pendingAspersionesKey = 'pending_aspersiones';

  static String _cacheKey(String bloque) => 'cached_aspersiones_$bloque';

  static Future<void> guardarCacheBloque(
    String bloque,
    List<dynamic> registros,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey(bloque), jsonEncode(registros));
  }

  static Future<List<dynamic>> leerCacheBloque(String bloque) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey(bloque));
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : [];
    } catch (_) {
      return [];
    }
  }

  static Future<void> guardarAspersionPendiente(
    Map<String, dynamic> payload,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final pendientes = _leerPendientes(prefs);
    pendientes.add(payload);
    await prefs.setString(_pendingAspersionesKey, jsonEncode(pendientes));
  }

  static Future<int> sincronizarAspersiones({
    required String supabaseUrl,
    required String apiKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final pendientes = _leerPendientes(prefs);
    if (pendientes.isEmpty) return 0;

    final restantes = <Map<String, dynamic>>[];
    var sincronizados = 0;
    final url = Uri.parse('$supabaseUrl/rest/v1/aspersiones');
    final headers = {
      'apikey': apiKey,
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Prefer': 'return=minimal',
    };

    for (final payload in pendientes) {
      try {
        final response = await http
            .post(url, headers: headers, body: jsonEncode(payload))
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 200 || response.statusCode == 201) {
          sincronizados++;
        } else {
          restantes.add(payload);
        }
      } catch (_) {
        restantes.add(payload);
      }
    }

    await prefs.setString(_pendingAspersionesKey, jsonEncode(restantes));
    return sincronizados;
  }

  static List<Map<String, dynamic>> _leerPendientes(SharedPreferences prefs) {
    final raw = prefs.getString(_pendingAspersionesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }
    } catch (_) {}
    return [];
  }
}
