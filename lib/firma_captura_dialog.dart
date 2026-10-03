import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Diálogo reutilizable para dibujar una firma.
/// Devuelve la firma como PNG en base64, o null si se cancela.
/// Es la misma lógica que usa el formulario de almacén.
Future<String?> mostrarDialogoFirma(
  BuildContext context, {
  required String titulo,
  String subtitulo = 'La firma se guardará con este registro.',
  Color color = const Color(0xFF008DC5),
}) {
  final firmaCanvasKey = GlobalKey();
  final trazos = <Offset?>[];

  return showDialog<String>(
    context: context,
    builder:
        (dialogContext) => StatefulBuilder(
          builder:
              (context, setDialogState) => Dialog(
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 460,
                    maxHeight: MediaQuery.of(context).size.height * 0.88,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(Icons.draw_rounded, color: color),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      titulo,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      subtitulo,
                                      style: const TextStyle(
                                        color: Colors.blueGrey,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Cerrar',
                                onPressed:
                                    () => Navigator.of(dialogContext).pop(),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Container(
                            height: 190,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAFCFD),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFD7E1E7),
                              ),
                            ),
                            child: Stack(
                              children: [
                                RepaintBoundary(
                                  key: firmaCanvasKey,
                                  child: GestureDetector(
                                    onPanStart:
                                        (details) => setDialogState(
                                          () => trazos.add(
                                            details.localPosition,
                                          ),
                                        ),
                                    onPanUpdate:
                                        (details) => setDialogState(
                                          () => trazos.add(
                                            details.localPosition,
                                          ),
                                        ),
                                    onPanEnd:
                                        (_) => setDialogState(
                                          () => trazos.add(null),
                                        ),
                                    child: CustomPaint(
                                      painter: FirmaTrazosPainter(trazos),
                                      child: const SizedBox.expand(),
                                    ),
                                  ),
                                ),
                                if (trazos.isEmpty)
                                  const Positioned.fill(
                                    child: IgnorePointer(
                                      child: Center(
                                        child: Text(
                                          'Firme aquí',
                                          style: TextStyle(
                                            color: Colors.blueGrey,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed:
                                    trazos.isEmpty
                                        ? null
                                        : () => setDialogState(trazos.clear),
                                icon: const Icon(Icons.delete_outline_rounded),
                                label: const Text('Borrar'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed:
                                      () => Navigator.of(dialogContext).pop(),
                                  child: const Text('Cancelar'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed:
                                      trazos.whereType<Offset>().length < 2
                                          ? null
                                          : () async {
                                            final firma =
                                                await _firmaDesdeCanvas(
                                                  firmaCanvasKey,
                                                  trazos,
                                                );
                                            if (firma != null &&
                                                dialogContext.mounted) {
                                              Navigator.of(
                                                dialogContext,
                                              ).pop(firma);
                                            }
                                          },
                                  icon: const Icon(Icons.check_rounded),
                                  label: const Text('Guardar firma'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        ),
  );
}

Future<String?> _firmaDesdeCanvas(
  GlobalKey canvasKey,
  List<Offset?> trazos,
) async {
  if (trazos.whereType<Offset>().length < 2) return null;
  try {
    final renderObject = canvasKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;
    final image = await renderObject.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) return null;
    return base64Encode(byteData.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

class FirmaTrazosPainter extends CustomPainter {
  final List<Offset?> strokes;
  const FirmaTrazosPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.white, BlendMode.src);
    final paint =
        Paint()
          ..color = const Color(0xFF17324D)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
    for (var index = 0; index < strokes.length - 1; index++) {
      final start = strokes[index];
      final end = strokes[index + 1];
      if (start != null && end != null) canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant FirmaTrazosPainter oldDelegate) => true;
}
