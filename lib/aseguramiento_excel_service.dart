import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

class AseguramientoExcelService {
  /// Mapeo de columnas Excel a índices
  static const Map<String, String> colMap = {
    'semana': 'B',
    'fecha': 'C',
    'nombre_producto': 'D',
    'proveedor': 'E',
    'presentacion': 'F',
    'total_unidades': 'G',
    'lote': 'H',
    'fecha_vencimiento': 'I',
    'estado_etiqueta': 'J',
    'estado_tapa': 'K',
    'sellos': 'L',
    'puntos_extraccion': 'M',
    'cantidad_cc_g': 'N',
    'color': 'O',
    'ph': 'P',
    'densidad': 'Q',
    'observaciones': 'S',
    'identificacion_asegura': 'T',
  };

  static Future<void> generarReporte(
    List<dynamic> registros, {
    String nombreArchivo = 'General',
  }) async {
    try {
      if (registros.isEmpty) {
        throw Exception('No hay datos para generar el reporte.');
      }

      // Cargar plantilla desde assets
      final ByteData data = await rootBundle.load(
        'assets/ASEGURAMIENTO_DE_PLAGUICIDAS_A_LA_LLEGADA_AL_ALMACEN.xlsx',
      );
      final List<int> templateBytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );

      // Decodificar como ZIP para manipular XML directamente
      final archive = ZipDecoder().decodeBytes(templateBytes);
      late ArchiveFile worksheetFile;

      for (final file in archive.files) {
        if (file.name == 'xl/worksheets/sheet1.xml') {
          worksheetFile = file;
          break;
        }
      }

      if (worksheetFile.size == 0) {
        throw Exception('No se encontró la hoja de trabajo en la plantilla.');
      }

      String sheetContent = String.fromCharCodes(
        worksheetFile.content as List<int>,
      );

      // Procesar primer registro (filas 5-8)
      final Map<String, dynamic> primerRegistro =
          registros.first is Map<String, dynamic>
          ? registros.first as Map<String, dynamic>
          : <String, dynamic>{};

      sheetContent = _updateCellValue(
        sheetContent,
        'B5',
        primerRegistro['semana'],
      );
      sheetContent = _updateCellValue(
        sheetContent,
        'C5',
        primerRegistro['fecha'],
      );
      sheetContent = _updateCellValue(
        sheetContent,
        'D5',
        primerRegistro['nombre_producto'],
      );
      sheetContent = _updateCellValue(
        sheetContent,
        'E5',
        primerRegistro['proveedor'],
      );
      sheetContent = _updateCellValue(
        sheetContent,
        'F5',
        primerRegistro['presentacion'],
      );
      sheetContent = _updateCellValue(
        sheetContent,
        'G5',
        primerRegistro['total_unidades'],
      );
      sheetContent = _updateCellValue(
        sheetContent,
        'H5',
        primerRegistro['lote'],
      );
      sheetContent = _updateCellValue(
        sheetContent,
        'I5',
        primerRegistro['fecha_vencimiento'],
      );
      sheetContent = _updateCellValue(
        sheetContent,
        'J5',
        primerRegistro['estado_etiqueta'],
      );
      sheetContent = _updateCellValue(
        sheetContent,
        'K5',
        primerRegistro['estado_tapa'],
      );
      sheetContent = _updateCellValue(
        sheetContent,
        'L5',
        primerRegistro['sellos'],
      );
      sheetContent = _updateCellValue(
        sheetContent,
        'M5',
        primerRegistro['puntos_extraccion'],
      );
      sheetContent = _updateCellValue(
        sheetContent,
        'N5',
        primerRegistro['cantidad_cc_g'],
      );
      sheetContent = _updateCellValue(
        sheetContent,
        'O5',
        primerRegistro['color'],
      );
      sheetContent = _updateCellValue(sheetContent, 'P5', primerRegistro['ph']);
      sheetContent = _updateCellValue(
        sheetContent,
        'Q5',
        primerRegistro['densidad'],
      );
      sheetContent = _updateCellValue(
        sheetContent,
        'S5',
        primerRegistro['observaciones'],
      );
      sheetContent = _updateCellValue(
        sheetContent,
        'T5',
        primerRegistro['identificacion_asegura'],
      );

      // Procesar registros de datos (filas 9+)
      const int filaInicio = 9;
      const int maximoRegistros = 500;

      for (int i = 0; i < registros.length; i++) {
        final registro = registros[i];
        if (registro is! Map<String, dynamic>) {
          continue;
        }

        final int fila = filaInicio + i;
        if (fila > filaInicio + maximoRegistros - 1) {
          throw Exception(
            'El reporte excede el máximo de 500 registros. Divide la información en varios archivos.',
          );
        }

        sheetContent = _updateCellValue(
          sheetContent,
          'B$fila',
          registro['semana'],
        );
        sheetContent = _updateCellValue(
          sheetContent,
          'C$fila',
          registro['fecha'],
        );
        sheetContent = _updateCellValue(
          sheetContent,
          'D$fila',
          registro['nombre_producto'],
        );
        sheetContent = _updateCellValue(
          sheetContent,
          'E$fila',
          registro['proveedor'],
        );
        sheetContent = _updateCellValue(
          sheetContent,
          'F$fila',
          registro['presentacion'],
        );
        sheetContent = _updateCellValue(
          sheetContent,
          'G$fila',
          registro['total_unidades'],
        );
        sheetContent = _updateCellValue(
          sheetContent,
          'H$fila',
          registro['lote'],
        );
        sheetContent = _updateCellValue(
          sheetContent,
          'I$fila',
          registro['fecha_vencimiento'],
        );
        sheetContent = _updateCellValue(
          sheetContent,
          'J$fila',
          registro['estado_etiqueta'],
        );
        sheetContent = _updateCellValue(
          sheetContent,
          'K$fila',
          registro['estado_tapa'],
        );
        sheetContent = _updateCellValue(
          sheetContent,
          'L$fila',
          registro['sellos'],
        );
        sheetContent = _updateCellValue(
          sheetContent,
          'M$fila',
          registro['puntos_extraccion'],
        );
        sheetContent = _updateCellValue(
          sheetContent,
          'N$fila',
          registro['cantidad_cc_g'],
        );
        sheetContent = _updateCellValue(
          sheetContent,
          'O$fila',
          registro['color'],
        );
        sheetContent = _updateCellValue(sheetContent, 'P$fila', registro['ph']);
        sheetContent = _updateCellValue(
          sheetContent,
          'Q$fila',
          registro['densidad'],
        );
        sheetContent = _updateCellValue(
          sheetContent,
          'S$fila',
          registro['observaciones'],
        );
        sheetContent = _updateCellValue(
          sheetContent,
          'T$fila',
          registro['identificacion_asegura'],
        );
      }

      // Reconstruir el archivo ZIP con el contenido modificado
      final newArchive = Archive();
      for (final file in archive.files) {
        if (file.name == 'xl/worksheets/sheet1.xml') {
          newArchive.addFile(
            ArchiveFile(file.name, sheetContent.length, sheetContent.codeUnits),
          );
        } else {
          newArchive.addFile(file);
        }
      }

      final List<int>? encodedBytes = ZipEncoder().encode(newArchive);
      if (encodedBytes == null) {
        throw Exception('No se pudo generar el archivo Excel.');
      }

      final String fileName = 'Aseguramiento_$nombreArchivo.xlsx';

      await _saveFileNative(encodedBytes, fileName);

    } catch (e) {
      throw 'Error al generar Excel: $e';
    }
  }
  


  /// Guarda el archivo en dispositivo nativo
  static Future<void> _saveFileNative(List<int> bytes, String fileName) async {
    final directory = await getExternalStorageDirectory();
    if (directory == null) {
  throw Exception('No se pudo acceder al almacenamiento');
}

final String fullPath = '${directory.path}/$fileName';

    final file = File(fullPath);
    await file.writeAsBytes(bytes, flush: true);

    await OpenFilex.open(fullPath);
  }

  /// Actualiza o inserta un valor en una celda, preservando estilos
  static String _updateCellValue(
    String xmlContent,
    String cellRef,
    dynamic value,
  ) {
    if (value == null || value.toString().isEmpty) {
      return xmlContent;
    }

    final String strValue = value.toString();

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
      final styleMatch = RegExp('\\bs="([^"]+)"').firstMatch(attrs);
      final styleAttr = styleMatch != null ? ' s="${styleMatch.group(1)}"' : '';

      return xmlContent.replaceRange(
        existingMatch.start,
        existingMatch.end,
        _buildInlineStringCell(cellRef, strValue, styleAttr),
      );
    }

    final rowMatch = RegExp(
      '<row([^>]*)r="${_rowNumberFromCell(cellRef)}"([^>]*)>(.*?)</row>',
      dotAll: true,
    ).firstMatch(xmlContent);

    if (rowMatch == null) {
      return xmlContent;
    }

    final rowStart = rowMatch.start;
    final rowEnd = rowMatch.end;
    final rowXml = rowMatch.group(0)!;
    final rowContentMatch = RegExp(
      '<row[^>]*>(.*?)</row>',
      dotAll: true,
    ).firstMatch(rowXml);
    if (rowContentMatch == null) {
      return xmlContent;
    }

    final rowContent = rowContentMatch.group(1)!;
    final targetColumn = _columnNumberFromCell(cellRef);
    final cellMatches = RegExp(
      '<c[^>]*r="([A-Z]+)\\d+"[^>]*/>|<c[^>]*r="([A-Z]+)\\d+"[^>]*>.*?</c>',
      dotAll: true,
    ).allMatches(rowContent).toList();

    int insertIndex = rowContent.length;
    for (final match in cellMatches) {
      final ref = match.group(1) ?? match.group(2) ?? '';
      if (_columnNumberFromCell(ref) > targetColumn) {
        insertIndex = match.start;
        break;
      }
    }

    final newRowContent =
        rowContent.substring(0, insertIndex) +
        _buildInlineStringCell(cellRef, strValue, '') +
        rowContent.substring(insertIndex);

    final newRowXml = rowXml.replaceRange(
      rowContentMatch.start,
      rowContentMatch.end,
      newRowContent,
    );

    return xmlContent.replaceRange(rowStart, rowEnd, newRowXml);
  }

  static String _buildInlineStringCell(
    String cellRef,
    String value,
    String styleAttr,
  ) {
    final escaped = _escapeXml(value);
    final preserveSpace = value.trim() != value;
    final spaceAttr = preserveSpace ? ' xml:space="preserve"' : '';
    return '<c r="$cellRef"$styleAttr t="inlineStr"><is><t$spaceAttr>$escaped</t></is></c>';
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
}
