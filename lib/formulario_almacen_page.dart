import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart'; // Asegúrate de tener intl en tu pubspec.yaml
import 'dart:async';
import 'login_controller.dart';
import 'offline_sync_service.dart';
import 'firma_digital_service.dart';

class AseguramientoPage extends StatefulWidget {
  final Map<String, dynamic>? dataInicial; // Datos que vienen del historial
  final bool esLectura; // Para saber si bloqueamos el formulario

  const AseguramientoPage({
    super.key,
    this.dataInicial,
    this.esLectura = false,
  });

  @override
  State<AseguramientoPage> createState() => _AseguramientoPageState();
}

class _AseguramientoPageState extends State<AseguramientoPage> {
  final _formKey = GlobalKey<FormState>();
  final LoginController loginController = Get.find<LoginController>();
  bool _isSaving = false;

  final Color brandBlue = const Color(0xFF008DC5);
  final Color brandGreen = const Color(0xFF1DB954);

  // --- CONTROLADORES ---
  final _semanaController = TextEditingController();
  final _productoController = TextEditingController();
  final _proveedorController = TextEditingController();
  final _formulaCController = TextEditingController();
  final _catToxicController = TextEditingController();
  final _presentacionController =
      TextEditingController(); // Unidad de medida (Texto)
  final _unidadesController = TextEditingController(); // Total unidades (Int)
  final _loteController = TextEditingController(); // # Lote (Texto)
  final _vencimientoController = TextEditingController(); // Fecha (Texto/Date)
  final _cantidadController =
      TextEditingController(); // Cantidad cc/g (Numeric)
  final _colorController = TextEditingController(); // Color (Texto)
  final _otroColorController = TextEditingController();
  final _phController = TextEditingController(); // pH (Numeric)
  final _densidadController = TextEditingController(); // Densidad (Numeric)
  final _obsController = TextEditingController(); // Observaciones (Texto)
  final _aseguraController = TextEditingController();
  final _autorizaController = TextEditingController();

  final List<int> _semanas = [];
  final List<String> _productos = [];
  final List<String> _proveedores = [];
  final List<String> _presentaciones = [];
  final List<String> _colores = [];
  final List<String> _formulasC = [];
  final List<String> _categoriasToxicologicas = [];
  final List<String> _administradores = [];
  final Map<String, String> _identificacionAdminPorNombre = {};
  final Map<String, String> _firmasPorIdentificacion = {};

  // --- ESTADOS BOTONES SELECCIÓN ---
  String _estadoEtiqueta = 'CUMPLE';
  String _estadoTapa = 'CUMPLE';
  String _sellos = 'CUMPLE';
  String _puntosextraccion = 'CUMPLE';

  int get _porcentajeCumplimiento {
    final criterios = [
      _estadoEtiqueta,
      _estadoTapa,
      _sellos,
      _puntosextraccion,
    ];
    final cumplidos =
        criterios
            .where((estado) => estado.trim().toUpperCase() == 'CUMPLE')
            .length;
    return cumplidos * 25;
  }

  String get _cumplimiento =>
      _porcentajeCumplimiento == 100 ? 'CUMPLE' : 'NO CUMPLE';

