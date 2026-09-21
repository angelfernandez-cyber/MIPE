// lib/formulario_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'login_controller.dart';
import 'offline_sync_service.dart';

class FormularioPage extends StatefulWidget {
  const FormularioPage({super.key});

  @override
  State<FormularioPage> createState() => _FormularioPageState();
}

class _FormularioPageState extends State<FormularioPage> {
  bool esModoLectura = false;
  final _formKey = GlobalKey<FormState>();
  final LoginController loginController = Get.find<LoginController>();
  bool _isSaving = false;

  final Color brandBlue = const Color(0xFF008DC5);
  final Color brandGreen = const Color(0xFF1DB954);
  final Color bgColor = const Color(0xFFF4F7F9);

  // Controladores
  final _bloqueController = TextEditingController();
  final _jefeMipeController = TextEditingController();
  final _bomberoController = TextEditingController();
  final _tempController = TextEditingController();
  final _humedadController = TextEditingController();
  final _tipoController = TextEditingController();
  final _volumenCamaController = TextEditingController();
  final _direccionController = TextEditingController();
  final _numCamasController = TextEditingController();
  final _equipoController = TextEditingController();
  final _ireController = TextEditingController();
  final _semanaController = TextEditingController();
  final _facilitadorMipeController = TextEditingController();
  final _facilitadorBloqueController = TextEditingController();

  // Listas dinámicas
  // ahora cada producto incluye: producto, dosis, cat_toxic, y blanco_id (ID del blanco seleccionado)
  List<Map<String, dynamic>> productos = [];
  List<TextEditingController> gruposFumigadores = [];

  // Blancos biológicos desde Supabase
  List<Map<String, dynamic>> _blancosDisponibles = [];

  // Equipos desde Supabase
  List<Map<String, dynamic>> _equiposDisponibles = [];

  // Catálogos del registro MIPE desde Supabase
  List<String> _personasDisponibles = [];
  List<String> _semanasDisponibles = [];
  List<String> _productosDisponibles = [];
  List<String> _tiposDisponibles = [];
  List<String> _direccionesDisponibles = [];
  List<String> _gruposDisponibles = [];

