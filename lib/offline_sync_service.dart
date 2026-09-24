import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class OfflineSyncService {
  static const String _pendingKey = 'offline_pending_records';
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

  static Future<List<dynamic>> fetchListWithCache({
    required String cacheKey,
    required Uri url,
    required Map<String, String> headers,
  }) async {
    try {
      final response = await http.get(url, headers: headers).timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final data = decoded is List ? decoded : <dynamic>[];
        await cacheList(cacheKey, data);
        return data;
      }
    } catch (_) {}
    return readCachedList(cacheKey);
  }

  static Future<void> enqueue(String table, Map<String, dynamic> payload) async {
    return _serialized(() async {
      final prefs = await SharedPreferences.getInstance();
      final pending = _readPending(prefs);
      pending.add({'table': table, 'payload': payload});
      await prefs.setString(_pendingKey, jsonEncode(pending));
    });
  }

  static Future<int> syncPending({
    required String supabaseUrl,
    required String apiKey,
  }) {
    return _serialized(() => _syncPending(
          supabaseUrl: supabaseUrl,
          apiKey: apiKey,
        ));
  }

  static Future<int> _syncPending({
    required String supabaseUrl,
    required String apiKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final pending = _readPending(prefs);
    if (pending.isEmpty) return 0;

    final remaining = <Map<String, dynamic>>[];
    var synced = 0;
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
        ).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200 || response.statusCode == 201) {
          synced++;
        } else {
          remaining.add(item);
        }
      } catch (_) {
        remaining.add(item);
      }
    }
    await prefs.setString(_pendingKey, jsonEncode(remaining));
    return synced;
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