  @override
  void initState() {
    super.initState();
    // Si recibimos datos, llenamos los controladores
    if (widget.dataInicial != null) {
      _semanaController.text = widget.dataInicial!['semana']?.toString() ?? '';
      _productoController.text = widget.dataInicial!['nombre_producto'] ?? '';
      _proveedorController.text = widget.dataInicial!['proveedor'] ?? '';
      _formulaCController.text = widget.dataInicial!['formula_c'] ?? '';
      _catToxicController.text = widget.dataInicial!['cat_toxic'] ?? '';
      _presentacionController.text = widget.dataInicial!['presentacion'] ?? '';
      _unidadesController.text =
          widget.dataInicial!['total_unidades']?.toString() ?? '';
      _loteController.text = widget.dataInicial!['lote'] ?? '';
      _vencimientoController.text =
          widget.dataInicial!['fecha_vencimiento'] ?? '';
      _cantidadController.text =
          widget.dataInicial!['cantidad_cc_g']?.toString() ?? '';
      _colorController.text = widget.dataInicial!['color'] ?? '';
      _otroColorController.text = widget.dataInicial!['color'] ?? '';
      _phController.text = widget.dataInicial!['ph']?.toString() ?? '';
      _densidadController.text =
          widget.dataInicial!['densidad']?.toString() ?? '';
      _obsController.text = widget.dataInicial!['observaciones'] ?? '';
      _aseguraController.text =
          widget.dataInicial?['nombre_quien_asegura'] ??
          widget.dataInicial?['identificacion_asegura'] ??
          '';
      _autorizaController.text =
          widget.dataInicial?['nombre_autoriza'] ??
          widget.dataInicial?['autorizacion'] ??
          '';

      // Actualizamos los estados de los botones
      _estadoEtiqueta = widget.dataInicial!['estado_etiqueta'] ?? 'CUMPLE';
      _estadoTapa = widget.dataInicial!['estado_tapa'] ?? 'CUMPLE';
      _sellos = widget.dataInicial!['sellos'] ?? 'CUMPLE';
      _puntosextraccion = widget.dataInicial!['puntos_extraccion'] ?? 'CUMPLE';
    } else {
      _semanaController.text = _semanaActual().toString();
      _aseguraController.text =
          loginController.loggedInUser.value?['nombres']?.toString() ?? '';
    }
    _cargarCatalogos();
    _cargarAdministradores();
    _cargarFirmas();
  }