  // Días laborables disponibles para el registro MIPE.
  final List<String> _diasDisponibles = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
  ];
  String? _diaSeleccionado; // ahora solo un día

  String? _diaActual() {
    const nombres = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes'];
    final weekday = DateTime.now().weekday;
    return weekday >= DateTime.monday && weekday <= DateTime.friday
        ? nombres[weekday - 1]
        : null;
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
    final semana =
        1 + juevesActual.difference(primerJueves).inDays ~/ 7;

    return semana > 52 ? 52 : semana;
  }

  void _selectDia(String dia) {
    if (esModoLectura) return;
    setState(() {
      if (_diaSeleccionado == dia) {
        _diaSeleccionado = null;
      } else {
        _diaSeleccionado = dia;
      }
    });
  }

  void _agregarProducto() {
    if (esModoLectura) return;
    if (productos.length < 7) {
      setState(() {
        productos.add({
          'producto': TextEditingController(),
          'dosis': TextEditingController(),
          'cat_toxic': TextEditingController(),
          'blanco_id': null, // ID del blanco biológico seleccionado
        });
      });
    } else {
      Get.snackbar(
        'Límite alcanzado',
        'Máximo 7 productos permitidos',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  void _quitarProducto(int index) {
    if (esModoLectura) return;
    setState(() {
      productos[index]['producto']?.dispose();
      productos[index]['dosis']?.dispose();
      productos[index]['cat_toxic']?.dispose();
      productos.removeAt(index);
    });
  }

  void _agregarGrupoFumigador() {
    if (esModoLectura) return;
    if (gruposFumigadores.length < 7) {
      setState(() {
        gruposFumigadores.add(TextEditingController());
      });
    } else {
      Get.snackbar(
        'Límite alcanzado',
        'Máximo 7 grupos de fumigadores permitidos',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  void _quitarGrupoFumigador(int index) {
    if (esModoLectura) return;
    setState(() {
      gruposFumigadores[index].dispose();
      gruposFumigadores.removeAt(index);
    });
  }

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    final esRegistroExistente =
        args is Map && (args.containsKey('id') || args.containsKey('producto'));
    if (!esRegistroExistente) {
      _semanaController.text = _semanaActual().toString();
    }
    _inicializarFormulario();
  }

  Future<void> _inicializarFormulario() async {
    // Cargar blancos primero
    await _cargarBlancosDisponibles();

    // Cargar equipos
    await _cargarEquiposDisponibles();

    // Cargar catálogos del nuevo registro MIPE
    await _cargarCatalogosMipe();

    if (Get.arguments == null) {
      _diaSeleccionado = _diaActual();
    }

    // Luego cargar los datos del formulario si vienen en argumentos
    if (Get.arguments != null) {
      if (Get.arguments is Map) {
        final args = Map<String, dynamic>.from(Get.arguments);
        if (args.containsKey('id') || args.containsKey('producto')) {
          esModoLectura = true;
          _llenarCamposParaLectura(args);
        } else if (args.containsKey('bloque')) {
          _bloqueController.text = args['bloque'].toString();
          esModoLectura = false;
        }
      } else {
        _bloqueController.text = Get.arguments.toString();
        esModoLectura = false;
      }
    }

    if (!esModoLectura && _diaSeleccionado == null) {
      _diaSeleccionado = _diaActual();
    }

    if (!esModoLectura && _semanaController.text.trim().isEmpty) {
      _semanaController.text = _semanaActual().toString();
    }
  }

  Future<void> _cargarBlancosDisponibles() async {
    try {
      final url = Uri.parse(
        '${loginController.supabaseUrl}/rest/v1/blancos_biologicos?select=*',
      );
      final headers = {
        'apikey': loginController.apiKey,
        'Authorization': 'Bearer ${loginController.apiKey}',
        'Accept': 'application/json',
      };
      final data = await OfflineSyncService.fetchListWithCache(
        cacheKey: 'cache_catalogo_blancos_biologicos',
        url: url,
        headers: headers,
      );
      if (data.isNotEmpty) {
        setState(() {
          _blancosDisponibles = List<Map<String, dynamic>>.from(data);
        });
        print('✅ Blancos biológicos cargados desde Supabase:');
        for (var blanco in _blancosDisponibles) {
          print('   - ID: ${blanco['id']}, Nombre: ${blanco['nombre']}');
        }
      } else {
        print('⚠️ No hay blancos biológicos disponibles en caché ni en Supabase');
      }
    } catch (e) {
      print('❌ Error al cargar blancos biológicos: $e');
    }
  }

  Future<void> _cargarEquiposDisponibles() async {
    try {
      final url = Uri.parse(
        '${loginController.supabaseUrl}/rest/v1/equipos?select=*&order=nombre.asc',
      );
      final headers = {
        'apikey': loginController.apiKey,
        'Authorization': 'Bearer ${loginController.apiKey}',
        'Accept': 'application/json',
      };
      final data = await OfflineSyncService.fetchListWithCache(
        cacheKey: 'cache_catalogo_equipos',
        url: url,
        headers: headers,
      );
      if (data.isNotEmpty) {
        setState(() {
          _equiposDisponibles = List<Map<String, dynamic>>.from(data);
        });
        print('✅ Equipos cargados desde Supabase:');
        for (var equipo in _equiposDisponibles) {
          print('   - ID: ${equipo['id']}, Nombre: ${equipo['nombre']}');
        }
      } else {
        print('⚠️ No hay equipos disponibles en caché ni en Supabase');
      }
    } catch (e) {
      print('❌ Error al cargar equipos: $e');
    }
  }

  Future<void> _cargarCatalogosMipe() async {
    try {
      final headers = {
        'apikey': loginController.apiKey,
        'Authorization': 'Bearer ${loginController.apiKey}',
        'Accept': 'application/json',
      };

      Future<List<dynamic>> fetchCatalogo(
        String table, {
        bool filtrarActivo = true,
        String campo = 'nombre',
      }) async {
        final filtro = filtrarActivo ? '&activo=eq.true' : '';
        final url = Uri.parse(
          '${loginController.supabaseUrl}/rest/v1/$table?select=$campo$filtro&order=$campo.asc',
        );
        return OfflineSyncService.fetchListWithCache(
          cacheKey: 'cache_catalogo_$table',
          url: url,
          headers: headers,
        );
      }

      final semanas = await OfflineSyncService.fetchListWithCache(
        cacheKey: 'cache_catalogo_aseguramiento_semanas',
        url: Uri.parse(
          '${loginController.supabaseUrl}/rest/v1/aseguramiento_semanas?select=numero&activo=eq.true&order=numero.asc',
        ),
        headers: headers,
      );

      final resultados = await Future.wait([
        fetchCatalogo('persona', filtrarActivo: false, campo: 'nombres'),
        fetchCatalogo('aseguramiento_productos'),
        fetchCatalogo('mipe_tipos'),
        fetchCatalogo('mipe_direcciones'),
        fetchCatalogo('mipe_grupos'),
      ]);

      if (!mounted) return;
      setState(() {
        _personasDisponibles = _nombresCatalogo(
          resultados[0],
          campo: 'nombres',
        );
        _semanasDisponibles =
            semanas
                .map((item) => item['numero'].toString())
                .toList();
        _productosDisponibles = _nombresCatalogo(resultados[1]);
        _tiposDisponibles = _nombresCatalogo(resultados[2]);
        _direccionesDisponibles = _nombresCatalogo(resultados[3]);
        _gruposDisponibles = _nombresCatalogo(resultados[4]);
      });
    } catch (e) {
      if (!mounted) return;
      Get.snackbar(
        'Catálogos MIPE no disponibles',
        'Verifique las tablas de catálogos en Supabase: $e',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 8),
      );
    }
  }

  List<String> _nombresCatalogo(
    List<dynamic> items, {
    String campo = 'nombre',
  }) {
    return items
        .map((item) => item[campo]?.toString().trim() ?? '')
        .where((nombre) => nombre.isNotEmpty)
        .toList();
  }

  Widget _buildCatalogoDropdown(
    TextEditingController controller,
    String label,
    IconData icon,
    List<String> values,
  ) {
    if (esModoLectura) {
      return _buildInput(controller, label, icon, TextInputType.text);
    }

    final currentValue = controller.text.trim();
    final options = [...values];
    if (currentValue.isNotEmpty && !options.contains(currentValue)) {
      options.insert(0, currentValue);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: currentValue.isEmpty ? null : currentValue,
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
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.blueGrey[600]),
          filled: true,
          fillColor: Colors.white,
          prefixIcon: Icon(icon, size: 20, color: brandBlue),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
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
        ),
        hint: Text(
          values.isEmpty ? 'Cargando opciones...' : 'Selecciona una opción',
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
        items:
            options
                .map(
                  (value) => DropdownMenuItem<String>(
                    value: value,
                    child: Text(value, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
        onChanged: (value) => setState(() => controller.text = value ?? ''),
        validator:
            (value) =>
                (value == null || value.isEmpty) ? 'Campo obligatorio' : null,
      ),
    );
  }

  /// Llena los campos cuando se abre en modo lectura (detalle)
  void _llenarCamposParaLectura(Map<String, dynamic> data) {
    _bloqueController.text = data['bloque']?.toString() ?? "";
    _jefeMipeController.text = data['jefe_mipe'] ?? "";
    _bomberoController.text = data['bombero'] ?? "";
    _tempController.text = data['temperatura']?.toString() ?? "";
    _humedadController.text = data['humedad_relativa']?.toString() ?? "";
    _tipoController.text = data['tipo_aplicacion'] ?? "";
    _volumenCamaController.text = data['volumen_cama']?.toString() ?? "";
    _direccionController.text = data['direccion'] ?? "";
    _numCamasController.text = data['num_camas']?.toString() ?? "";
    _equipoController.text = data['equipo'] ?? "";
    _ireController.text = data['ire_horas']?.toString() ?? "";
    _semanaController.text = data['semana']?.toString() ?? "";
    _facilitadorMipeController.text = data['facilitador_mipe'] ?? "";
    _facilitadorBloqueController.text = data['facilitador_bloque'] ?? "";

    // Cargar día si viene (acepta string o lista)
    _diaSeleccionado = null;
    if (data['dias'] != null) {
      try {
        if (data['dias'] is String) {
          final raw = data['dias'] as String;
          final parts = raw
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty);
          for (var p in parts) {
            if (_diasDisponibles.contains(p)) {
              _diaSeleccionado = p;
              break;
            }
          }
        } else if (data['dias'] is List) {
          for (var p in data['dias']) {
            final s = p.toString();
            if (_diasDisponibles.contains(s)) {
              _diaSeleccionado = s;
              break;
            }
          }
        }
      } catch (_) {}
    }

    // Cargar grupos
    gruposFumigadores.clear();
    if (data['grupo_fumigadores'] != null) {
      try {
        if (data['grupo_fumigadores'] is String) {
          final raw = data['grupo_fumigadores'] as String;
          if (raw.trim().startsWith('[')) {
            final decoded = jsonDecode(raw);
            if (decoded is List) {
              for (var g in decoded) {
                gruposFumigadores.add(
                  TextEditingController(text: g.toString()),
                );
              }
            }
          } else {
            final parts = raw
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty);
            for (var p in parts) {
              gruposFumigadores.add(TextEditingController(text: p));
            }
          }
        } else if (data['grupo_fumigadores'] is List) {
          for (var g in data['grupo_fumigadores']) {
            gruposFumigadores.add(TextEditingController(text: g.toString()));
          }
        }
      } catch (_) {}
    }

    // Cargar productos con dosis, cat_toxic y blanco_biologico
    productos.clear();
    if (data['producto'] != null) {
      try {
        // Parsear productos (siempre como string concatenado)
        final productosRaw = data['producto'] as String;
        final productosList =
            productosRaw
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();

        // Parsear dosis (puede ser null o string concatenado)
        final dosisList =
            data['dosis'] != null
                ? (data['dosis'] as String)
                    .split(',')
                    .map((s) => s.trim())
                    .toList()
                : [];

        // Parsear cat_toxic (puede ser null o string concatenado)
        final catList =
            data['cat_toxic'] != null
                ? (data['cat_toxic'] as String)
                    .split(',')
                    .map((s) => s.trim())
                    .toList()
                : [];

        // Parsear blanco_biologico (puede ser null o string concatenado)
        final blancosList =
            data['blanco_biologico'] != null
                ? (data['blanco_biologico'] as String)
                    .split(',')
                    .map((s) => s.trim())
                    .toList()
                : [];

        print('📦 Cargando productos:');
        print('   Productos: $productosList');
        print('   Dosis: $dosisList');
        print('   Cat. Toxico: $catList');
        print('   Blancos: $blancosList');
        print('   Blancos disponibles en BD: $_blancosDisponibles');

        // Crear productos con sus datos asociados
        for (int i = 0; i < productosList.length; i++) {
          final dosis = i < dosisList.length ? dosisList[i] : '';
          final catToxic = i < catList.length ? catList[i] : '';
          final blancoNombre = i < blancosList.length ? blancosList[i] : '';

          // Buscar el ID del blanco por su nombre (case-insensitive y con trim)
          int? blancoId;
          if (blancoNombre.isNotEmpty) {
            final blancoNombreLower = blancoNombre.toLowerCase().trim();
            print(
              '   Buscando blanco "$blancoNombre" (lower: "$blancoNombreLower")',
            );

            final blanco = _blancosDisponibles.firstWhere(
              (b) {
                final bdNameLower =
                    (b['nombre']?.toString() ?? '').toLowerCase().trim();
                final match = bdNameLower == blancoNombreLower;
                if (match) {
                  print('     ✓ Encontrado: ${b['nombre']} (ID: ${b['id']})');
                }
                return match;
              },
              orElse: () {
                print('     ✗ NO ENCONTRADO en BD');
                return {};
              },
            );
            blancoId = blanco['id'] as int?;
          }

          productos.add({
            'producto': TextEditingController(text: productosList[i]),
            'dosis': TextEditingController(text: dosis),
            'cat_toxic': TextEditingController(text: catToxic),
            'blanco_id': blancoId,
          });
        }
      } catch (e) {
        print('❌ Error cargando productos: $e');
      }
    }

    setState(() {});
  }

  void _limpiarCampos() {
    FocusManager.instance.primaryFocus?.unfocus();
    _formKey.currentState?.reset();
    _bloqueController.clear();
    _jefeMipeController.clear();
    _bomberoController.clear();
    _tempController.clear();
    _humedadController.clear();
    _tipoController.clear();
    _volumenCamaController.clear();
    _direccionController.clear();
    _numCamasController.clear();
    _equipoController.clear();
    _ireController.clear();
    _semanaController.text = _semanaActual().toString();
    _facilitadorMipeController.clear();
    _facilitadorBloqueController.clear();

    for (var grupo in gruposFumigadores) {
      grupo.dispose();
    }
    gruposFumigadores.clear();

    for (var prod in productos) {
      prod['producto']?.dispose();
      prod['dosis']?.dispose();
      prod['cat_toxic']?.dispose();
    }
    productos.clear();

    _diaSeleccionado = _diaActual();

    setState(() {});
  }

  Future<void> _guardarEnSupabase() async {
    if (!_formKey.currentState!.validate()) return;

    // Validación adicional: al menos un nombre de producto no vacío
    final nombresNoVacios =
        productos
            .map((p) => p['producto']?.text.trim() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
    if (nombresNoVacios.isEmpty) {
      Get.snackbar(
        'Error',
        'Debe agregar al menos un nombre de producto',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    setState(() => _isSaving = true);
    Map<String, dynamic> payload = {};

    try {
      // --- Mantener comportamiento anterior para producto/dosis/cat ---
      final productosNombres =
          productos
              .map((p) => p['producto']?.text.trim() ?? '')
              .where((s) => s.isNotEmpty)
              .toList();
      final productosDosis =
          productos
              .map((p) => p['dosis']?.text.trim() ?? '')
              .where((s) => s.isNotEmpty)
              .toList();
      final productosCat =
          productos
              .map((p) => p['cat_toxic']?.text.trim() ?? '')
              .where((s) => s.isNotEmpty)
              .toList();

      final productoConcatenado = productosNombres.join(', ');
      final dosisConcatenada = productosDosis.join(', ');
      final catConcatenada = productosCat.join(', ');

      // --- Nuevo: concatenar blancos por producto ---
      final productosBlancos =
          productos
              .map((p) {
                final blancoId = p['blanco_id'] as int?;
                if (blancoId == null) return '';
                final blanco = _blancosDisponibles.firstWhere(
                  (b) => b['id'] == blancoId,
                  orElse: () => {},
                );
                return blanco['nombre']?.toString() ?? '';
              })
              .where((s) => s.isNotEmpty)
              .toList();
      final blancosConcatenados = productosBlancos.join(', ');

      final gruposConcatenados = gruposFumigadores
          .map((g) => g.text.trim())
          .where((s) => s.isNotEmpty)
          .join(', ');

      final diasConcatenados = _diaSeleccionado ?? '';

      String? productoToSend =
          productoConcatenado.isNotEmpty ? productoConcatenado : null;
      String? dosisToSend =
          dosisConcatenada.isNotEmpty ? dosisConcatenada : null;
      String? catToSend = catConcatenada.isNotEmpty ? catConcatenada : null;
      String? gruposToSend =
          gruposConcatenados.isNotEmpty ? gruposConcatenados : null;
      String? diasToSend =
          diasConcatenados.isNotEmpty ? diasConcatenados : null;
      String? blancosToSend =
          blancosConcatenados.isNotEmpty ? blancosConcatenados : null;

      final int? semanaParsed = int.tryParse(_semanaController.text.trim());

      payload = {
        'bloque':
            int.tryParse(_bloqueController.text.trim()) ??
            _bloqueController.text.trim(),
        'jefe_mipe':
            _jefeMipeController.text.trim().isNotEmpty
                ? _jefeMipeController.text.trim()
                : null,
        'bombero':
            _bomberoController.text.trim().isNotEmpty
                ? _bomberoController.text.trim()
                : null,
        'temperatura':
            _tempController.text.trim().isNotEmpty
                ? _tempController.text.trim()
                : null,
        'humedad_relativa':
            _humedadController.text.trim().isNotEmpty
                ? _humedadController.text.trim()
                : null,
        'tipo_aplicacion':
            _tipoController.text.trim().isNotEmpty
                ? _tipoController.text.trim()
                : null,
        'producto': productoToSend,
        'dosis': dosisToSend,
        'cat_toxic': catToSend,
        'grupo_fumigadores': gruposToSend,
        'dias': diasToSend,
        'volumen_cama':
            _volumenCamaController.text.trim().isNotEmpty
                ? _volumenCamaController.text.trim()
                : null,
        'direccion':
            _direccionController.text.trim().isNotEmpty
                ? _direccionController.text.trim()
                : null,
        'num_camas':
            _numCamasController.text.trim().isNotEmpty
                ? _numCamasController.text.trim()
                : null,
        'equipo':
            _equipoController.text.trim().isNotEmpty
                ? _equipoController.text.trim()
                : null,
        'ire_horas':
            _ireController.text.trim().isNotEmpty
                ? _ireController.text.trim()
                : null,
        'semana': semanaParsed,
        'facilitador_mipe':
            _facilitadorMipeController.text.trim().isNotEmpty
                ? _facilitadorMipeController.text.trim()
                : null,
        'facilitador_bloque':
            _facilitadorBloqueController.text.trim().isNotEmpty
                ? _facilitadorBloqueController.text.trim()
                : null,
        'usuario_registro':
            loginController.loggedInUser.value?['nombres'] ?? 'Operario',
        // **Solo añadimos blancos aquí** (sin tocar el resto)
        'blanco_biologico': blancosToSend,
      };

      // Eliminar claves con valor null
      payload.removeWhere((key, value) => value == null);

      // Debug: imprime payload y headers
      print('--- PAYLOAD PREVIO A ENVÍO ---');
      print(jsonEncode(payload));

      final headers = {
        'apikey': loginController.apiKey,
        'Authorization': 'Bearer ${loginController.apiKey}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Prefer': 'return=representation',
      };

      print('--- HEADERS ---');
      print(headers);

      final url = Uri.parse(
        '${loginController.supabaseUrl}/rest/v1/aspersiones',
      );
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 8));

      print('SUPABASE URL: ${loginController.supabaseUrl}');
      print('STATUS: ${response.statusCode}');
      print('BODY: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        _limpiarCampos();
        Get.snackbar(
          'Éxito',
          'Registro guardado correctamente',
          backgroundColor: brandGreen,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );
      } else {
        print('Error al guardar: ${response.statusCode} - ${response.body}');
        Get.snackbar('Error', 'No se pudo guardar: ${response.statusCode}');
      }
    } on TimeoutException {
      await OfflineSyncService.enqueue('aspersiones', payload);
      _limpiarCampos();
      Get.snackbar('Guardado sin internet', 'Se sincronizará automáticamente al recuperar conexión');
    } on http.ClientException {
      await OfflineSyncService.enqueue('aspersiones', payload);
      _limpiarCampos();
      Get.snackbar('Guardado sin internet', 'Se sincronizará automáticamente al recuperar conexión');
    } catch (e, st) {
      print('Excepción guardando: $e\n$st');
      Get.snackbar('Error Crítico', 'Verifica tu conexión');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          esModoLectura ? 'DETALLE DE ASPERSIÓN' : 'NUEVO REGISTRO MIPE',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
        backgroundColor: esModoLectura ? Colors.blueGrey[800] : brandBlue,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 15.0,
                vertical: 10,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildSectionTitle("DATOS DE UBICACIÓN Y RESPONSABLE"),
                    _buildCard([
                      Row(
                        children: [
                          Expanded(
                            child: _buildInput(
                              _bloqueController,
                              'Bloque',
                              Icons.grid_view,
                              TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildCatalogoDropdown(
                              _bomberoController,
                              'Bombero',
                              Icons.person,
                              _personasDisponibles,
                            ),
                          ),
                        ],
                      ),
                      _buildCatalogoDropdown(
                        _jefeMipeController,
                        'Jefe MIPE',
                        Icons.assignment_ind,
                        _personasDisponibles,
                      ),
                      _buildCatalogoDropdown(
                        _semanaController,
                        'Semana',
                        Icons.calendar_month,
                        _semanasDisponibles,
                      ),
                    ]),
                    _buildSectionTitle("DÍA (selección única)"),
                    _buildCard([_buildDiaSelector()]),
                    _buildSectionTitle("CONDICIONES AMBIENTALES"),
                    _buildCard([
                      Row(
                        children: [
                          Expanded(
                            child: _buildInput(
                              _tempController,
                              'Temp (°C)',
                              Icons.thermostat,
                              TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildInput(
                              _humedadController,
                              '% HR',
                              Icons.water_drop,
                              TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                    ]),
                    _buildSectionTitle("DETALLES DE APLICACIÓN"),
                    _buildCard([
                      Row(
                        children: [
                          Expanded(
                            child: _buildCatalogoDropdown(
                              _tipoController,
                              'Tipo',
                              Icons.category,
                              _tiposDisponibles,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildCatalogoDropdown(
                              _direccionController,
                              'Dirección',
                              Icons.navigation,
                              _direccionesDisponibles,
                            ),
                          ),
                        ],
                      ),
                      ...List.generate(
                        productos.length,
                        (index) => _buildProductCard(index),
                      ),
                      if (!esModoLectura)
                        ElevatedButton.icon(
                          onPressed: _agregarProducto,
                          icon: const Icon(
                            Icons.add_circle_outline,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'AGREGAR PRODUCTO',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: brandBlue,
                            minimumSize: const Size(double.infinity, 45),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildInput(
                              _volumenCamaController,
                              'Vol. Cama',
                              Icons.layers,
                              TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildInput(
                              _numCamasController,
                              'No. Camas',
                              Icons.format_list_numbered,
                              TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      ...List.generate(gruposFumigadores.length, (index) {
                        return Row(
                          children: [
                            Expanded(
                              child: _buildCatalogoDropdown(
                                gruposFumigadores[index],
                                'Grupo ${index + 1}',
                                Icons.groups,
                                _gruposDisponibles,
                              ),
                            ),
                            if (!esModoLectura)
                              IconButton(
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  color: Colors.red,
                                ),
                                onPressed: () => _quitarGrupoFumigador(index),
                              ),
                          ],
                        );
                      }),
                      if (!esModoLectura)
                        ElevatedButton.icon(
                          onPressed: _agregarGrupoFumigador,
                          icon: const Icon(
                            Icons.add_circle_outline,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'GRUPO FUMIGADORES',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: brandBlue,
                            minimumSize: const Size(double.infinity, 45),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                    ]),
                    _buildSectionTitle("OPERACIÓN Y SEGURIDAD"),
                    _buildCard([
                      _buildEquipoDropdown(),
                      const SizedBox(height: 10),
                      _buildInput(
                        _ireController,
                        'I.R.E (Horas de Reingreso)',
                        Icons.timer,
                        TextInputType.number,
                      ),
                    ]),
                    _buildSectionTitle("FACILITADORES"),
                    _buildCard([
                      _buildCatalogoDropdown(
                        _facilitadorMipeController,
                        'Facilitador MIPE',
                        Icons.person_4,
                        _personasDisponibles,
                      ),
                      _buildCatalogoDropdown(
                        _facilitadorBloqueController,
                        'Facilitador Bloque',
                        Icons.person_3,
                        _personasDisponibles,
                      ),
                    ]),
                    const SizedBox(height: 30),
                    _buildButtons(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiaSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Selecciona un día de aplicación',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        AbsorbPointer(
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children:
                _diasDisponibles.map((dia) {
                  final selected = _diaSeleccionado == dia;
                  return ChoiceChip(
                    label: Text(dia),
                    selected: selected,
                    onSelected: (_) => _selectDia(dia),
                    selectedColor: brandBlue,
                    backgroundColor: Colors.grey[200],
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : Colors.black,
                    ),
                  );
                }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        if (_diaSeleccionado != null)
          Text(
            'Día seleccionado: $_diaSeleccionado',
            style: const TextStyle(color: Colors.black54),
          )
        else
          const Text(
            'El día se selecciona automáticamente según la fecha actual.',
            style: TextStyle(color: Colors.black54),
          ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 25),
      decoration: BoxDecoration(
        color: esModoLectura ? Colors.blueGrey[800] : brandBlue,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(35)),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 35,
            backgroundColor: Colors.white.withOpacity(0.2),
            child: Icon(
              esModoLectura
                  ? Icons.description_outlined
                  : Icons.post_add_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            esModoLectura ? "Consulta de Registro" : "Completar Formulario",
            style: const TextStyle(
              color: Colors.white70,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Container(
      padding: const EdgeInsets.only(left: 5, top: 20, bottom: 8),
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          color: brandBlue,
          fontWeight: FontWeight.bold,
          fontSize: 13,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildProductCard(int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: brandBlue.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Producto ${index + 1}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: brandBlue,
                  fontSize: 14,
                ),
              ),
              if (!esModoLectura)
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    color: Colors.red[600],
                    size: 20,
                  ),
                  onPressed: () => _quitarProducto(index),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
          const SizedBox(height: 10),
          _buildCatalogoDropdown(
            productos[index]['producto']!,
            'Nombre del Producto',
            Icons.science,
            _productosDisponibles,
          ),
          Row(
            children: [
              Expanded(
                child: _buildProductInput(
                  productos[index]['dosis']!,
                  'Dosis',
                  Icons.straighten,
                  isDecimal: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildProductInput(
                  productos[index]['cat_toxic']!,
                  'Cat. Toxico',
                  Icons.warning_amber_rounded,
                  isDecimal: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Nuevo campo: Blanco biológico por producto (Dropdown)
          _buildBlancoBiologicoDropdown(index),
        ],
      ),
    );
  }

  Widget _buildBlancoBiologicoDropdown(int productIndex) {
    final blancoId = productos[productIndex]['blanco_id'] as int?;
    String blancoNombre = 'No seleccionado';

    if (blancoId != null && _blancosDisponibles.isNotEmpty) {
      final blanco = _blancosDisponibles.firstWhere(
        (b) => b['id'] == blancoId,
        orElse: () => {'nombre': 'No encontrado'},
      );
      blancoNombre = blanco['nombre']?.toString() ?? 'No seleccionado';
    }

    // En modo lectura, mostrar como texto
    if (esModoLectura) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: TextEditingController(text: blancoNombre),
          readOnly: true,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey[800],
          ),
          decoration: InputDecoration(
            labelText: 'Blanco Biológico',
            labelStyle: const TextStyle(fontSize: 12),
            filled: true,
            fillColor: Colors.blueGrey[50],
            prefixIcon: Icon(
              Icons.bug_report,
              size: 18,
              color: Colors.blueGrey,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey[200]!),
            ),
          ),
        ),
      );
    }

    // En modo edición, mostrar dropdown
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<int>(
            value: productos[productIndex]['blanco_id'] as int?,
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
            decoration: InputDecoration(
              labelText: 'Blanco Biológico',
              labelStyle: TextStyle(color: Colors.blueGrey[600]),
              prefixIcon: const Icon(Icons.bug_report, size: 20),
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
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
            hint: const Text('Seleccionar'),
            items:
                _blancosDisponibles.map<DropdownMenuItem<int>>((blanco) {
                  return DropdownMenuItem<int>(
                    value: blanco['id'] as int,
                    child: Text(blanco['nombre'] ?? 'Sin nombre'),
                  );
                }).toList(),
            onChanged: (int? newValue) {
              setState(() {
                productos[productIndex]['blanco_id'] = newValue;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProductInput(
    TextEditingController controller,
    String label,
    IconData icon, {
    required bool isDecimal,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: isDecimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            isDecimal ? RegExp(r'\d*\.?\d*') : RegExp(r'\d+'),
          ),
        ],
        readOnly: esModoLectura,
        style: TextStyle(
          fontWeight: esModoLectura ? FontWeight.bold : FontWeight.normal,
          color: esModoLectura ? Colors.blueGrey[800] : Colors.black,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 12),
          filled: esModoLectura,
          fillColor: esModoLectura ? Colors.blueGrey[50] : Colors.white,
          prefixIcon: Icon(
            icon,
            size: 18,
            color: esModoLectura ? Colors.blueGrey : brandBlue,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey[200]!),
          ),
        ),
        validator:
            (val) => (val!.isEmpty && !esModoLectura) ? 'Requerido' : null,
      ),
    );
  }

  Widget _buildInput(
    TextEditingController controller,
    String label,
    IconData icon,
    TextInputType type,
  ) {
    bool isReadOnly = esModoLectura || (label == 'Bloque');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: type,
        readOnly: isReadOnly,
        style: TextStyle(
          fontWeight: isReadOnly ? FontWeight.bold : FontWeight.normal,
          color: isReadOnly ? Colors.blueGrey[800] : Colors.black,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 13),
          filled: isReadOnly,
          fillColor: isReadOnly ? Colors.blueGrey[50] : Colors.white,
          prefixIcon: Icon(
            icon,
            size: 20,
            color: isReadOnly ? Colors.blueGrey : brandBlue,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 15,
            vertical: 15,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[200]!),
          ),
        ),
        validator:
            (val) =>
                (val!.isEmpty && !esModoLectura) ? 'Campo obligatorio' : null,
      ),
    );
  }

  Widget _buildEquipoDropdown() {
    // En modo lectura mostramos el valor guardado como campo de solo lectura.
    if (esModoLectura) {
      return _buildInput(
        _equipoController,
        'EQUIPO',
        Icons.handyman,
        TextInputType.text,
      );
    }

    // El equipo se guarda como texto (nombre) en la tabla 'aspersiones',
    // por eso usamos el nombre del equipo como valor del dropdown y lo
    // reflejamos en _equipoController para no cambiar la lógica de guardado.
    final String valorActual = _equipoController.text.trim();
    final bool existeEnLista = _equiposDisponibles.any(
      (e) => (e['nombre']?.toString() ?? '') == valorActual,
    );
    final String? valorDropdown =
        (existeEnLista && valorActual.isNotEmpty) ? valorActual : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: valorDropdown,
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
        decoration: InputDecoration(
          labelText: 'EQUIPO',
          labelStyle: TextStyle(color: Colors.blueGrey[600]),
          filled: true,
          fillColor: Colors.white,
          prefixIcon: Icon(Icons.handyman, size: 20, color: brandBlue),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
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
        ),
        hint: Text(
          _equiposDisponibles.isEmpty
              ? 'Cargando equipos...'
              : 'Selecciona un equipo',
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
        items:
            _equiposDisponibles.map<DropdownMenuItem<String>>((equipo) {
              final nombre = equipo['nombre']?.toString() ?? 'Sin nombre';
              return DropdownMenuItem<String>(
                value: nombre,
                child: Text(nombre),
              );
            }).toList(),
        onChanged: (String? newValue) {
          setState(() {
            _equipoController.text = newValue ?? '';
          });
        },
        validator:
            (val) => (val == null || val.isEmpty) ? 'Campo obligatorio' : null,
      ),
    );
  }

  Widget _buildButtons() {
    if (!esModoLectura) {
      return _isSaving
          ? const CircularProgressIndicator()
          : ElevatedButton.icon(
            onPressed: _guardarEnSupabase,
            icon: const Icon(Icons.cloud_upload_rounded, color: Colors.white),
            label: const Text(
              'FINALIZAR REGISTRO',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: brandBlue,
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              elevation: 5,
            ),
          );
    }

    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: () {
            Get.back();
          },
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          label: const Text(
            'VOLVER',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}
