import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class OfflineSyncService {
  static const String _pendingKey = 'offline_pending_records';

  /// Último rechazo del servidor (p. ej. faltan columnas en Supabase).
  /// Es null si la última subida fue bien o si solo faltó internet.
  static String? ultimoErrorServidor;

  /// Guarda el registro en el celular al instante y lo sube en segundo plano.
  /// [alTerminar] recibe cuántos registros se subieron (0 = sin internet o
  /// rechazo del servidor; ver [ultimoErrorServidor]).
  static Future<void> guardarLocalYSubir({
    required String table,
    required Map<String, dynamic> payload,
    required String supabaseUrl,
    required String apiKey,
    void Function(int subidos)? alTerminar,
  }) async {
    await enqueue(table, payload);
    unawaited(
      syncPending(supabaseUrl: supabaseUrl, apiKey: apiKey)
          .then((subidos) => alTerminar?.call(subidos))
          .catchError((_) => alTerminar?.call(0)),
    );
  }
  static Future<void> _operationTail = Future<void>.value();

  // Evita que dos sincronizaciones o un guardado local simultáneo sobrescriban
  // la cola mientras se está enviando un lote a Supabase.
  static Future<T> _serialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  static Future<int> pendingCount() async {
    final prefs = await SharedPreferences.getInstance();
    return _readPending(prefs).length;
  }

  static Future<void> cacheList(String key, List<dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(data));
  }

  static Future<List<dynamic>> readCachedList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : [];
    } catch (_) {
      return [];
    }
  }

  /// Descarga una lista y la guarda en caché; si no hay internet usa la caché.
  ///
  /// * [cacheFirst]: si ya hay caché, la devuelve al instante y actualiza la
  ///   caché en segundo plano (ideal para catálogos de formularios).
  /// * Si hay caché, solo se espera 4 s a internet (señal mala o WiFi sin
  ///   internet); sin caché se espera hasta 10 s.
  static Future<List<dynamic>> fetchListWithCache({
    required String cacheKey,
    required Uri url,
    required Map<String, String> headers,
    bool cacheFirst = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final tieneCache = prefs.containsKey(cacheKey);

    if (cacheFirst && tieneCache) {
      unawaited(_descargarYGuardar(cacheKey, url, headers, const Duration(seconds: 15)));
      return readCachedList(cacheKey);
    }

    final data = await _descargarYGuardar(
      cacheKey,
      url,
      headers,
      Duration(seconds: tieneCache ? 4 : 10),
    );
    return data ?? readCachedList(cacheKey);
  }

  static Future<List<dynamic>?> _descargarYGuardar(
    String cacheKey,
    Uri url,
    Map<String, String> headers,
    Duration timeout,
  ) async {
    try {
      final response = await http.get(url, headers: headers).timeout(timeout);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final data = decoded is List ? decoded : <dynamic>[];
        await cacheList(cacheKey, data);
        return data;
      }
    } catch (_) {}
    return null;
  }

  /// Registros guardados en el dispositivo que aún no se suben a [table].
  /// Devuelve copias marcadas con `_pendiente_sync: true` para mostrarlas en
  /// historiales; la cola original no se modifica.
  static Future<List<Map<String, dynamic>>> pendingRecords(String table) async {
    final prefs = await SharedPreferences.getInstance();
    return _readPending(prefs)
        .where((item) => item['table'] == table && item['payload'] is Map)
        .map((item) {
          final registro = Map<String, dynamic>.from(item['payload'] as Map);
          final creado =
              item['creado_local']?.toString() ??
              DateTime.now().toIso8601String();
          registro['_pendiente_sync'] = true;
          registro.putIfAbsent('fecha_registro', () => creado);
          registro.putIfAbsent(
            'fecha',
            () => creado.replaceFirst('T', ' ').substring(0, 16),
          );
          return registro;
        })
        .toList()
        .reversed
        .toList();
  }

  static Future<void> enqueue(String table, Map<String, dynamic> payload) async {
    return _serialized(() async {
      final prefs = await SharedPreferences.getInstance();
      final pending = _readPending(prefs);
      pending.add({
        'id': '${DateTime.now().microsecondsSinceEpoch}_${pending.length}',
        'table': table,
        'payload': payload,
        'creado_local': DateTime.now().toIso8601String(),
      });
      await prefs.setString(_pendingKey, jsonEncode(pending));
    });
  }

  static Future<int>? _syncEnCurso;

  /// true mientras hay una subida en curso.
  static bool get sincronizando => _syncEnCurso != null;

  /// Sube los registros pendientes. Si ya hay una subida en curso, devuelve
  /// esa misma (no se acumulan subidas en fila).
  static Future<int> syncPending({
    required String supabaseUrl,
    required String apiKey,
  }) {
    final enCurso = _syncEnCurso;
    if (enCurso != null) return enCurso;
    final nueva = _syncPending(supabaseUrl: supabaseUrl, apiKey: apiKey)
        .whenComplete(() => _syncEnCurso = null);
    _syncEnCurso = nueva;
    return nueva;
  }

  static String _idDe(Map<String, dynamic> item) =>
      item['id']?.toString() ?? jsonEncode(item);

  static Future<int> _syncPending({
    required String supabaseUrl,
    required String apiKey,
  }) async {
    // Foto de la cola; el envío se hace SIN bloquear la cola, para que
    // guardar un registro nuevo nunca espere a internet.
    final prefs = await SharedPreferences.getInstance();
    final pending = _readPending(prefs);
    if (pending.isEmpty) return 0;

    final subidos = <String>{};
    for (final item in pending) {
      try {
        final response = await http.post(
          Uri.parse('$supabaseUrl/rest/v1/${item['table']}'),
          headers: {
            'apikey': apiKey,
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'Prefer': 'return=minimal',
          },
          body: jsonEncode(item['payload']),
        ).timeout(const Duration(seconds: 12));
        if (response.statusCode == 200 || response.statusCode == 201) {
          subidos.add(_idDe(item));
          ultimoErrorServidor = null;
        } else if (response.statusCode >= 400 && response.statusCode < 500) {
          ultimoErrorServidor = '${response.statusCode}: ${response.body}';
        }
      } on TimeoutException {
        break; // sin internet: no tiene sentido seguir intentando el resto
      } on SocketException {
        break;
      } on http.ClientException {
        break;
      } catch (_) {}
    }

    if (subidos.isEmpty) return 0;
    // Quitar de la cola solo lo que se subió (respetando lo que se haya
    // guardado mientras tanto).
    await _serialized(() async {
      final actual = _readPending(prefs);
      actual.removeWhere((item) => subidos.contains(_idDe(item)));
      await prefs.setString(_pendingKey, jsonEncode(actual));
    });
    return subidos.length;
  }

  static List<Map<String, dynamic>> _readPending(SharedPreferences prefs) {
    final raw = prefs.getString(_pendingKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
