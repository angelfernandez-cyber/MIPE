import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle, ByteData;
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

class MIPEExcelService {
  /// Genera el reporte MIPE en un Isolate y reporta progreso 0.0..1.0 vía onProgress.
  /// El isolate devuelve los bytes del archivo; el hilo principal escribe el archivo y lo abre.
  /// Se pueden pasar bloqueHeader y jefeMipe para rellenar encabezado (D6 y J6).
  static Future<String> generarReporteMIPE(
    List<dynamic> registros, {
    String nombreArchivo = 'MIPE',
    void Function(double progress)? onProgress,
    bool abrirArchivoAlFinal = true,
    String? bloqueHeader,
    String? jefeMipe,
    bool protegerHoja = false,
    MIPECancellationToken? cancelToken,
  }) async {
    if (registros.isEmpty) throw Exception('No hay datos para generar el reporte.');

    // Cargar bytes de la plantilla en el hilo principal (plugins OK aquí)
    final ByteData data = await rootBundle.load('assets/aspersion.xlsx');
    final List<int> templateBytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

    final receivePort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();
    final cancelPort = ReceivePort();
    final cancelPortSubscription = cancelPort.listen((message) {
      if (message is SendPort) cancelToken?._attach(message);
    });

    final payload = <String, dynamic>{
      'sendPort': receivePort.sendPort,
      'templateBytes': templateBytes,
      'registros': registros,
      'nombreArchivo': nombreArchivo,
      'bloqueHeader': bloqueHeader,
      'jefeMipe': jefeMipe,
      'protegerHoja': protegerHoja,
      'cancelPort': cancelPort.sendPort,
    };

    await Isolate.spawn<_IsolatePayload>(_isolateEntry, _IsolatePayload(payload),
        onError: errorPort.sendPort, onExit: exitPort.sendPort, errorsAreFatal: false);

    final completer = Completer<String>();
    StreamSubscription? sub;
    StreamSubscription? errSub;
    StreamSubscription? exitSub;

    sub = receivePort.listen((dynamic message) async {
      try {
        if (message is Map) {
          if (message['cancelado'] == true) {
            if (!completer.isCompleted) {
              completer.completeError(const MIPECanceledException());
            }
            return;
          }

          // progreso desde el isolate
          if (message.containsKey('progress')) {
            final p = (message['progress'] as num).toDouble();
            try {
              onProgress?.call(p.clamp(0.0, 1.0));
            } catch (_) {}
            return;
          }

          // isolate terminó y envía bytes del archivo
          if (message.containsKey('doneBytes')) {
            final dynamic raw = message['doneBytes'];
            final Uint8List encodedBytes = raw is Uint8List ? raw : Uint8List.fromList(List<int>.from(raw as List));
            Directory? directory;
            try {
              directory = await getExternalStorageDirectory();
            } catch (_) {
              directory = null;
            }
            if (directory == null) {
              directory = await getApplicationDocumentsDirectory();
            }
            if (directory == null) {
              if (!completer.isCompleted) completer.completeError(Exception('No se pudo acceder al almacenamiento del dispositivo.'));
              return;
            }

            final outPath = '${directory.path}/MIPE_${nombreArchivo}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
            final outFile = File(outPath);
            await outFile.writeAsBytes(encodedBytes, flush: true);

            try {
              onProgress?.call(1.0);
            } catch (_) {}

            if (abrirArchivoAlFinal) {
              try {
                await OpenFilex.open(outPath);
              } catch (e) {
                print('No se pudo abrir el archivo automáticamente: $e');
              }
            }

            if (!completer.isCompleted) completer.complete(outPath);
            return;
          }

          // isolate envía 'error' con stack
          if (message.containsKey('error')) {
            final String err = message['error']?.toString() ?? 'Error desconocido';
            final String? stack = message['stack']?.toString();
            print('MIPE isolate error: $err');
            if (stack != null) print(stack);
            if (!completer.isCompleted) completer.completeError(Exception(err));
            return;
          }
        }
      } catch (e, st) {
        if (!completer.isCompleted) completer.completeError(e);
      }
    });

    errSub = errorPort.listen((dynamic err) {
      if (!completer.isCompleted) completer.completeError(Exception('Isolate error: $err'));
    });

    exitSub = exitPort.listen((_) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!completer.isCompleted) completer.completeError(Exception('Isolate finalizó sin devolver ruta'));
      });
    });

    try {
      final result = await completer.future;
      await sub?.cancel();
      await errSub?.cancel();
      await exitSub?.cancel();
      receivePort.close();
      errorPort.close();
      exitPort.close();
      cancelPort.close();
      await cancelPortSubscription.cancel();
      return result;
    } catch (e) {
      await sub?.cancel();
      await errSub?.cancel();
      await exitSub?.cancel();
      receivePort.close();
      errorPort.close();
      exitPort.close();
      cancelPort.close();
      await cancelPortSubscription.cancel();
      rethrow;
    }
  }

  // ----------------- Isolate entry -----------------
  static void _isolateEntry(_IsolatePayload payload) {
    final Map<String, dynamic> msg = payload.message;
    final SendPort sendPort = msg['sendPort'] as SendPort;
    final List<int> templateBytes = List<int>.from(msg['templateBytes'] as List<dynamic>);
    final List<dynamic> registros = List<dynamic>.from(msg['registros'] as List<dynamic>);
    final String nombreArchivo = msg['nombreArchivo'] as String? ?? 'MIPE';
    final String? bloqueHeader = msg['bloqueHeader'] as String?;
    final String? jefeMipe = msg['jefeMipe'] as String?;
    final bool protegerHoja = msg['protegerHoja'] as bool? ?? false;
    final SendPort cancelPort = msg['cancelPort'] as SendPort;
    bool cancelado = false;
    final cancelSubscription = ReceivePort();
    cancelPort.send(cancelSubscription.sendPort);
    cancelSubscription.listen((message) {
      if (message == 'cancelar') cancelado = true;
    });

    _generateExcelBytesInIsolate(
      sendPort: sendPort,
      templateBytes: templateBytes,
      registros: registros,
      nombreArchivo: nombreArchivo,
      bloqueHeader: bloqueHeader,
      jefeMipe: jefeMipe,
      protegerHoja: protegerHoja,
      estaCancelado: () => cancelado,
    );
    cancelSubscription.close();
  }

  static Future<void> _generateExcelBytesInIsolate({
    required SendPort sendPort,
    required List<int> templateBytes,
    required List<dynamic> registros,
    required String nombreArchivo,
    String? bloqueHeader,
    String? jefeMipe,
    bool protegerHoja = false,
    bool Function()? estaCancelado,
  }) async {
    try {
      sendPort.send({'progress': 0.02});

      final archive = ZipDecoder().decodeBytes(templateBytes);

      ArchiveFile? worksheetFile;
      ArchiveFile? stylesFile;

      for (final file in archive.files) {
        if (file.name == 'xl/worksheets/sheet1.xml') worksheetFile = file;
        if (file.name == 'xl/styles.xml') stylesFile = file;
      }

      if (worksheetFile == null) {
        sendPort.send({'error': 'No se encontró xl/worksheets/sheet1.xml en la plantilla.'});
        return;
      }
      if (stylesFile == null) {
        sendPort.send({'error': 'No se encontró xl/styles.xml en la plantilla.'});
        return;
      }

      String sheetContent = String.fromCharCodes(worksheetFile.content as List<int>);
      String stylesContent = String.fromCharCodes(stylesFile.content as List<int>);

      // Aseguramos que exista un estilo con borde y centrado; si no existe, lo añadimos
      stylesContent = _agregarEstilosConBorde(stylesContent);
      final int? estiloBorde = _obtenerStyleIdConBordeYWrap(stylesContent);
      final int styleToUse = estiloBorde ?? 44;

      final List<String> mergedRanges = _extraerMergedRanges(sheetContent);

      // Si se pasó bloqueHeader o jefeMipe, los usamos; si no, intentamos tomar del primer registro
      String bloqueParaEncabezado = bloqueHeader ?? '';
      String jefeParaEncabezado = jefeMipe ?? '';

      if ((bloqueParaEncabezado.isEmpty || jefeParaEncabezado.isEmpty) && registros.isNotEmpty && registros.first is Map) {
        final primerRegistro = registros.first as Map;
        if (bloqueParaEncabezado.isEmpty) bloqueParaEncabezado = (primerRegistro['bloque']?.toString() ?? '');
        if (jefeParaEncabezado.isEmpty) jefeParaEncabezado = (primerRegistro['bombero']?.toString() ?? '');
      }

      // Aplicar encabezados en plantilla (D6 = bloque, J6 = jefe MIPE)
      if (bloqueParaEncabezado.isNotEmpty) {
        sheetContent = _updateCellValue(sheetContent, 'D6', bloqueParaEncabezado, defaultStyleId: styleToUse);
      }
      if (jefeParaEncabezado.isNotEmpty) {
        sheetContent = _updateCellValue(sheetContent, 'J6', jefeParaEncabezado, defaultStyleId: styleToUse);
      }

      // --- Lógica de rellenado (basada en tu implementación original) ---
      const int filaPlantillaStart = 11;
      const int filasPorBloque = 7;
      final String blockXml = _extraerBlockTemplate(sheetContent, filaPlantillaStart, filasPorBloque);
      final List<String> mergesInBlock = _mergedRangesInsideBlock(mergedRanges, filaPlantillaStart, filasPorBloque);

      final int total = registros.length;
      int processed = 0;
      final List<String> bloquesNuevosXml = [];
      int bloqueIndex = 0;

      for (var registro in registros) {
        if (estaCancelado?.call() == true) {
          sendPort.send({'cancelado': true});
          return;
        }
        if (registro is! Map<String, dynamic>) {
          processed++;
          sendPort.send({'progress': (processed / total) * 0.7});
          bloqueIndex++;
          continue;
        }

        if (bloqueIndex % 8 == 0) {
          await Future<void>.delayed(Duration.zero);
          if (estaCancelado?.call() == true) {
            sendPort.send({'cancelado': true});
            return;
          }
        }

        final int startRow = filaPlantillaStart + bloqueIndex * filasPorBloque;

        String _s(dynamic v) => v == null ? '' : v.toString();

        final String fecha = _formatDate(_s(registro['fecha_registro']));
        final String semana = _s(registro['semana']);
        final dynamic diaRaw = registro.containsKey('dias') ? registro['dias'] : (registro.containsKey('dia') ? registro['dia'] : '');
        final String dia = _s(diaRaw);
        final String temperatura = _s(registro['temperatura']);

        final String blancoBiologico = _s(registro['blanco_biologico']);
        final String humedadRelativa = _s(registro['humedad_relativa']);
        final List<String> fumigadores = _parseToListStrings(registro['grupo_fumigadores']);
        final String tipoAplicacion = _s(registro['tipo_aplicacion']);
        final List<String> productos = _parseToListStrings(registro['producto']);
        final List<String> dosis = _parseToListStrings(registro['dosis']);
        final List<String> catToxic = _parseToListStrings(registro['cat_toxic']);

        final String volumenCama = _s(registro['volumen_cama']);
        final String direccion = _s(registro['direccion']);
        final String numCamas = _s(registro['num_camas']);
        final String equipo = _s(registro['equipo']);
        final String ireHoras = _s(registro['ire_horas']);
        final String facilitadorMipe = _s(registro['facilitador_mipe']);
        final String facilitadorBloque = _s(registro['facilitador_bloque']);

        // Convertir blancos a lista (si vienen concatenados o JSON)
        final List<String> blancosPorProducto = _parseToListStrings(blancoBiologico);

        if (bloqueIndex == 0) {
          // Escribir Fecha / Semana / Día en filas individuales (si ya no están mergeadas)
          sheetContent = _updateCellValue(sheetContent, 'B${startRow}', 'Fecha: $fecha', defaultStyleId: styleToUse);
          sheetContent = _updateCellValue(sheetContent, 'B${startRow + 1}', '', defaultStyleId: styleToUse);
          sheetContent = _updateCellValue(sheetContent, 'B${startRow + 2}', '', defaultStyleId: styleToUse);

          sheetContent = _updateCellValue(sheetContent, 'B${startRow + 3}', 'Semana: $semana', defaultStyleId: styleToUse);
          sheetContent = _updateCellValue(sheetContent, 'B${startRow + 4}', '', defaultStyleId: styleToUse);

          sheetContent = _updateCellValue(sheetContent, 'B${startRow + 5}', 'Día: $dia', defaultStyleId: styleToUse);
          sheetContent = _updateCellValue(sheetContent, 'B${startRow + 6}', '', defaultStyleId: styleToUse);

          // Escribir temperatura en columna F por fila
          for (int i = 0; i < filasPorBloque; i++) {
            sheetContent = _updateCellValue(sheetContent, 'F${startRow + i}', temperatura, defaultStyleId: styleToUse);
          }

          // Escribir blanco biológico por fila (uno por producto). Si hay menos blancos que filas, quedan vacíos.
          for (int i = 0; i < filasPorBloque; i++) {
            final row = startRow + i;
            final blancoValue = i < blancosPorProducto.length ? blancosPorProducto[i] : '';
            sheetContent = _updateCellValue(sheetContent, 'D${row}', blancoValue, defaultStyleId: styleToUse);
          }

          // Escribir fumigadores por fila en H
          for (int i = 0; i < filasPorBloque; i++) {
            final value = i < fumigadores.length ? fumigadores[i] : '';
            sheetContent = _updateCellValue(sheetContent, 'H${startRow + i}', value, defaultStyleId: styleToUse);
          }

          // Tipo en J (fila inicial del bloque)
          sheetContent = _updateCellValue(sheetContent, 'J${startRow}', tipoAplicacion, defaultStyleId: styleToUse);

          // Productos, dosis y cat por fila (K, M, N)
          for (int i = 0; i < filasPorBloque; i++) {
            final row = startRow + i;
            sheetContent = _updateCellValue(sheetContent, 'K${row}', i < productos.length ? productos[i] : '', defaultStyleId: styleToUse);
            sheetContent = _updateCellValue(sheetContent, 'M${row}', i < dosis.length ? dosis[i] : '', defaultStyleId: styleToUse);
            sheetContent = _updateCellValue(sheetContent, 'N${row}', i < catToxic.length ? catToxic[i] : '', defaultStyleId: styleToUse);
          }

          // Humedad y otros campos del registro
          for (int i = 0; i < filasPorBloque; i++) {
            sheetContent = _updateCellValue(
              sheetContent,
              'G${startRow + i}',
              humedadRelativa,
              defaultStyleId: styleToUse,
            );
          }
          sheetContent = _updateCellValue(sheetContent, 'O${startRow}', volumenCama, defaultStyleId: styleToUse);
          sheetContent = _updateCellValue(sheetContent, 'P${startRow}', direccion, defaultStyleId: styleToUse);
          sheetContent = _updateCellValue(sheetContent, 'Q${startRow}', numCamas, defaultStyleId: styleToUse);
          sheetContent = _updateCellValue(sheetContent, 'R${startRow}', equipo, defaultStyleId: styleToUse);
          sheetContent = _updateCellValue(sheetContent, 'S${startRow}', ireHoras, defaultStyleId: styleToUse);
          sheetContent = _updateCellValue(sheetContent, 'T${startRow}', facilitadorMipe, defaultStyleId: styleToUse);
          sheetContent = _updateCellValue(sheetContent, 'U${startRow}', facilitadorBloque, defaultStyleId: styleToUse);

          sheetContent = _centrarRangoExceptBC(sheetContent, startRow, filasPorBloque, styleToUse, mergedRanges);
        } else {
          final int destinoStartRow = filaPlantillaStart + bloqueIndex * filasPorBloque;
          final Map<String, String> valueMap = {};

          // Escribir Fecha / Semana / Día por fila
          valueMap['B${destinoStartRow}'] = 'Fecha: $fecha';
          valueMap['B${destinoStartRow + 1}'] = '';
          valueMap['B${destinoStartRow + 2}'] = '';
          valueMap['B${destinoStartRow + 3}'] = 'Semana: $semana';
          valueMap['B${destinoStartRow + 4}'] = '';
          valueMap['B${destinoStartRow + 5}'] = 'Día: $dia';
          valueMap['B${destinoStartRow + 6}'] = '';

          // Temperatura por fila
          for (int i = 0; i < filasPorBloque; i++) {
            valueMap['F${destinoStartRow + i}'] = temperatura;
            valueMap['G${destinoStartRow + i}'] = humedadRelativa;
          }

          // Blancos por fila (usar lista)
          for (int i = 0; i < filasPorBloque; i++) {
            valueMap['D${destinoStartRow + i}'] = i < blancosPorProducto.length ? blancosPorProducto[i] : '';
          }

          // Fumigadores por fila
          for (int i = 0; i < filasPorBloque; i++) {
            valueMap['H${destinoStartRow + i}'] = i < fumigadores.length ? fumigadores[i] : '';
          }

          valueMap['J${destinoStartRow}'] = tipoAplicacion;

          // Productos, dosis y cat por fila
          for (int i = 0; i < filasPorBloque; i++) {
            valueMap['K${destinoStartRow + i}'] = i < productos.length ? productos[i] : '';
            valueMap['M${destinoStartRow + i}'] = i < dosis.length ? dosis[i] : '';
            valueMap['N${destinoStartRow + i}'] = i < catToxic.length ? catToxic[i] : '';
          }

          valueMap['O${destinoStartRow}'] = volumenCama;
          valueMap['P${destinoStartRow}'] = direccion;
          valueMap['Q${destinoStartRow}'] = numCamas;
          valueMap['R${destinoStartRow}'] = equipo;
          valueMap['S${destinoStartRow}'] = ireHoras;
          valueMap['T${destinoStartRow}'] = facilitadorMipe;
          valueMap['U${destinoStartRow}'] = facilitadorBloque;

          final String newBlockXml = _cloneBlockFromTemplate(blockXml, filaPlantillaStart, destinoStartRow, valueMap, defaultStyleId: styleToUse);
          bloquesNuevosXml.add(newBlockXml);

          for (final m in mergesInBlock) {
            final String newMerge = _shiftRangeByRows(m, (destinoStartRow - filaPlantillaStart));
            sheetContent = _insertMergeCell(sheetContent, newMerge);
          }

          sheetContent = _centrarRangoExceptBC(sheetContent, destinoStartRow, filasPorBloque, styleToUse, mergedRanges);
        }

        processed++;
        final double p = (processed / total) * 0.7;
        sendPort.send({'progress': p.clamp(0.0, 1.0)});

        bloqueIndex++;
      }

      if (bloquesNuevosXml.isNotEmpty) {
        sheetContent = _insertBlocksBeforeRow(sheetContent, bloquesNuevosXml, filaPlantillaStart);
      }

      final Set<int> filasConDatos = {};
      for (int b = 0; b < bloqueIndex; b++) {
        final base = filaPlantillaStart + b * filasPorBloque;
        for (int r = 0; r < filasPorBloque; r++) filasConDatos.add(base + r);
      }

      sendPort.send({'progress': 0.78});

      if (filasConDatos.isNotEmpty) {
        // Aplicar bordes a todas las celdas con datos (excluyendo columna A si tu plantilla lo requiere)
        sheetContent = _aplicarBordesFilasConStyleExcluirA(sheetContent, filasConDatos, styleToUse);

        for (int b = 0; b < bloqueIndex; b++) {
          final base = filaPlantillaStart + b * filasPorBloque;
          sheetContent = _asegurarBordeInferiorUltimaFilaExcluirA(sheetContent, base, filasPorBloque, styleToUse);
        }

        // Si quieres quitar estilos de la columna A (por ejemplo), se hace aquí
        sheetContent = _quitarEstilosColumnaA(sheetContent, filasConDatos);
      }

      if (protegerHoja && !sheetContent.contains('<sheetProtection')) {
        sheetContent = sheetContent.replaceFirst(
          '</sheetData>',
          '</sheetData><sheetProtection sheet="1" objects="1" scenarios="1"/>',
        );
      }

      sendPort.send({'progress': 0.88});

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

      final encoded = ZipEncoder().encode(newArchive);
      if (encoded == null) {
        sendPort.send({'error': 'Error generando Excel: ZipEncoder devolvió null.'});
        return;
      }

      final Uint8List encodedBytes = Uint8List.fromList(encoded);
      sendPort.send({'progress': 1.0});
      sendPort.send({'doneBytes': encodedBytes});
    } catch (e, st) {
      try {
        sendPort.send({'error': e.toString(), 'stack': st.toString()});
      } catch (_) {}
    }
  }

  // ----------------- Helpers (completas) -----------------

  static String _extraerBlockTemplate(String sheetContent, int startRow, int rowCount) {
    final buffer = StringBuffer();
    for (int r = 0; r < rowCount; r++) {
      final rowNum = startRow + r;
      final rowRegex = RegExp('<row([^>]*)r="$rowNum"([^>]*)>(.*?)</row>', dotAll: true);
      final match = rowRegex.firstMatch(sheetContent);
      if (match != null) {
        buffer.writeln(match.group(0)!);
      } else {
        return '';
      }
    }
    return buffer.toString();
  }

  static List<String> _mergedRangesInsideBlock(List<String> mergedRanges, int startRow, int rowCount) {
    final endRow = startRow + rowCount - 1;
    final List<String> result = [];
    for (final r in mergedRanges) {
      final coords = _rangeToCoords(r);
      if (coords['r1']! >= startRow && coords['r2']! <= endRow) result.add(r);
    }
    return result;
  }

  // Versión de _cloneBlockFromTemplate que aplica defaultStyleId a celdas nuevas
  static String _cloneBlockFromTemplate(String blockXml, int templateStartRow, int newStartRow, Map<String, String> valueMap, {int? defaultStyleId}) {
    if (blockXml.isEmpty) return '';
    String newBlock = blockXml;
    final rowNumRegex = RegExp(r'r="(\d+)"');
    newBlock = newBlock.replaceAllMapped(rowNumRegex, (m) {
      final oldRow = int.parse(m.group(1)!);
      final offset = oldRow - templateStartRow;
      final newRow = newStartRow + offset;
      return 'r="$newRow"';
    });

    valueMap.forEach((ref, val) {
      if (!RegExp(r'^[A-Z]+\d+$').hasMatch(ref)) return;
      final escaped = _escapeXml(val);
      final cellRegex = RegExp(r'<c[^>]*\br="' + RegExp.escape(ref) + r'"[^>]*>(?:.*?)</c>', dotAll: true);

      if (cellRegex.hasMatch(newBlock)) {
        newBlock = newBlock.replaceFirstMapped(cellRegex, (m) {
          final tag = m.group(0)!;
          final styleMatch = RegExp(r'\bs="([^"]+)"').firstMatch(tag);
          final styleAttr = styleMatch != null ? ' s="${styleMatch.group(1)}"' : (defaultStyleId != null ? ' s="$defaultStyleId"' : '');
          return '<c r="$ref"$styleAttr t="inlineStr"><is><t>$escaped</t></is></c>';
        });
      } else {
        final column = RegExp(r'^([A-Z]+)').firstMatch(ref)!.group(1)!;
        final styleId = _getStyleForColumnInBlock(blockXml, column, templateStartRow);
        final styleAttr = styleId != null ? ' s="$styleId"' : (defaultStyleId != null ? ' s="$defaultStyleId"' : '');
        final newCell = '<c r="$ref"$styleAttr t="inlineStr"><is><t>$escaped</t></is></c>';

        final rowNum = _rowNumberFromCell(ref);
        final rowRegex = RegExp(r'(<row[^>]*r="' + rowNum.toString() + r'"[^>]*>)(.*?)(</row>)', dotAll: true);
        final rowMatch = rowRegex.firstMatch(newBlock);
        if (rowMatch != null) {
          final before = rowMatch.group(1)!;
          final inner = rowMatch.group(2)!;
          final after = rowMatch.group(3)!;
          final newInner = inner + newCell;
          newBlock = newBlock.replaceRange(rowMatch.start, rowMatch.end, before + newInner + after);
        } else {
          newBlock = newBlock + newCell;
        }
      }
    });

    return newBlock;
  }

  static String? _getStyleForColumnInBlock(String blockXml, String column, int templateStartRow) {
    final ref = '$column$templateStartRow';
    final cellRegex = RegExp(r'<c([^>]*?)\br="' + RegExp.escape(ref) + r'"([^>]*)>(?:.*?)</c>', dotAll: true);
    final m = cellRegex.firstMatch(blockXml);
    if (m != null) {
      final attrs = (m.group(1) ?? '') + ' ' + (m.group(2) ?? '');
      final styleMatch = RegExp(r'\bs="([^"]+)"').firstMatch(attrs);
      if (styleMatch != null) return styleMatch.group(1);
    }
    return null;
  }

  static String _insertBlocksBeforeRow(String sheetContent, List<String> blocksXml, int insertBeforeRow) {
    final rowRegex = RegExp('<row([^>]*)r="' + insertBeforeRow.toString() + r'"([^>]*)>(.*?)</row>', dotAll: true);
    final match = rowRegex.firstMatch(sheetContent);
    if (match != null) {
      final originalRow = match.group(0)!;
      final buffer = StringBuffer();
      for (final b in blocksXml) buffer.writeln(b);
      buffer.writeln(originalRow);
      return sheetContent.replaceRange(match.start, match.end, buffer.toString());
    } else {
      final sheetDataRegex = RegExp(r'(<sheetData[^>]*>)(.*?)(</sheetData>)', dotAll: true);
      final sdMatch = sheetDataRegex.firstMatch(sheetContent);
      if (sdMatch != null) {
        final before = sdMatch.group(1)!;
        final inner = sdMatch.group(2)!;
        final after = sdMatch.group(3)!;
        final newInner = inner + blocksXml.join('\n');
        return sheetContent.replaceRange(sdMatch.start, sdMatch.end, before + newInner + after);
      }
    }
    return sheetContent;
  }

  static String _insertMergeCell(String sheetContent, String mergeRef) {
    final mergeCellsRegex = RegExp(r'(<mergeCells[^>]*>)(.*?)(</mergeCells>)', dotAll: true);
    final match = mergeCellsRegex.firstMatch(sheetContent);
    final newEntry = '<mergeCell ref="$mergeRef"/>';
    if (match != null) {
      final inner = match.group(2)!;
      if (inner.contains('ref="$mergeRef"')) return sheetContent;
      final newInner = inner + newEntry;
      return sheetContent.replaceRange(match.start, match.end, match.group(1)! + newInner + match.group(3)!);
    } else {
      final insertAfter = RegExp(r'(</sheetPr>)', dotAll: true).firstMatch(sheetContent);
      if (insertAfter != null) {
        final pos = insertAfter.end;
        final toInsert = '<mergeCells count="1">$newEntry</mergeCells>';
        return sheetContent.substring(0, pos) + toInsert + sheetContent.substring(pos);
      }
    }
    return sheetContent;
  }

  static String _shiftRangeByRows(String range, int rowOffset) {
    final coords = _rangeToCoords(range);
    final newStart = '${_colNumberToLetters(coords['c1']!)}${coords['r1']! + rowOffset}';
    final newEnd = '${_colNumberToLetters(coords['c2']!)}${coords['r2']! + rowOffset}';
    return '$newStart:$newEnd';
  }

  static List<String> _extraerMergedRanges(String sheetXml) {
    final List<String> ranges = [];
    final mcMatch = RegExp(r'<mergeCells[^>]*>(.*?)</mergeCells>', dotAll: true).firstMatch(sheetXml);
    if (mcMatch == null) return ranges;
    final content = mcMatch.group(1)!;
    final iter = RegExp(r'<mergeCell\s+ref="([^"]+)"\s*/>').allMatches(content);
    for (final m in iter) ranges.add(m.group(1)!);
    return ranges;
  }

  static String _applyStyleRespectingMerged(String sheetContent, String cellRef, int styleId, List<String> mergedRanges) {
    for (final range in mergedRanges) {
      if (_isCellInRange(cellRef, range)) {
        return _applyStyleToRange(sheetContent, range, styleId);
      }
    }
    return _forzarEstiloEnCelda(sheetContent, cellRef, styleId);
  }

  static String _applyStyleToRange(String sheetContent, String range, int styleId) {
    final coords = _rangeToCoords(range);
    String resultado = sheetContent;
    for (int r = coords['r1']!; r <= coords['r2']!; r++) {
      for (int c = coords['c1']!; c <= coords['c2']!; c++) {
        final col = _colNumberToLetters(c);
        final cellRef = '$col$r';
        resultado = _forzarEstiloEnCelda(resultado, cellRef, styleId);
      }
    }
    return resultado;
  }

  static String _centrarRangoExceptBC(String sheetContent, int startRow, int count, int styleId, List<String> mergedRanges) {
    final List<String> allCols = List.generate(21, (i) => String.fromCharCode(65 + i)); // A..U
    final List<String> columnas = allCols.where((c) => c != 'B' && c != 'C').toList();

    String resultado = sheetContent;
    for (int r = 0; r < count; r++) {
      final fila = startRow + r;
      for (final col in columnas) {
        final cellRef = '$col$fila';
        bool applied = false;
        for (final range in mergedRanges) {
          if (_isCellInRange(cellRef, range)) {
            resultado = _applyStyleToRange(resultado, range, styleId);
            applied = true;
            break;
          }
        }
        if (!applied) {
          resultado = _forzarEstiloEnCelda(resultado, cellRef, styleId);
        }
      }
    }
    return resultado;
  }

  static Map<String,int> _rangeToCoords(String range) {
    final parts = range.split(':');
    final start = parts[0];
    final end = parts.length > 1 ? parts[1] : parts[0];
    final startCol = _columnNumberFromCell(start);
    final startRow = _rowNumberFromCell(start);
    final endCol = _columnNumberFromCell(end);
    final endRow = _rowNumberFromCell(end);
    return {'c1': startCol, 'r1': startRow, 'c2': endCol, 'r2': endRow};
  }

  static bool _isCellInRange(String cellRef, String range) {
    final coords = _rangeToCoords(range);
    final c = _columnNumberFromCell(cellRef);
    final r = _rowNumberFromCell(cellRef);
    return c >= coords['c1']! && c <= coords['c2']! && r >= coords['r1']! && r <= coords['r2']!;
  }

  static String _colNumberToLetters(int col) {
    var n = col;
    var s = '';
    while (n > 0) {
      final rem = (n - 1) % 26;
      s = String.fromCharCode(65 + rem) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  static List<String> _parseToListStrings(dynamic field) {
    if (field == null) return [];
    if (field is List) return field.map((e) => e?.toString() ?? '').toList();
    if (field is String) {
      final s = field.trim();
      if (s.isEmpty) return [];
      try {
        final decoded = jsonDecode(s);
        if (decoded is List) return decoded.map((e) => e?.toString() ?? '').toList();
      } catch (_) {}
      return s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }
    return [field.toString()];
  }

  static String _formatDate(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final dd = dt.day.toString().padLeft(2, '0');
      final mm = dt.month.toString().padLeft(2, '0');
      final yyyy = dt.year.toString();
      return '$dd/$mm/$yyyy';
    } catch (_) {
      return iso;
    }
  }

  // ---------------- XML helpers básicos ----------------

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
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

  // ---------------- Estilos: agregar borde y obtener styleId ----------------

  /// Asegura que stylesContent tenga un borde y un xf con alignment centrado y border.
  /// Devuelve el stylesContent modificado.
  static String _agregarEstilosConBorde(String stylesContent) {
    // Asegurar que exista la sección <borders> con al menos 1 border
    if (!stylesContent.contains('<borders')) {
      // crear estructura mínima
      final insertPos = stylesContent.indexOf('</styleSheet>');
      final toInsert = '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>';
      stylesContent = stylesContent.replaceRange(insertPos, insertPos, toInsert);
    } else {
      // si no hay borders dentro, añadir uno
      final bordersMatch = RegExp(r'<borders[^>]*>(.*?)</borders>', dotAll: true).firstMatch(stylesContent);
      if (bordersMatch != null) {
        final inner = bordersMatch.group(1)!;
        final countMatch = RegExp(r'count="(\d+)"').firstMatch(bordersMatch.group(0)!);
        final count = countMatch != null ? int.tryParse(countMatch.group(1)!) ?? 0 : 0;
        if (count < 1) {
          final newInner = '<border><left/><right/><top/><bottom/><diagonal/></border>' + inner;
          final newBorders = bordersMatch.group(0)!.replaceFirst(inner, newInner);
          stylesContent = stylesContent.replaceRange(bordersMatch.start, bordersMatch.end, newBorders);
          stylesContent = stylesContent.replaceFirst(RegExp(r'count="\d+"'), 'count="${count + 1}"');
        }
      }
    }

    // Asegurar que exista cellXfs y añadir un xf con border y alignment si no existe
    final cellXfsMatch = RegExp(r'<cellXfs[^>]*>(.*?)</cellXfs>', dotAll: true).firstMatch(stylesContent);
    if (cellXfsMatch != null) {
      final inner = cellXfsMatch.group(1)!;
      // Buscar si ya existe un xf con applyAlignment="1" y borderId (indicador de estilo centrado+borde)
      if (!RegExp(r'<xf[^>]*applyAlignment="1"[^>]*>').hasMatch(inner)) {
        // Añadir un xf al final con applyAlignment y borderId="0" (usamos el primer border)
        final newXf = '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>';
        final newInner = inner + newXf;
        final newCellXfs = cellXfsMatch.group(0)!.replaceFirst(inner, newInner);
        stylesContent = stylesContent.replaceRange(cellXfsMatch.start, cellXfsMatch.end, newCellXfs);
        // actualizar count si existe
        stylesContent = stylesContent.replaceFirstMapped(RegExp(r'<cellXfs[^>]*count="(\d+)"'), (m) {
          final c = int.tryParse(m.group(1)!) ?? 0;
          return m.group(0)!.replaceFirst('count="${m.group(1)}"', 'count="${c + 1}"');
        });
      }
    } else {
      // No existe cellXfs: crear una mínima con un xf centrado
      final insertPos = stylesContent.indexOf('</styleSheet>');
      final cellXfs = '<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf></cellXfs>';
      stylesContent = stylesContent.replaceRange(insertPos, insertPos, cellXfs);
    }

    return stylesContent;
  }

  /// Busca en stylesContent el índice (0-based) del primer xf que tenga applyAlignment="1"
  /// y una etiqueta <alignment horizontal="center"...>. Devuelve null si no encuentra.
  static int? _obtenerStyleIdConBordeYWrap(String stylesContent) {
    final cellXfsMatch = RegExp(r'<cellXfs[^>]*>(.*?)</cellXfs>', dotAll: true).firstMatch(stylesContent);
    if (cellXfsMatch == null) return null;
    final inner = cellXfsMatch.group(1)!;
    final iter = RegExp(r'<xf\b[^>]*>').allMatches(inner).toList();
    for (int i = 0; i < iter.length; i++) {
      final xfTag = iter[i].group(0)!;
      final xfFullMatch = RegExp(r'(<xf\b[^>]*>)(.*?)</xf>', dotAll: true).firstMatch(inner.substring(iter[i].start));
      // Simpler: check xfTag and following content for alignment
      final xfIndexStart = iter[i].start;
      final xfIndexEnd = (i + 1 < iter.length) ? iter[i + 1].start : inner.length;
      final xfBlock = inner.substring(xfIndexStart, xfIndexEnd);
      if (xfBlock.contains('applyAlignment="1"') || xfBlock.contains('<alignment')) {
        // return index i (styleId)
        return i;
      }
    }
    return null;
  }

  // ---------------- Manipulación de celdas en sheet1.xml ----------------

  // Inserta o actualiza el valor de una celda (preserva estilos s="..." si existen)
  // Añadí parámetro defaultStyleId para poder asignar estilo al crear celdas nuevas.
  static String _updateCellValue(String xmlContent, String cellRef, dynamic value, {int? defaultStyleId}) {
    if (value == null) return xmlContent;
    final String strValue = value.toString();
    if (strValue.isEmpty) return xmlContent;

    // Detectar si el valor es numérico (solo si la cadena representa un número)
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
      final styleAttr = styleMatch != null ? ' s="${styleMatch.group(1)}"' : (defaultStyleId != null ? ' s="$defaultStyleId"' : '');

      if (isNumeric) {
        // Si es entero, quitar decimales innecesarios
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
        ? _buildNumericCell(cellRef, (numeric == numeric.roundToDouble() ? numeric.toInt().toString() : numeric.toString()), defaultStyleId != null ? ' s="$defaultStyleId"' : '')
        : _buildInlineStringCell(cellRef, strValue, defaultStyleId != null ? ' s="$defaultStyleId"' : '');

    final newRowContent = rowContent.substring(0, insertIndex) +
        newCellXml +
        rowContent.substring(insertIndex);

    final newRowXml = rowXml.replaceRange(rowContentMatch.start, rowContentMatch.end, newRowContent);
    return xmlContent.replaceRange(rowMatch.start, rowMatch.end, newRowXml);
  }

  // Construye una celda inlineStr; añade xml:space="preserve" si hay espacios al inicio/final
  static String _buildInlineStringCell(String cellRef, String value, String styleAttr) {
    final escaped = _escapeXml(value);
    final preserveSpace = value.startsWith(' ') || value.endsWith(' ');
    final spaceAttr = preserveSpace ? ' xml:space="preserve"' : '';
    final style = styleAttr.isNotEmpty ? styleAttr : '';
    return '<c r="$cellRef"$style t="inlineStr"><is><t$spaceAttr>$escaped</t></is></c>';
  }

  // Construye una celda numérica (tipo n) con valor en <v>
  static String _buildNumericCell(String cellRef, String value, String styleAttr) {
    final style = styleAttr.isNotEmpty ? styleAttr : '';
    return '<c r="$cellRef"$style t="n"><v>$value</v></c>';
  }

  // Forzar estilo en una celda (añade o reemplaza s="...") — usado para aplicar bordes/centrado
  static String _forzarEstiloEnCelda(String xmlContent, String cellRef, int styleId) {
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

    // Si la celda no existe, crearla dentro de la fila
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

  // ---------------- Aplicar bordes a filas con datos (excluir columna A si se desea) ----------------

  static String _aplicarBordesFilasConStyleExcluirA(String sheetContent, Set<int> filasConDatos, int styleId) {
    final columnas = ['B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U'];
    String resultado = sheetContent;
    for (final fila in filasConDatos) {
      for (final col in columnas) {
        final cellRef = '$col$fila';
        resultado = _forzarEstiloEnCelda(resultado, cellRef, styleId);
      }
    }
    return resultado;
  }

  // Asegura que la última fila del bloque tenga borde inferior (si tu plantilla requiere ajustes)
  static String _asegurarBordeInferiorUltimaFilaExcluirA(String sheetContent, int baseRow, int filasPorBloque, int styleId) {
    final lastRow = baseRow + filasPorBloque - 1;
    final columnas = ['B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U'];
    String resultado = sheetContent;
    for (final col in columnas) {
      final cellRef = '$col$lastRow';
      resultado = _forzarEstiloEnCelda(resultado, cellRef, styleId);
    }
    return resultado;
  }

  // Quitar estilos de la columna A si no quieres bordes allí (opcional)
  static String _quitarEstilosColumnaA(String sheetContent, Set<int> filasConDatos) {
    String resultado = sheetContent;
    for (final fila in filasConDatos) {
      final cellRef = 'A$fila';
      final cellRegex = RegExp('<c([^>]*)r="$cellRef"([^>]*)/>|<c([^>]*)r="$cellRef"([^>]*)>(.*?)</c>', dotAll: true);
      final match = cellRegex.firstMatch(resultado);
      if (match != null) {
        String cellTag = match.group(0)!;
        // eliminar atributo s="..."
        cellTag = cellTag.replaceAll(RegExp(r'\s*s="\d+"'), '');
        resultado = resultado.replaceRange(match.start, match.end, cellTag);
      }
    }
    return resultado;
  }
}

// ----------------- Payload wrapper -----------------
class _IsolatePayload {
  final Map<String, dynamic> message;
  _IsolatePayload(this.message);
}

class MIPECancellationToken {
  SendPort? _sendPort;
  bool _cancelRequested = false;

  void _attach(SendPort sendPort) {
    _sendPort = sendPort;
    if (_cancelRequested) sendPort.send('cancelar');
  }

  void cancel() {
    _cancelRequested = true;
    _sendPort?.send('cancelar');
  }
}

class MIPECanceledException implements Exception {
  const MIPECanceledException();
}