  Future<void> _cargarAdministradores() async {
    try {
      final uri = Uri.parse(
        '${loginController.supabaseUrl}/rest/v1/persona',
      ).replace(
        queryParameters: {
          'select': 'nombres,identificacion',
          'admin': 'eq.S',
          'order': 'nombres.asc',
        },
      );
      final registros = await OfflineSyncService.fetchListWithCache(
        cacheKey: 'cache_persona_administradores',
        url: uri,
        headers: {
          'apikey': loginController.apiKey,
          'Authorization': 'Bearer ${loginController.apiKey}',
        },
      );
      final nombres =
          registros
              .whereType<Map>()
              .map((registro) => registro['nombres']?.toString().trim() ?? '')
              .where((nombre) => nombre.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      final identificaciones = <String, String>{};
      for (final registro in registros.whereType<Map>()) {
        final nombre = registro['nombres']?.toString().trim() ?? '';
        final identificacion =
            registro['identificacion']?.toString().trim() ?? '';
        if (nombre.isNotEmpty && identificacion.isNotEmpty) {
          identificaciones[nombre] = identificacion;
        }
      }

      final nombreActual =
          loginController.loggedInUser.value?['nombres']?.toString().trim();
      if (nombres.isEmpty &&
          loginController.loggedInUser.value?['admin']?.toString().trim() ==
              'S' &&
          nombreActual != null &&
          nombreActual.isNotEmpty) {
        nombres.add(nombreActual);
        final idActual =
            loginController.loggedInUser.value?['identificacion']
                ?.toString()
                .trim();
        if (idActual != null && idActual.isNotEmpty) {
          identificaciones[nombreActual] = idActual;
        }
      }

      if (!mounted) return;
      setState(() {
        _administradores
          ..clear()
          ..addAll(nombres);
        _identificacionAdminPorNombre
          ..clear()
          ..addAll(identificaciones);
        if (_autorizaController.text.trim().isEmpty && nombres.length == 1) {
          _autorizaController.text = nombres.first;
        }
      });
    } catch (e) {
      debugPrint('No se pudieron cargar los administradores: $e');
    }
  }

  Future<void> _cargarFirmas() async {
    final identificacion =
        loginController.loggedInUser.value?['identificacion']?.toString() ?? '';
    if (identificacion.isEmpty || loginController.esVisitante) return;
    final password = loginController.passwordEnMemoria;
    final firmas =
        password == null || password.isEmpty
            ? await FirmaDigitalService.leerCache(identificacion)
            : await FirmaDigitalService.obtenerFirmas(
              supabaseUrl: loginController.supabaseUrl,
              apiKey: loginController.apiKey,
              identificacion: identificacion,
              password: password,
            );
    if (!mounted) return;
    setState(() {
      _firmasPorIdentificacion
        ..clear()
        ..addEntries(
          firmas
              .where((firma) {
                final imagen = firma['firma_png_base64']?.toString() ?? '';
                return imagen.isNotEmpty;
              })
              .map(
                (firma) => MapEntry(
                  firma['identificacion'].toString(),
                  firma['firma_png_base64'].toString(),
                ),
              ),
        );
    });
  }

  String? _firmaAdministradorSeleccionado() {
    final identificacion = _identificacionAdminSeleccionado();
    return identificacion == null
        ? null
        : _firmasPorIdentificacion[identificacion];
  }

  String? _identificacionAdminSeleccionado() {
    final nombre = _autorizaController.text;
    String? identificacion;
    for (final entry in _identificacionAdminPorNombre.entries) {
      if (entry.key.toLowerCase() == nombre.toLowerCase()) {
        identificacion = entry.value;
        break;
      }
    }
    return identificacion;
  }

  Widget _vistaFirma(String? firma, String etiqueta) {
    if (firma == null || firma.isEmpty) return const SizedBox.shrink();
    try {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            const SizedBox(width: 48),
            Container(
              constraints: const BoxConstraints(maxWidth: 240),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: brandBlue.withOpacity(0.18)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Image.memory(
                base64Decode(firma),
                height: 48,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              etiqueta,
              style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
            ),
          ],
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  int _semanaActual() {
    final hoy = DateTime.now();
    final juevesActual = hoy.add(
      Duration(days: DateTime.thursday - hoy.weekday),
    );
    final cuatroDeEnero = DateTime(juevesActual.year, 1, 4);
    final primerJueves = cuatroDeEnero.add(
      Duration(days: DateTime.thursday - cuatroDeEnero.weekday),
    );
    final semana = 1 + juevesActual.difference(primerJueves).inDays ~/ 7;

    // El catálogo de semanas de la aplicación llega hasta la semana 52.
    return semana > 52 ? 52 : semana;
  }

  @override
  void dispose() {
    _semanaController.dispose();
    _productoController.dispose();
    _proveedorController.dispose();
    _formulaCController.dispose();
    _catToxicController.dispose();
    _presentacionController.dispose();
    _unidadesController.dispose();
    _loteController.dispose();
    _vencimientoController.dispose();
    _cantidadController.dispose();
    _colorController.dispose();
    _otroColorController.dispose();
    _phController.dispose();
    _densidadController.dispose();
    _obsController.dispose();
    _aseguraController.dispose();
    _autorizaController.dispose();
    super.dispose();
  }

  Future<List<dynamic>> _fetchCatalogo(
    String table,
    String select, {
    String? order,
  }) async {
    final uri = Uri.parse(
      '${loginController.supabaseUrl}/rest/v1/$table',
    ).replace(
      queryParameters: {'select': select, if (order != null) 'order': order},
    );
    return OfflineSyncService.fetchListWithCache(
      cacheKey: 'cache_catalogo_$table',
      url: uri,
      headers: {
        'apikey': loginController.apiKey,
        'Authorization': 'Bearer ${loginController.apiKey}',
      },
    );
  }

  Future<void> _cargarCatalogos() async {
    try {
      final resultados = await Future.wait([
        _fetchCatalogo('aseguramiento_semanas', 'numero', order: 'numero.asc'),
        _fetchCatalogo(
          'aseguramiento_productos',
          'nombre',
          order: 'nombre.asc',
        ),
        _fetchCatalogo(
          'aseguramiento_proveedores',
          'nombre',
          order: 'nombre.asc',
        ),
        _fetchCatalogo(
          'aseguramiento_presentaciones',
          'nombre',
          order: 'nombre.asc',
        ),
        _fetchCatalogo('aseguramiento_colores', 'nombre', order: 'nombre.asc'),
        _fetchCatalogo(
          'aseguramiento_formulas_c',
          'nombre',
          order: 'nombre.asc',
        ),
        _fetchCatalogo(
          'aseguramiento_categorias_toxicologicas',
          'nombre',
          order: 'nombre.asc',
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _semanas
          ..clear()
          ..addAll(
            resultados[0].map((item) => (item['numero'] as num).toInt()),
          );
        _productos
          ..clear()
          ..addAll(resultados[1].map((item) => item['nombre'].toString()));
        _proveedores
          ..clear()
          ..addAll(resultados[2].map((item) => item['nombre'].toString()));
        _presentaciones
          ..clear()
          ..addAll(resultados[3].map((item) => item['nombre'].toString()));
        _colores
          ..clear()
          ..addAll(resultados[4].map((item) => item['nombre'].toString()));
        _formulasC
          ..clear()
          ..addAll(resultados[5].map((item) => item['nombre'].toString()));
        _categoriasToxicologicas
          ..clear()
          ..addAll(resultados[6].map((item) => item['nombre'].toString()));
        if (!_colores.contains('OTRO')) _colores.add('OTRO');
        final colorGuardado = _colorController.text.trim().toUpperCase();
        if (colorGuardado.isNotEmpty && !_colores.contains(colorGuardado)) {
          _colorController.text = 'OTRO';
          _otroColorController.text = colorGuardado;
        } else if (colorGuardado == 'OTRO') {
          _colorController.text = 'OTRO';
          _otroColorController.clear();
        }
      });
    } catch (e) {
      if (!mounted) return;
      Get.snackbar(
        'Catálogos no disponibles',
        'Verifique que las tablas de Supabase estén creadas: $e',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 8),
      );
    }
  }

  // Función para seleccionar fecha de vencimiento
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime(2040),
      locale: const Locale('es', 'ES'),
    );
    if (picked != null) {
      setState(() {
        _vencimientoController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _guardarEnBaseDeDatos() async {
    if (!loginController.visitantePuedeInsertar) {
      Get.snackbar(
        'Solo lectura',
        'El perfil visitante no tiene permiso para insertar datos.',
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    Map<String, dynamic> body = {};

    try {
      // Asegura que el usuario y los administradores terminaron de cargar
      // antes de construir el registro y copiar las firmas seleccionadas.
      await _cargarAdministradores();
      await _cargarFirmas();

      // Helper local para convertir a mayúsculas y devolver null si vacío
      String? up(String? s) {
        if (s == null) return null;
        final t = s.trim();
        return t.isEmpty ? null : t.toUpperCase();
      }

      final idFirmaAutoriza = _identificacionAdminSeleccionado();
      final idFirmaAsegura =
          loginController.loggedInUser.value?['identificacion']
              ?.toString()
              .trim() ??
          widget.dataInicial?['identificacion_asegura']?.toString().trim();
      final firmaAsegura =
          (idFirmaAsegura == null
              ? null
              : _firmasPorIdentificacion[idFirmaAsegura]) ??
          widget.dataInicial?['firma_asegura_base64']?.toString();
      final firmaAutoriza =
          (idFirmaAutoriza == null
              ? null
              : _firmasPorIdentificacion[idFirmaAutoriza]) ??
          widget.dataInicial?['firma_autoriza_base64']?.toString();

      if ((firmaAsegura == null || firmaAsegura.isEmpty) && !widget.esLectura) {
        throw Exception(
          'No hay firma guardada para quien asegura. Guarda tu firma digital e inténtalo de nuevo.',
        );
      }
      if ((firmaAutoriza == null || firmaAutoriza.isEmpty) &&
          !widget.esLectura) {
        throw Exception(
          'No hay firma guardada para quien autoriza. Selecciona un administrador con firma registrada.',
        );
      }

      // Campos numéricos y fecha se mantienen igual; los textos se pasan por up(...)
      body = {
        'semana': int.tryParse(_semanaController.text),

        // Fecha del registro (se guarda en formato ISO yyyy-MM-dd)
        'fecha': DateFormat('yyyy-MM-dd').format(DateTime.now()),

        // Campos de texto convertidos a MAYÚSCULAS
        'nombre_producto': up(_productoController.text),
        'proveedor': up(_proveedorController.text),
        'formula_c': up(_formulaCController.text),
        'cat_toxic': up(_catToxicController.text),

        'presentacion': up(_presentacionController.text),
        'total_unidades': int.tryParse(_unidadesController.text) ?? 0,

        'lote': up(_loteController.text),
        'fecha_vencimiento':
            _vencimientoController.text.isEmpty
                ? null
                : _vencimientoController.text,

        // Estados ya vienen en mayúsculas (CUMPLE / NO CUMPLE)
        'estado_etiqueta': _estadoEtiqueta,
        'estado_tapa': _estadoTapa,
        'sellos': _sellos,
        'puntos_extraccion': _puntosextraccion,

        'cumplimiento': '$_porcentajeCumplimiento%',

        // Campos numéricos
        // cantidad como entero (si está vacío queda 0)
        'cantidad_cc_g': int.tryParse(_cantidadController.text) ?? 0,
        'color':
            _colorController.text == 'OTRO'
                ? (up(_otroColorController.text) ?? 'NO DEFINIDO')
                : (up(_colorController.text) ?? 'NO DEFINIDO'),

        // ph y densidad NO obligatorios: si están vacíos se envía null
        'ph':
            _phController.text.trim().isEmpty
                ? null
                : (int.tryParse(_phController.text) ??
                    (double.tryParse(_phController.text)?.round())),
        'densidad':
            _densidadController.text.trim().isEmpty
                ? null
                : (double.tryParse(_densidadController.text) ?? null),

        'observaciones': up(_obsController.text) ?? 'N/A',
        'autorizacion': up(_autorizaController.text),
        'nombre_autoriza': up(_autorizaController.text),
        'firma_asegura_base64': firmaAsegura,
        'firma_autoriza_base64': firmaAutoriza,
        'identificacion_asegura': idFirmaAsegura,
        'identificacion_autoriza':
            idFirmaAutoriza ??
            widget.dataInicial?['identificacion_autoriza']?.toString(),
        'nombre_quien_asegura': up(_aseguraController.text),
      };

      final url = Uri.parse(
        '${loginController.supabaseUrl}/rest/v1/aseguramiento_plaguicidas',
      );

      final response = await http
          .post(
            url,
            headers: {
              'apikey': loginController.apiKey,
              'Authorization': 'Bearer ${loginController.apiKey}',
              'Content-Type': 'application/json',
              'Prefer': 'return=minimal',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 201 || response.statusCode == 200) {
        Get.snackbar(
          'Éxito',
          'Registro guardado correctamente',
          backgroundColor: brandGreen,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );

        // Limpiar formulario
        _formKey.currentState?.reset();
        _semanaController.text = _semanaActual().toString();
        _productoController.clear();
        _proveedorController.clear();
        _formulaCController.clear();
        _catToxicController.clear();
        _presentacionController.clear();
        _unidadesController.clear();
        _loteController.clear();
        _vencimientoController.clear();
        _cantidadController.clear();
        _colorController.clear();
        _otroColorController.clear();
        _phController.clear();
        _densidadController.clear();
        _obsController.clear();
        _aseguraController.clear();
        _autorizaController.clear();
        setState(() {
          _aseguraController.text =
              loginController.loggedInUser.value?['nombres']?.toString() ?? '';
          if (_administradores.length == 1) {
            _autorizaController.text = _administradores.first;
          }
          _estadoEtiqueta = 'CUMPLE';
          _estadoTapa = 'CUMPLE';
          _sellos = 'CUMPLE';
          _puntosextraccion = 'CUMPLE';
        });
      } else {
        throw Exception('Error de Supabase: ${response.body}');
      }
    } on TimeoutException {
      await OfflineSyncService.enqueue('aseguramiento_plaguicidas', body);
      Get.snackbar(
        'Guardado sin internet',
        'Se sincronizará automáticamente al recuperar conexión',
      );
    } on http.ClientException {
      await OfflineSyncService.enqueue('aseguramiento_plaguicidas', body);
      Get.snackbar(
        'Guardado sin internet',
        'Se sincronizará automáticamente al recuperar conexión',
      );
    } on HandshakeException {
      await OfflineSyncService.enqueue('aseguramiento_plaguicidas', body);
      Get.snackbar(
        'Guardado en este dispositivo',
        'No se pudo validar el certificado de la conexión. El registro se subirá cuando la conexión sea segura.',
      );
    } catch (e) {
      final errorServidor = e.toString();
      final errorNormalizado = errorServidor.toLowerCase();
      final detalle =
          errorServidor.contains('PGRST204') ||
                  errorServidor.contains('42703') ||
                  errorNormalizado.contains('could not find the')
              ? 'A Supabase le faltan columnas del formulario. Ejecuta supabase/firmas_digitales.sql en el SQL Editor y vuelve a intentar.'
              : errorServidor;
      Get.snackbar(
        'Error',
        'No se pudo guardar el registro: $detalle',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 8),
        snackPosition: SnackPosition.BOTTOM,
      );
      print("DETALLE DEL ERROR: $e");
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      appBar: AppBar(
        toolbarHeight: 75,
        elevation: 0,
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,

        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF008DC5), Color(0xFF005F86)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
          ),
        ),

        title: Row(
          children: [
            // BOTÓN ATRÁS
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                onPressed: () => Get.back(),
              ),
            ),

            const SizedBox(width: 14),

            // TITULO
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Control de",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    "ASEGURAMIENTO",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderInfo(),
              const SizedBox(height: 20),

              _sectionTitle("DATOS DEL PRODUCTO"),
              Row(
                children: [
                  Expanded(
                    child: _buildDropdown<int>(
                      label: 'Semana',
                      icon: Icons.calendar_today,
                      values: _semanas,
                      selectedValue: int.tryParse(_semanaController.text),
                      labelForValue: (value) => value.toString(),
                      onChanged:
                          (value) => setState(
                            () =>
                                _semanaController.text =
                                    value?.toString() ?? '',
                          ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildDropdown<String>(
                      label: 'Nombre Producto',
                      icon: Icons.inventory,
                      values: _productos,
                      selectedValue:
                          _productoController.text.isEmpty
                              ? null
                              : _productoController.text,
                      labelForValue: (value) => value,
                      onChanged:
                          (value) => setState(
                            () => _productoController.text = value ?? '',
                          ),
                    ),
                  ),
                ],
              ),

              _buildDropdown<String>(
                label: 'Casa Comercial',
                icon: Icons.business,
                values: _proveedores,
                selectedValue:
                    _proveedorController.text.isEmpty
                        ? null
                        : _proveedorController.text,
                labelForValue: (value) => value,
                onChanged:
                    (value) =>
                        setState(() => _proveedorController.text = value ?? ''),
              ),

              Row(
                children: [
                  Expanded(
                    child: _buildDropdown<String>(
                      label: 'Presentación',
                      icon: Icons.layers,
                      values: _presentaciones,
                      selectedValue:
                          _presentacionController.text.isEmpty
                              ? null
                              : _presentacionController.text,
                      labelForValue: (value) => value,
                      onChanged:
                          (value) => setState(
                            () => _presentacionController.text = value ?? '',
                          ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildNumberInput(
                      _unidadesController,
                      'Cantidad',
                      Icons.numbers,
                      isDecimal: false, // Entero para unidades físicas
                    ),
                  ),
                ],
              ),

              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      _loteController,
                      '# Lote',
                      Icons.tag, // Texto para permitir códigos de lote
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildNumberInput(
                      _cantidadController,
                      'Cantidad (Unidad)',
                      Icons.scale,
                      isDecimal: false, // Entero para gramajes exactos
                    ),
                  ),
                ],
              ),

              Row(
                children: [
                  Expanded(
                    child: _buildDropdown<String>(
                      label: 'Formula C',
                      icon: Icons.science,
                      values: _formulasC,
                      selectedValue:
                          _formulaCController.text.isEmpty
                              ? null
                              : _formulaCController.text,
                      labelForValue: (value) => value,
                      onChanged:
                          (value) => setState(
                            () => _formulaCController.text = value ?? '',
                          ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildDropdown<String>(
                      label: 'Cat Toxic',
                      icon: Icons.warning_amber,
                      values: _categoriasToxicologicas,
                      selectedValue:
                          _catToxicController.text.isEmpty
                              ? null
                              : _catToxicController.text,
                      labelForValue: (value) => value,
                      onChanged:
                          (value) => setState(
                            () => _catToxicController.text = value ?? '',
                          ),
                    ),
                  ),
                ],
              ),

              _buildTextField(
                _vencimientoController,
                'Fecha de Vencimiento',
                Icons.event,
                onTap:
                    () => _selectDate(
                      context,
                    ), // Aquí le decimos que abra el calendario
                readOnly: true, // Aquí le decimos que no abra el teclado
              ),

              _sectionTitle("CARACTERÍSTICAS DE SEGURIDAD"),
              _buildOptionSelector(
                "Estado Etiqueta",
                _estadoEtiqueta,
                (val) => setState(() => _estadoEtiqueta = val),
              ),
              _buildOptionSelector(
                "Estado Tapa",
                _estadoTapa,
                (val) => setState(() => _estadoTapa = val),
              ),
              _buildOptionSelector(
                "Sellos",
                _sellos,
                (val) => setState(() => _sellos = val),
              ),
              _buildOptionSelector(
                "Puntos Extracción",
                _puntosextraccion,
                (val) => setState(() => _puntosextraccion = val),
              ),

              _sectionTitle("CUMPLIMIENTO"),
              _buildCumplimientoSelector(),

              _sectionTitle("ANÁLISIS FÍSICO-QUÍMICO"),
              _buildDropdown<String>(
                label: 'Color',
                icon: Icons.colorize,
                values: _colores,
                selectedValue:
                    _colorController.text.isEmpty
                        ? null
                        : _colorController.text,
                labelForValue: (value) => value,
                onChanged:
                    (value) => setState(() {
                      _colorController.text = value ?? '';
                      if (value != 'OTRO') _otroColorController.clear();
                    }),
              ),
              if (_colorController.text == 'OTRO')
                _buildTextField(
                  _otroColorController,
                  'Especifique el color',
                  Icons.edit,
                ),

              Row(
                children: [
                  Expanded(
                    child: _buildNumberInput(
                      _phController,
                      'pH',
                      Icons.water_drop,
                      isDecimal: true,
                      requiredField: false, // ahora opcional
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildNumberInput(
                      _densidadController,
                      'Densidad',
                      Icons.shutter_speed,
                      isDecimal: true,
                      requiredField: false, // ahora opcional
                    ),
                  ),
                ],
              ),

              _buildTextField(
                _obsController,
                'Observaciones',
                Icons.comment,
                isMultiline: true,
                requiredField: false,
              ),
              _buildTextField(
                _aseguraController,
                'Quién asegura',
                Icons.verified_user,
                readOnly: true,
              ),
              _vistaFirma(
                _firmasPorIdentificacion[loginController
                            .loggedInUser
                            .value?['identificacion']
                            ?.toString() ??
                        ''] ??
                    widget.dataInicial?['firma_asegura_base64']?.toString(),
                'Firma de quien asegura',
              ),
              if (_administradores.length > 1)
                _buildDropdown<String>(
                  label: 'Quién autoriza',
                  icon: Icons.admin_panel_settings,
                  values: _administradores,
                  selectedValue:
                      _administradores.contains(_autorizaController.text)
                          ? _autorizaController.text
                          : null,
                  labelForValue: (value) => value,
                  onChanged:
                      (value) => setState(
                        () => _autorizaController.text = value ?? '',
                      ),
                )
              else
                _buildTextField(
                  _autorizaController,
                  'Quién autoriza',
                  Icons.admin_panel_settings,
                  readOnly: _administradores.length == 1,
                ),
              _vistaFirma(
                _firmaAdministradorSeleccionado() ??
                    widget.dataInicial?['firma_autoriza_base64']?.toString(),
                'Firma de quien autoriza',
              ),

              const SizedBox(height: 30),
              if (!widget
                  .esLectura) // Solo muestra el botón si NO es modo lectura
                _isSaving
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton.icon(
                      onPressed: _guardarEnBaseDeDatos,
                      icon: const Icon(Icons.cloud_upload, color: Colors.white),
                      label: const Text(
                        "GUARDAR REGISTRO",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brandBlue,
                        minimumSize: const Size(double.infinity, 60),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGETS AUXILIARES ---

  Widget _buildDropdown<T>({
    required String label,
    required IconData icon,
    required List<T> values,
    required T? selectedValue,
    required String Function(T value) labelForValue,
    required ValueChanged<T?> onChanged,
  }) {
    final options = [...values];
    if (selectedValue != null && !options.contains(selectedValue)) {
      options.insert(0, selectedValue);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<T>(
        initialValue: selectedValue,
        isExpanded: true,
        menuMaxHeight: 280,
        dropdownColor: Colors.white,
        style: const TextStyle(
          color: Color(0xFF263238),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        icon: const Icon(Icons.arrow_drop_down_rounded),
        iconEnabledColor: brandBlue,
        onChanged: widget.esLectura ? null : onChanged,
        items:
            options
                .map(
                  (value) => DropdownMenuItem<T>(
                    value: value,
                    child: Text(
                      labelForValue(value),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.blueGrey[600]),
          prefixIcon: Icon(icon, color: brandBlue, size: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.blueGrey[200]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.blueGrey[200]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: brandBlue, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.redAccent),
          ),
          filled: true,
          fillColor: widget.esLectura ? Colors.blueGrey[50] : Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
        validator: (value) => value == null ? 'Requerido' : null,
      ),
    );
  }

  Widget _buildCumplimientoSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '$_porcentajeCumplimiento%',
            style: TextStyle(
              color:
                  _porcentajeCumplimiento == 100
                      ? brandGreen
                      : Colors.redAccent,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        AbsorbPointer(
          absorbing: true,
          child: Row(
            children: [
              Expanded(
                child: _optionButton(
                  "CUMPLE",
                  _cumplimiento == "CUMPLE",
                  brandGreen,
                  () {},
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _optionButton(
                  "NO CUMPLE",
                  _cumplimiento == "NO CUMPLE",
                  Colors.redAccent,
                  () {},
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildOptionSelector(
    String label,
    String currentValue,
    Function(String) onSelected,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        AbsorbPointer(
          absorbing: widget.esLectura, // Evita que cambien CUMPLE/NO CUMPLE
          child: Row(
            children: [
              Expanded(
                child: _optionButton(
                  "CUMPLE",
                  currentValue == "CUMPLE",
                  brandGreen,
                  () => onSelected("CUMPLE"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _optionButton(
                  "NO CUMPLE",
                  currentValue == "NO CUMPLE",
                  Colors.redAccent,
                  () => onSelected("NO CUMPLE"),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 15),
      ],
    );
  }

  Widget _optionButton(
    String text,
    bool isSelected,
    Color activeColor,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor : Colors.grey[300]!,
          ),
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey[600],
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isMultiline = false,
    VoidCallback? onTap,
    bool readOnly = false,
    bool requiredField = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AbsorbPointer(
        absorbing: widget.esLectura, // Bloquea interacción si es modo lectura
        child: TextFormField(
          controller: controller,
          maxLines: isMultiline ? 3 : 1,
          readOnly: widget.esLectura || readOnly,
          onTap: onTap,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, color: brandBlue, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            filled: true,
            fillColor: widget.esLectura ? Colors.grey[200] : Colors.grey[50],
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          validator:
              requiredField
                  ? (v) => v!.trim().isEmpty ? 'Requerido' : null
                  : null,
        ),
      ),
    );
  }

  // Versión actualizada: acepta requiredField para hacer el campo opcional
  Widget _buildNumberInput(
    TextEditingController controller,
    String label,
    IconData icon, {
    required bool isDecimal,
    bool requiredField = true, // nuevo parámetro: por defecto obligatorio
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AbsorbPointer(
        absorbing: widget.esLectura,
        child: TextFormField(
          controller: controller,
          readOnly: widget.esLectura,
          keyboardType: TextInputType.numberWithOptions(decimal: isDecimal),
          inputFormatters: [
            isDecimal
                ? FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
                : FilteringTextInputFormatter.digitsOnly,
          ],
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, color: brandBlue, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            filled: true,
            fillColor: widget.esLectura ? Colors.grey[200] : Colors.grey[50],
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          validator: (v) {
            if (!requiredField) return null; // no es obligatorio
            return (v == null || v.isEmpty) ? 'Requerido' : null;
          },
        ),
      ),
    );
  }

  Widget _buildHeaderInfo() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: brandBlue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: brandBlue.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: brandBlue,
            child: const Icon(Icons.person, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Responsable",
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
              Text(
                loginController.loggedInUser.value?['nombres'] ?? 'Usuario',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 15, bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          color: brandBlue,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
