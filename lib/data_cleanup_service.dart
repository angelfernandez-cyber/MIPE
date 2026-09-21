import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_file_saver.dart';

class CleanupTable {
  final String name;
  final String deleteFilter;

  const CleanupTable(this.name, this.deleteFilter);
}

class DataCleanupService {
  static const tables = <CleanupTable>[
    CleanupTable('aspersiones', 'id=not.is.null'),
    CleanupTable('aseguramiento_plaguicidas', 'id=not.is.null'),
  ];

  static const int defaultQuotaBytes = 500 * 1024 * 1024;

  static Future<StorageUsage> fetchStorageUsage({
    required String supabaseUrl,
    required String apiKey,
  }) async {
    final response = await http.post(
      Uri.parse('$supabaseUrl/rest/v1/rpc/get_database_storage_usage'),
      headers: {
        'apikey': apiKey,
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: '{}',
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception(
        'La función de almacenamiento no está disponible (${response.statusCode}). '
        'Ejecuta supabase/storage_usage.sql en el SQL Editor de Supabase. '
        'Detalle: ${response.body}',
      );
    }
    final data = jsonDecode(response.body);
    if (data is List && data.isEmpty) {
      throw Exception('Supabase no devolvió el tamaño de la base de datos.');
    }
    final row = data is List ? data.first : data;
    if (row is! Map || row['used_bytes'] == null) {
      throw Exception('La función de almacenamiento devolvió un formato inválido.');
    }
    return StorageUsage(
      usedBytes: (row['used_bytes'] as num).toInt(),
      quotaBytes: defaultQuotaBytes,
    );
  }

  static Future<String> createBackupAndSave({
    required String supabaseUrl,
    required String apiKey,
    void Function(String table)? onTable,
  }) async {
    final backup = <String, dynamic>{
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'source': 'Cultivos La Planicie',
      'tables': <String, dynamic>{},
    };

    for (final table in tables) {
      onTable?.call(table.name);
      backup['tables'][table.name] = await _fetchAllRows(
        supabaseUrl,
        apiKey,
        table.name,
      );
    }

    final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(backup));
    final fileName = 'respaldo_planicie_${DateTime.now().millisecondsSinceEpoch}.json';
    return saveBackupBytes(bytes, fileName);
  }

  static Future<int> deleteAll({
    required String supabaseUrl,
    required String apiKey,
    void Function(String table)? onTable,
  }) async {
    for (final table in tables) {
      onTable?.call(table.name);
    }

    final response = await http.post(
      Uri.parse('$supabaseUrl/rest/v1/rpc/limpiar_datos_respaldo'),
      headers: {
        'apikey': apiKey,
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal',
      },
      body: '{}',
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
        'No se pudo limpiar la información (${response.statusCode}). '
        'Ejecuta supabase/backup_cleanup.sql en Supabase. Detalle: ${response.body}',
      );
    }
    return tables.length;
  }

  static Future<int> restoreBackup({
    required List<int> bytes,
    required String supabaseUrl,
    required String apiKey,
    void Function(String table)? onTable,
  }) async {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map || decoded['tables'] is! Map) {
      throw Exception('El archivo no tiene un formato de respaldo válido.');
    }

    final rawTables = Map<String, dynamic>.from(decoded['tables'] as Map);
    final allowedNames = tables.map((table) => table.name).toSet();
    final unknownNames = rawTables.keys
        .where((name) => !allowedNames.contains(name))
        .toList();
    if (unknownNames.isNotEmpty) {
      throw Exception('El respaldo contiene tablas no permitidas.');
    }

    for (final table in tables) {
      if (!rawTables.containsKey(table.name) || rawTables[table.name] is! List) {
        throw Exception('Falta información de ${table.name} en el respaldo.');
      }
    }

    final preparedRows = <String, List<Map<String, dynamic>>>{};
    for (final table in tables) {
      final rows = <Map<String, dynamic>>[];
      for (final row in rawTables[table.name] as List) {
        if (row is! Map) {
          throw Exception('El respaldo contiene un registro inválido.');
        }
        final copy = Map<String, dynamic>.from(row);
        copy.remove('id');
        rows.add(copy);
      }
      preparedRows[table.name] = rows;
    }

    await deleteAll(
      supabaseUrl: supabaseUrl,
      apiKey: apiKey,
      onTable: onTable,
    );

    var restored = 0;
    for (final table in tables) {
      onTable?.call(table.name);
      final rows = preparedRows[table.name]!;

      for (var offset = 0; offset < rows.length; offset += 200) {
        final end = offset + 200 < rows.length ? offset + 200 : rows.length;
        final response = await http.post(
          Uri.parse('$supabaseUrl/rest/v1/${table.name}'),
          headers: {
            'apikey': apiKey,
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'Prefer': 'return=minimal',
          },
          body: jsonEncode(rows.sublist(offset, end)),
        );
        if (response.statusCode != 201 && response.statusCode != 200) {
          throw Exception('No se pudo restaurar ${table.name}: ${response.body}');
        }
        restored += end - offset;
      }
    }
    return restored;
  }

  static Future<void> clearLocalCopies() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where((key) =>
        key.startsWith('cache_aspersiones_bloque_') ||
        key == 'cache_aseguramiento_plaguicidas')) {
      await prefs.remove(key);
    }
  }

  static Future<http.Response> _request(
    String supabaseUrl,
    String apiKey,
    String table, {
    String method = 'GET',
    required String query,
  }) {
    final url = Uri.parse('$supabaseUrl/rest/v1/$table?$query');
    final headers = {
      'apikey': apiKey,
      'Authorization': 'Bearer $apiKey',
      'Accept': 'application/json',
      if (method == 'DELETE') 'Prefer': 'return=minimal',
    };
    if (method == 'DELETE') return http.delete(url, headers: headers);
    return http.get(url, headers: headers);
  }

  static Future<List<dynamic>> _fetchAllRows(
    String supabaseUrl,
    String apiKey,
    String table,
  ) async {
    const pageSize = 1000;
    final rows = <dynamic>[];
    var offset = 0;
    while (true) {
      final response = await _request(
        supabaseUrl,
        apiKey,
        table,
        query: 'select=*&offset=$offset&limit=$pageSize',
      );
      if (response.statusCode != 200) {
        throw Exception('No se pudo respaldar $table: ${response.body}');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List || decoded.isEmpty) break;
      rows.addAll(decoded);
      if (decoded.length < pageSize) break;
      offset += pageSize;
    }
    return rows;
  }
}

class StorageUsage {
  final int usedBytes;
  final int quotaBytes;

  const StorageUsage({required this.usedBytes, required this.quotaBytes});

  int get remainingBytes => (quotaBytes - usedBytes).clamp(0, quotaBytes);
  double get ratio => quotaBytes == 0 ? 0 : usedBytes / quotaBytes;
}