import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';

import 'firma_digital_service.dart';
import 'login_controller.dart';

class FirmaDigitalPage extends StatefulWidget {
  const FirmaDigitalPage({super.key});

  @override
  State<FirmaDigitalPage> createState() => _FirmaDigitalPageState();
}

class _FirmaDigitalPageState extends State<FirmaDigitalPage> {
  static const Color _blue = Color(0xFF008DC5);
  final LoginController _login = Get.find<LoginController>();
  final GlobalKey _canvasKey = GlobalKey();
  final List<Offset?> _strokes = [];
  String? _firmaActual;
  bool _loading = true;
  bool _saving = false;

  String get _identificacion =>
      _login.loggedInUser.value?['identificacion']?.toString() ?? '';
  String get _nombre =>
      _login.loggedInUser.value?['nombres']?.toString() ?? 'Usuario';

  @override
  void initState() {
    super.initState();
    _cargarFirma();
  }

  Future<void> _cargarFirma() async {
    final password = _login.passwordEnMemoria;
    if (_identificacion.isEmpty || password == null || password.isEmpty) {
      final cache = await FirmaDigitalService.leerCache(_identificacion);
      if (!mounted) return;
      setState(() {
        _firmaActual = _firmaDe(cache, _identificacion);
        _loading = false;
      });
      return;
    }
    final firmas = await FirmaDigitalService.obtenerFirmas(
      supabaseUrl: _login.supabaseUrl,
      apiKey: _login.apiKey,
      identificacion: _identificacion,
      password: password,
    );
    if (!mounted) return;
    setState(() {
      _firmaActual = _firmaDe(firmas, _identificacion);
      _loading = false;
    });
  }

  String? _firmaDe(List<Map<String, dynamic>> firmas, String identificacion) {
    for (final firma in firmas) {
      if (firma['identificacion']?.toString() == identificacion) {
        final imagen = firma['firma_png_base64']?.toString();
        if (imagen != null && imagen.isNotEmpty) return imagen;
      }
    }
    return null;
  }

  Future<String?> _pedirPassword() async {
    final controller = TextEditingController();
    final password = await Get.dialog<String>(
      AlertDialog(
        title: const Text('Confirma tu contraseña'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Contraseña actual'),
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Get.back(result: controller.text),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    controller.dispose();
    return password;
  }

  Future<void> _guardar() async {
    if (_strokes.whereType<Offset>().length < 2) {
      Get.snackbar('Firma vacía', 'Dibuja tu firma antes de guardarla.');
      return;
    }
    if (_login.esVisitante || _identificacion.isEmpty) {
      Get.snackbar('Acceso no disponible', 'Inicia sesión con tu usuario para registrar una firma.');
      return;
    }

    setState(() => _saving = true);
    try {
      final boundary = _canvasKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) throw Exception('No se pudo preparar la imagen.');
      final signature = base64Encode(byteData.buffer.asUint8List());
      final password = _login.passwordEnMemoria ?? await _pedirPassword();
      if (password == null || password.isEmpty) return;

      await FirmaDigitalService.guardarFirma(
        supabaseUrl: _login.supabaseUrl,
        apiKey: _login.apiKey,
        identificacion: _identificacion,
        password: password,
        firmaPngBase64: signature,
      );
      if (!mounted) return;
      setState(() {
        _firmaActual = signature;
        _strokes.clear();
      });
      Get.snackbar('Firma guardada', 'Se usará en tus registros de almacén.');
    } catch (error) {
      Get.snackbar('No se pudo guardar', error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _eliminarFirma() async {
    final confirmar = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Eliminar firma'),
        content: const Text(
          'La firma dejará de aparecer en los próximos registros. Las copias guardadas en registros anteriores se conservarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    final password = _login.passwordEnMemoria ?? await _pedirPassword();
    if (password == null || password.isEmpty) return;

    setState(() => _saving = true);
    try {
      await FirmaDigitalService.eliminarFirma(
        supabaseUrl: _login.supabaseUrl,
        apiKey: _login.apiKey,
        identificacion: _identificacion,
        password: password,
      );
      if (!mounted) return;
      setState(() => _firmaActual = null);
      Get.snackbar('Firma eliminada', 'Ya no se usará en nuevos registros.');
    } catch (error) {
      Get.snackbar(
        'No se pudo eliminar',
        error.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text('Mi firma'),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _nombre,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Dibuja tu firma una vez. Aparecerá automáticamente en los registros que asegures.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.blueGrey),
                ),
                const SizedBox(height: 20),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_firmaActual != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      children: [
                        const Text('Firma guardada'),
                        const SizedBox(height: 8),
                        Image.memory(base64Decode(_firmaActual!), height: 72),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _eliminarFirma,
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.redAccent,
                          ),
                          label: const Text('Eliminar firma guardada'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _blue.withOpacity(0.25)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      height: 220,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: RepaintBoundary(
                              key: _canvasKey,
                              child: GestureDetector(
                                onPanStart: (details) => setState(
                                  () => _strokes.add(details.localPosition),
                                ),
                                onPanUpdate: (details) => setState(
                                  () => _strokes.add(details.localPosition),
                                ),
                                onPanEnd: (_) => setState(() => _strokes.add(null)),
                                child: CustomPaint(
                                  painter: _FirmaPainter(_strokes),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                          ),
                          if (_strokes.isEmpty)
                            const Positioned.fill(
                              child: IgnorePointer(
                                child: Center(
                                  child: Text(
                                    'Firma aquí',
                                    style: TextStyle(
                                      color: Color(0x553D596B),
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: _saving ? null : () => setState(_strokes.clear),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Borrar y volver a dibujar'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _saving ? null : _guardar,
                  icon: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(_saving ? 'Guardando...' : 'Guardar mi firma'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FirmaPainter extends CustomPainter {
  final List<Offset?> strokes;
  const _FirmaPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.white, BlendMode.src);
    final paint = Paint()
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
  bool shouldRepaint(covariant _FirmaPainter oldDelegate) => true;
}
