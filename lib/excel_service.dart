import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:intl/intl.dart';

class MIPEExcelService {

  static Future<void> generarReporteMIPE(
    List<dynamic> registros, {
    String nombreArchivo = 'MIPE',
  }) async {
    try {
      if (registros.isEmpty) {
        throw Exception('No hay datos para generar el reporte.');
      }

      // 🔹 Cargar plantilla
      final ByteData data = await rootBundle.load(
        'assets/formato_aspersiones.xlsx',
      );

      final List<int> templateBytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );

      final archive = ZipDecoder().decodeBytes(templateBytes);

      late ArchiveFile worksheetFile;

      for (final file in archive.files) {
        if (file.name == 'xl/worksheets/sheet1.xml') {
          worksheetFile = file;
          break;
        }
      }

      if (worksheetFile.size == 0) {
        throw Exception('No se encontró la hoja en la plantilla.');
      }

      String sheetContent = String.fromCharCodes(
        worksheetFile.content as List<int>,
      );

      // 🔹 ENCABEZADO
      final primerRegistro = registros.first;

      sheetContent = _updateCellValue(
        sheetContent,
        'B6',
        primerRegistro['bloque'],
      );

      sheetContent = _updateCellValue(
        sheetContent,
        'G6',
        primerRegistro['jefe_mipe'],
      );

      // 🔹 CONFIGURACIÓN DE FILAS POR DÍA
      const int filaBase = 11; // Lunes empieza en fila 11
      const int saltoDia = 7;  // cada día ocupa 7 filas

      // 🔹 CONTADORES por día (para no sobreescribir)
      Map<int, int> contadorDia = {};

      for (var registro in registros) {
        if (registro is! Map<String, dynamic>) continue;

        DateTime fecha = DateTime.parse(registro['fecha_registro']);
        int dia = fecha.weekday; // 1=Lunes ... 7=Domingo

        if (dia > 6) continue; // ignorar domingo

        contadorDia[dia] = (contadorDia[dia] ?? 0);

        int fila = filaBase +
            ((dia - 1) * saltoDia) +
            contadorDia[dia]!;

        contadorDia[dia] = contadorDia[dia]! + 1;

        // 🔹 LLENADO EXACTO DE CELDAS

        sheetContent = _updateCellValue(
          sheetContent,
          'B$fila',
          DateFormat('dd/MM/yyyy').format(fecha),
        );

        sheetContent = _updateCellValue(
          sheetContent,
          'D$fila',
          registro['blanco_biologico'],
        );

        sheetContent = _updateCellValue(
          sheetContent,
          'F$fila',
          registro['temperatura'],
        );

        sheetContent = _updateCellValue(
          sheetContent,
          'G$fila',
          registro['humedad_relativa'],
        );

        sheetContent = _updateCellValue(
          sheetContent,
          'J$fila',
          registro['producto'],
        );

        sheetContent = _updateCellValue(
          sheetContent,
          'L$fila',
          registro['dosis'],
        );

        sheetContent = _updateCellValue(
          sheetContent,
          'M$fila',
          registro['cat_toxic'],
        );

        sheetContent = _updateCellValue(
          sheetContent,
          'Q$fila',
          registro['equipo'],
        );

        sheetContent = _updateCellValue(
          sheetContent,
          'R$fila',
          registro['ire_horas'],
        );

        sheetContent = _updateCellValue(
          sheetContent,
          'S$fila',
          registro['usuario_registro'] ?? 'Operario',
        );
      }

      // 🔹 RECONSTRUIR EXCEL
      final newArchive = Archive();

      for (final file in archive.files) {
        if (file.name == 'xl/worksheets/sheet1.xml') {
          newArchive.addFile(
            ArchiveFile(
              file.name,
              sheetContent.length,
              sheetContent.codeUnits,
            ),
          );
        } else {
          newArchive.addFile(file);
        }
      }

      final encodedBytes = ZipEncoder().encode(newArchive);

      if (encodedBytes == null) {
        throw Exception('Error generando Excel.');
      }

      final String fileName = 'Reporte_$nombreArchivo.xlsx';

      await _saveFile(encodedBytes, fileName);

    } catch (e) {
      throw 'Error MIPE: $e';
    }
  }

  // 🔹 GUARDAR ARCHIVO
  static Future<void> _saveFile(List<int> bytes, String fileName) async {
    final directory = await getExternalStorageDirectory();

    if (directory == null) {
      throw Exception('No se pudo acceder al almacenamiento');
    }

    final path = '${directory.path}/$fileName';

    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);

    await OpenFilex.open(path);
  }

  // 🔹 ACTUALIZAR CELDA SIN ROMPER FORMATO
  static String _updateCellValue(
    String xmlContent,
    String cellRef,
    dynamic value,
  ) {
    if (value == null || value.toString().isEmpty) {
      return xmlContent;
    }

    final strValue = value.toString();

    final cellRegex = RegExp(
      '<c([^>]*)r="$cellRef"([^>]*)/>|<c([^>]*)r="$cellRef"([^>]*)>.*?</c>',
      dotAll: true,
    );

    final match = cellRegex.firstMatch(xmlContent);

    if (match != null) {
      final attrs = [
        match.group(1) ?? '',
        match.group(2) ?? '',
        match.group(3) ?? '',
        match.group(4) ?? '',
      ].join(' ');

      final styleMatch = RegExp('\\bs="([^"]+)"').firstMatch(attrs);
      final styleAttr =
          styleMatch != null ? ' s="${styleMatch.group(1)}"' : '';

      return xmlContent.replaceRange(
        match.start,
        match.end,
        _buildCell(cellRef, strValue, styleAttr),
      );
    }

    return xmlContent;
  }

  static String _buildCell(
    String ref,
    String value,
    String styleAttr,
  ) {
    final escaped = value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');

    return '<c r="$ref"$styleAttr t="inlineStr"><is><t>$escaped</t></is></c>';
  }
}