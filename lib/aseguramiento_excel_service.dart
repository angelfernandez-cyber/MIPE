// lib/aseguramiento_excel_service.dart
// Servicio para generar Excel desde plantilla XLSX (Aseguramiento de plaguicidas).
// Requisitos pubspec.yaml:
//   archive: ^3.3.0
//   path_provider: ^2.0.0
//   open_filex: ^3.4.0
// Asegúrate de tener la plantilla en assets y declarada en pubspec.yaml.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle, ByteData;
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

class AseguramientoExcelService {
  /// Devuelve un valor seguro según tipo esperado
  /// Si el valor es null o vacío devuelve el placeholder (defaultText) '-'
  /// Si el valor existe y es numérico, se devolverá el número (num)
  static dynamic _safe(dynamic value, {String defaultText = '-'}) {
    if (value == null) return defaultText;
    final s = value.toString().trim();
    if (s.isEmpty) return defaultText;
    final num? n = num.tryParse(s.replaceAll(',', '.'));
    return n ?? s;
  }

  /// Genera el reporte a partir de la plantilla XLSX.
  /// Devuelve la ruta completa del archivo generado.
  /// onProgress recibe valores entre 0.0 y 1.0.
  /// cancelToken permite abortar la operación desde la UI.
  static Future<String> generarReporte(
    List<dynamic> registros, {
    String nombreArchivo = 'General',
    void Function(double progress)? onProgress,
    CancellationToken? cancelToken, // <-- NUEVO: Token de cancelación
  }) async {
    try {
      if (registros.isEmpty) {
        throw Exception('No hay datos para generar el reporte.');
      }

      onProgress?.call(0.02);
      await Future.delayed(const Duration(milliseconds: 50));

      // Verificación de cancelación temprana
      if (cancelToken?.isCancelled == true) throw Exception('Exportación cancelada por el usuario.');

      final ByteData data = await rootBundle.load(
        'assets/ASEGURAMIENTO_DE_PLAGUICIDAS_A_LA_LLEGADA_AL_ALMACEN.xlsx',
      );
      final List<int> templateBytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );

      onProgress?.call(0.08);

      if (cancelToken?.isCancelled == true) throw Exception('Exportación cancelada por el usuario.');

      final archive = ZipDecoder().decodeBytes(templateBytes);
      ArchiveFile? worksheetFile;
      ArchiveFile? stylesFile;

      for (final file in archive.files) {
        if (file.name == 'xl/worksheets/sheet1.xml') worksheetFile = file;
        if (file.name == 'xl/styles.xml') stylesFile = file;
      }

      if (worksheetFile == null) {
        throw Exception('No se encontró xl/worksheets/sheet1.xml en la plantilla.');
      }
      if (stylesFile == null) {
        throw Exception('No se encontró xl/styles.xml en la plantilla.');
      }

      String sheetContent = String.fromCharCodes(worksheetFile.content as List<int>);
      String stylesContent = String.fromCharCodes(stylesFile.content as List<int>);

      onProgress?.call(0.18);

      // Asegurar que exista un estilo con borde y centrado; si no, lo añadimos y obtenemos su id
      final int estiloConBorde = _ensureCenteredBorderStyleId(refStylesContent: stylesContent);
      // Si _ensureCenteredBorderStyleId devolvió -1 significa que no pudo parsear; en ese caso usamos 15 por compatibilidad
      final int styleToUse = estiloConBorde >= 0 ? estiloConBorde : 15;
      // Si se añadió un estilo, reemplazamos stylesContent por la versión actualizada
      stylesContent = _lastStylesContent ?? stylesContent;

      // Encabezado con el primer registro (si aplica)
      final Map<String, dynamic> primerRegistro =
          registros.isNotEmpty && registros.first is Map<String, dynamic>
              ? Map<String, dynamic>.from(registros.first)
              : <String, dynamic>{};

      // Mapear encabezado
      sheetContent = _updateCellValue(sheetContent, 'B5', _safe(primerRegistro['semana']));
      sheetContent = _updateCellValue(sheetContent, 'C5', _safe(primerRegistro['fecha']));
      sheetContent = _updateCellValue(sheetContent, 'D5', _safe(primerRegistro['nombre_producto']));
      sheetContent = _updateCellValue(sheetContent, 'E5', _safe(primerRegistro['proveedor']));
      sheetContent = _updateCellValue(sheetContent, 'F5', _safe(primerRegistro['presentacion']));
      sheetContent = _updateCellValue(sheetContent, 'G5', _safe(primerRegistro['total_unidades']));
      sheetContent = _updateCellValue(sheetContent, 'H5', _safe(primerRegistro['lote']));
      sheetContent = _updateCellValue(sheetContent, 'I5', _safe(primerRegistro['fecha_vencimiento']));
      sheetContent = _updateCellValue(sheetContent, 'J5', _safe(primerRegistro['estado_etiqueta']));
      sheetContent = _updateCellValue(sheetContent, 'K5', _safe(primerRegistro['estado_tapa']));
      sheetContent = _updateCellValue(sheetContent, 'L5', _safe(primerRegistro['sellos']));
      sheetContent = _updateCellValue(sheetContent, 'M5', _safe(primerRegistro['puntos_extraccion']));
      sheetContent = _updateCellValue(sheetContent, 'N5', _safe(primerRegistro['cantidad_cc_g']));
      sheetContent = _updateCellValue(sheetContent, 'O5', _safe(primerRegistro['color']));
      sheetContent = _updateCellValue(sheetContent, 'P5', _safe(primerRegistro['ph']));
      sheetContent = _updateCellValue(sheetContent, 'Q5', _safe(primerRegistro['densidad']));

      // Columna R -> cumplimiento_pct (si existe) o fallback a cumplimiento textual
      final dynamic encabezadoCumplPct = primerRegistro.containsKey('cumplimiento_pct')
          ? primerRegistro['cumplimiento_pct']
          : (primerRegistro.containsKey('cumplimiento') ? primerRegistro['cumplimiento'] : null);
      sheetContent = _updateCellValue(sheetContent, 'R5', _safe(encabezadoCumplPct));

      sheetContent = _updateCellValue(sheetContent, 'S5', _safe(primerRegistro['observaciones']));
      sheetContent = _updateCellValue(sheetContent, 'T5', _safe(primerRegistro['identificacion_asegura']));
      sheetContent = _updateCellValue(
        sheetContent,
        'U5',
        _safe(primerRegistro['nombre_autoriza'] ?? primerRegistro['nombre_quien_asegura'] ?? primerRegistro['autorizacion']),
      );

      onProgress?.call(0.28);

      // Procesar registros (filas 9 en adelante)
      const int filaInicio = 9;
      const int maximoRegistros = 500;
      final Set<int> filasConDatos = {};

      final int total = registros.length;
      int processed = 0;

      for (int i = 0; i < registros.length; i++) {
        // VERIFICACIÓN DE CANCELACIÓN EN CADA ITERACIÓN
        if (cancelToken?.isCancelled == true) {
          throw Exception('Exportación cancelada por el usuario.');
        }

        final registro = registros[i];
        if (registro is! Map<String, dynamic>) {
          processed++;
          onProgress?.call(0.28 + (processed / total) * 0.5);
          if (i % 20 == 0) await Future.delayed(const Duration(milliseconds: 1));
          continue;
        }

        final int fila = filaInicio + i;
        if (fila > filaInicio + maximoRegistros - 1) {
          throw Exception('El reporte excede el máximo de $maximoRegistros registros.');
        }

        filasConDatos.add(fila);

        // Rellenar fila
        sheetContent = _updateCellValue(sheetContent, 'B$fila', _safe(registro['semana']));
        sheetContent = _updateCellValue(sheetContent, 'C$fila', _safe(registro['fecha']));
        sheetContent = _updateCellValue(sheetContent, 'D$fila', _safe(registro['nombre_producto']));
        sheetContent = _updateCellValue(sheetContent, 'E$fila', _safe(registro['proveedor']));
        sheetContent = _updateCellValue(sheetContent, 'F$fila', _safe(registro['presentacion']));
        sheetContent = _updateCellValue(sheetContent, 'G$fila', _safe(registro['total_unidades']));
        sheetContent = _updateCellValue(sheetContent, 'H$fila', _safe(registro['lote']));
        sheetContent = _updateCellValue(sheetContent, 'I$fila', _safe(registro['fecha_vencimiento']));
        sheetContent = _updateCellValue(sheetContent, 'J$fila', _safe(registro['estado_etiqueta']));
        sheetContent = _updateCellValue(sheetContent, 'K$fila', _safe(registro['estado_tapa']));
        sheetContent = _updateCellValue(sheetContent, 'L$fila', _safe(registro['sellos']));
        sheetContent = _updateCellValue(sheetContent, 'M$fila', _safe(registro['puntos_extraccion']));
        sheetContent = _updateCellValue(sheetContent, 'N$fila', _safe(registro['cantidad_cc_g']));
        sheetContent = _updateCellValue(sheetContent, 'O$fila', _safe(registro['color']));
        sheetContent = _updateCellValue(sheetContent, 'P$fila', _safe(registro['ph']));
        sheetContent = _updateCellValue(sheetContent, 'Q$fila', _safe(registro['densidad']));

        final dynamic filaCumplPct = registro.containsKey('cumplimiento_pct')
            ? registro['cumplimiento_pct']
            : (registro.containsKey('cumplimiento') ? registro['cumplimiento'] : null);
        sheetContent = _updateCellValue(sheetContent, 'R$fila', _safe(filaCumplPct));

        sheetContent = _updateCellValue(sheetContent, 'S$fila', _safe(registro['observaciones']));
        sheetContent = _updateCellValue(sheetContent, 'T$fila', _safe(registro['identificacion_asegura']));
        sheetContent = _updateCellValue(
          sheetContent,
          'U$fila',
          _safe(registro['nombre_autoriza'] ?? registro['nombre_quien_asegura'] ?? registro['autorizacion']),
        );

        processed++;
        onProgress?.call(0.28 + (processed / total) * 0.5);
        if (i % 20 == 0) await Future.delayed(const Duration(milliseconds: 1));
      }

      onProgress?.call(0.80);
      if (cancelToken?.isCancelled == true) throw Exception('Exportación cancelada por el usuario.');

      // Aplicar bordes y centrado a filas con datos
      if (filasConDatos.isNotEmpty) {
        sheetContent = _aplicarBordesYCentrado(sheetContent, filasConDatos, styleToUse);
      }

      onProgress?.call(0.88);

      // Reconstruir ZIP
      final newArchive = Archive();
      for (final file in archive.files) {
        if (file.name == 'xl/worksheets/sheet1.xml') {
          final bytes = utf8.encode(sheetContent);
          newArchive.addFile(ArchiveFile(file.name, bytes.length, bytes));
        } else if (file.name == 'xl/styles.xml') {
          final bytes = utf8.encode(stylesContent);
          newArchive.addFile(ArchiveFile(file.name, bytes.length, bytes));
        } else {
          newArchive.addFile(file);
        }
      }

      final List<int>? encodedBytes = ZipEncoder().encode(newArchive);
      if (encodedBytes == null) throw Exception('No se pudo generar el archivo Excel.');

      onProgress?.call(0.94);
      if (cancelToken?.isCancelled == true) throw Exception('Exportación cancelada por el usuario.');

      final String fileName = 'Aseguramiento_$nombreArchivo.xlsx';
      final String savedPath = await _saveFileNative(encodedBytes, fileName);

      onProgress?.call(1.0);

      return savedPath;
    } catch (e) {
      rethrow;
    }
  }

  // Guarda el archivo en almacenamiento y lo abre, devuelve la ruta completa
  static Future<String> _saveFileNative(List<int> bytes, String fileName) async {
    Directory? directory;
    try {
      if (Platform.isAndroid) {
        try {
          directory = await getExternalStorageDirectory();
        } catch (_) {
          directory = null;
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
    } catch (_) {
      directory = null;
    }

    // Fallback general
    if (directory == null) {
      directory = await getApplicationDocumentsDirectory();
    }
    if (directory == null) throw Exception('No se pudo acceder al almacenamiento del dispositivo.');

    final fullPath = '${directory.path}/$fileName';
    final file = File(fullPath);
    await file.writeAsBytes(bytes, flush: true);
    try {
      await OpenFilex.open(fullPath);
    } catch (_) {}
    return fullPath;
  }

  // ---------------- Helpers ----------------

  static String _updateCellValue(String xmlContent, String cellRef, dynamic value) {
    if (value == null) return xmlContent;
    final String strValue = value.toString();
    if (strValue.isEmpty) return xmlContent;

    final num? numeric = num.tryParse(strValue.replaceAll(',', '.'));
    final bool isNumeric = numeric != null;

    final cellRegex = RegExp(
      '<c([^>]*)r="$cellRef"([^>]*)/>|<c([^>]*)r="$cellRef"([^>]*)>.*?</c>',
      dotAll: true,
    );

    final existingMatch = cellRegex.firstMatch(xmlContent);
    if (existingMatch != null) {
      final attrs = [
        existingMatch.group(1) ?? '',
        existingMatch.group(2) ?? '',
        existingMatch.group(3) ?? '',
        existingMatch.group(4) ?? '',
      ].join(' ');
      final styleMatch = RegExp(r'\bs="([^"]+)"').firstMatch(attrs);
      final styleAttr = styleMatch != null ? ' s="${styleMatch.group(1)}"' : '';

      if (isNumeric) {
        final String numText = (numeric == numeric.roundToDouble())
            ? numeric.toInt().toString()
            : numeric.toString();
        return xmlContent.replaceRange(
          existingMatch.start,
          existingMatch.end,
          _buildNumericCell(cellRef, numText, styleAttr),
        );
      } else {
        return xmlContent.replaceRange(
          existingMatch.start,
          existingMatch.end,
          _buildInlineStringCell(cellRef, strValue, styleAttr),
        );
      }
    }

    final rowNum = _rowNumberFromCell(cellRef);
    final rowRegex = RegExp('<row([^>]*)r="$rowNum"([^>]*)>(.*?)</row>', dotAll: true);
    final rowMatch = rowRegex.firstMatch(xmlContent);
    if (rowMatch == null) return xmlContent;

    final rowXml = rowMatch.group(0)!;
    final rowContentMatch = RegExp('<row[^>]*>(.*?)</row>', dotAll: true).firstMatch(rowXml);
    if (rowContentMatch == null) return xmlContent;
    final rowContent = rowContentMatch.group(1)!;

    final targetColumn = _columnNumberFromCell(cellRef);
    final cellMatches = RegExp('<c[^>]*r="([A-Z]+)\\d+"[^>]*/>|<c[^>]*r="([A-Z]+)\\d+"[^>]*>.*?</c>', dotAll: true)
        .allMatches(rowContent)
        .toList();

    int insertIndex = rowContent.length;
    for (final m in cellMatches) {
      final ref = m.group(1) ?? m.group(2) ?? '';
      if (ref.isEmpty) continue;
      if (_columnNumberFromCell(ref) > targetColumn) {
        insertIndex = m.start;
        break;
      }
    }

    final String newCellXml = isNumeric
        ? _buildNumericCell(cellRef, (numeric == numeric.roundToDouble() ? numeric.toInt().toString() : numeric.toString()), '')
        : _buildInlineStringCell(cellRef, strValue, '');

    final newRowContent = rowContent.substring(0, insertIndex) +
        newCellXml +
        rowContent.substring(insertIndex);

    final newRowXml = rowXml.replaceRange(rowContentMatch.start, rowContentMatch.end, newRowContent);
    return xmlContent.replaceRange(rowMatch.start, rowMatch.end, newRowXml);
  }

  static String _buildInlineStringCell(String cellRef, String value, String styleAttr) {
    final escaped = _escapeXml(value);
    final preserveSpace = value.startsWith(' ') || value.endsWith(' ');
    final spaceAttr = preserveSpace ? ' xml:space="preserve"' : '';
    final style = styleAttr.isNotEmpty ? styleAttr : '';
    return '<c r="$cellRef"$style t="inlineStr"><is><t$spaceAttr>$escaped</t></is></c>';
  }

  static String _buildNumericCell(String cellRef, String value, String styleAttr) {
    final style = styleAttr.isNotEmpty ? styleAttr : '';
    return '<c r="$cellRef"$style t="n"><v>$value</v></c>';
  }

  static int _rowNumberFromCell(String cellRef) {
    final match = RegExp(r'\d+').firstMatch(cellRef);
    return match == null ? 0 : int.parse(match.group(0)!);
  }

  static int _columnNumberFromCell(String cellRef) {
    final column = RegExp(r'[A-Z]+').firstMatch(cellRef)?.group(0) ?? 'A';
    var result = 0;
    for (final codeUnit in column.codeUnits) {
      result = result * 26 + (codeUnit - 64);
    }
    return result;
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static String _aplicarBordesYCentrado(String sheetContent, Set<int> filasConDatos, int estiloConBorde) {
    final columnas = ['B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U'];
    final int estilo = estiloConBorde;
    String resultado = sheetContent;
    for (final fila in filasConDatos) {
      for (final col in columnas) {
        final cellRef = '$col$fila';
        resultado = _aplicarEstiloACelda(resultado, cellRef, estilo);
      }
    }
    return resultado;
  }

  static String _aplicarEstiloACelda(String xmlContent, String cellRef, int styleId) {
    final cellRegex = RegExp('<c([^>]*)r="$cellRef"([^>]*)/>|<c([^>]*)r="$cellRef"([^>]*)>(.*?)</c>', dotAll: true);
    final match = cellRegex.firstMatch(xmlContent);
    final newStyleAttr = ' s="$styleId"';
    if (match != null) {
      String cellTag = match.group(0)!;
      if (cellTag.contains(RegExp(r'\bs="\d+"'))) {
        cellTag = cellTag.replaceFirst(RegExp(r'\bs="\d+"'), newStyleAttr.trim());
      } else {
        cellTag = cellTag.replaceFirst('<c', '<c$newStyleAttr');
      }
      return xmlContent.replaceRange(match.start, match.end, cellTag);
    }

    final rowNumber = _rowNumberFromCell(cellRef);
    final rowRegex = RegExp('<row([^>]*)r="$rowNumber"([^>]*)>(.*?)</row>', dotAll: true);
    final rowMatch = rowRegex.firstMatch(xmlContent);
    if (rowMatch == null) return xmlContent;

    final rowXml = rowMatch.group(0)!;
    final rowContent = rowMatch.group(3)!;
    final targetColumn = _columnNumberFromCell(cellRef);
    final cellMatches = RegExp('<c[^>]*r="([A-Z]+)\\d+"[^>]*/>|<c[^>]*r="([A-Z]+)\\d+"[^>]*>.*?</c>', dotAll: true)
        .allMatches(rowContent)
        .toList();

    int insertIndex = rowContent.length;
    for (final existingMatch in cellMatches) {
      final ref = existingMatch.group(1) ?? existingMatch.group(2) ?? '';
      if (ref.isEmpty) continue;
      if (_columnNumberFromCell(ref) > targetColumn) {
        insertIndex = existingMatch.start;
        break;
      }
    }

    final newCell = _buildInlineStringCell(cellRef, '', ' s="$styleId"');
    final newRowContent = rowContent.substring(0, insertIndex) + newCell + rowContent.substring(insertIndex);
    final newRowXml = rowXml.replaceFirst(rowContent, newRowContent);
    return xmlContent.replaceRange(rowMatch.start, rowMatch.end, newRowXml);
  }

  static String? _lastStylesContent;

  static int _ensureCenteredBorderStyleId({required String refStylesContent}) {
    try {
      String styles = refStylesContent;
      final xfMatches = RegExp(r'<cellXfs[^>]*>(.*?)</cellXfs>', dotAll: true).firstMatch(styles);
      if (xfMatches == null) return -1;
      final xfInner = xfMatches.group(1)!;
      final allXfs = RegExp(r'<xf\b[^>]*?>', dotAll: true).allMatches(xfInner).toList();

      for (int i = 0; i < allXfs.length; i++) {
        final xfTag = allXfs[i].group(0)!;
        if (xfTag.contains('applyAlignment="1"') && xfTag.contains('alignment')) {
          return i;
        }
      }

      final bordersMatch = RegExp(r'<borders[^>]*>(.*?)</borders>', dotAll: true).firstMatch(styles);
      if (bordersMatch == null) return -1;
      final bordersInner = bordersMatch.group(1)!;
      final borderCountMatch = RegExp(r'<borders[^>]*count="(\d+)"').firstMatch(styles);
      int borderCount = borderCountMatch != null ? int.parse(borderCountMatch.group(1)!) : RegExp(r'<border\b').allMatches(bordersInner).length;

      final newBorderXml = '<border><left style="thin"><color rgb="FF000000"/></left><right style="thin"><color rgb="FF000000"/></right><top style="thin"><color rgb="FF000000"/></top><bottom style="thin"><color rgb="FF000000"/></bottom><diagonal/></border>';
      final newBordersInner = bordersInner + newBorderXml;
      styles = styles.replaceRange(bordersMatch.start, bordersMatch.end, '<borders count="${borderCount + 1}">$newBordersInner</borders>');

      final cellXfsMatch = RegExp(r'<cellXfs[^>]*>(.*?)</cellXfs>', dotAll: true).firstMatch(styles);
      if (cellXfsMatch == null) return -1;
      final cellXfsInner = cellXfsMatch.group(1)!;
      final cellXfsCountMatch = RegExp(r'<cellXfs[^>]*count="(\d+)"').firstMatch(styles);
      int cellXfsCount = cellXfsCountMatch != null ? int.parse(cellXfsCountMatch.group(1)!) : RegExp(r'<xf\b').allMatches(cellXfsInner).length;

      final newXf = '<xf numFmtId="0" fontId="0" fillId="0" borderId="$borderCount" xfId="0" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>';
      final newCellXfsInner = cellXfsInner + newXf;
      styles = styles.replaceRange(cellXfsMatch.start, cellXfsMatch.end, '<cellXfs count="${cellXfsCount + 1}">$newCellXfsInner</cellXfs>');

      _lastStylesContent = styles;
      return cellXfsCount;
    } catch (e) {
      return -1;
    }
  }
}

/// CLASE NUEVA PARA CONTROLAR LA CANCELACIÓN DESDE LA UI
class CancellationToken {
  bool isCancelled = false;

  void cancel() {
    isCancelled = true;
  }
}