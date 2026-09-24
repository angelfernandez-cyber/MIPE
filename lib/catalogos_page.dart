import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import 'login_controller.dart';

class _Catalogo {
  const _Catalogo(
    this.clave,
    this.nombre,
    this.tabla,
    this.icono, {
    this.esSemana = false,
  });
  final String clave;
  final String nombre;
  final String tabla;
  final IconData icono;
  final bool esSemana;
}

class CatalogosPage extends StatefulWidget {
  const CatalogosPage({super.key});

  @override
  State<CatalogosPage> createState() => _CatalogosPageState();
}

class _CatalogosPageState extends State<CatalogosPage> {
  final LoginController _login = Get.find<LoginController>();
  final List<_Catalogo> _catalogos = const [
    _Catalogo(
      'semanas',
      'Semanas',
      'aseguramiento_semanas',
      Icons.calendar_month_rounded,
      esSemana: true,
    ),
    _Catalogo(
      'productos',
      'Productos',
      'aseguramiento_productos',
      Icons.science_rounded,
    ),
    _Catalogo(
      'proveedores',
      'Proveedores',
      'aseguramiento_proveedores',
      Icons.local_shipping_rounded,
    ),
    _Catalogo(
      'presentaciones',
      'Presentaciones',
      'aseguramiento_presentaciones',
      Icons.inventory_2_rounded,
    ),
    _Catalogo(
      'colores',
      'Colores',
      'aseguramiento_colores',
      Icons.palette_rounded,
    ),
    _Catalogo(
      'formulas_c',
      'Fórmula C',
      'aseguramiento_formulas_c',
      Icons.fact_check_rounded,
    ),
    _Catalogo(
      'categorias_toxicologicas',
      'Categorías toxicológicas',
      'aseguramiento_categorias_toxicologicas',
      Icons.warning_amber_rounded,
    ),
    _Catalogo(
      'tipos_mipe',
      'Tipos de aplicación',
      'mipe_tipos',
      Icons.water_drop_rounded,
    ),
    _Catalogo(
      'direcciones_mipe',
      'Direcciones',
      'mipe_direcciones',
      Icons.explore_rounded,
    ),
    _Catalogo('grupos_mipe', 'Grupos', 'mipe_grupos', Icons.groups_rounded),
  ];

  late _Catalogo _seleccionado = _catalogos.first;
  List<Map<String, dynamic>> _opciones = [];
  bool _cargando = true;
  bool _guardando = false;
  String? _password;

  @override
  void initState() {
    super.initState();
    if (_login.loggedInUser.value?['admin']?.toString().trim() != 'S') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.back();
        Get.snackbar(
          'Acceso restringido',
          'Solo el administrador puede gestionar las listas.',
        );
      });
      return;
    }
    _password = _login.passwordEnMemoria;
    _cargar();
  }

  Future<String?> _obtenerPassword() async {
    final actual = _password ?? _login.passwordEnMemoria;
    if (actual != null && actual.isNotEmpty) return actual;
    final resultado = await Get.to<String>(
      () => const _CatalogoTextoPage(
        titulo: 'Confirmar administrador',
        etiqueta: 'Contraseña',
        textoBoton: 'Continuar',
        ocultarTexto: true,
      ),
    );
    if (resultado == null || resultado.isEmpty) return null;
    _password = resultado;
    return resultado;
  }

  Future<dynamic> _rpc(
    String operacion, {
    String? valor,
    int? id,
    bool? activo,
  }) async {
    final password = await _obtenerPassword();
    if (password == null) {
      throw Exception('Se requiere la contraseña del administrador.');
    }
    final usuario = _login.loggedInUser.value?['identificacion']?.toString();
    final response = await http
        .post(
          Uri.parse(
            '${_login.supabaseUrl}/rest/v1/rpc/gestionar_opciones_listas_admin',
          ),
          headers: {
            'apikey': _login.apiKey,
            'Authorization': 'Bearer ${_login.apiKey}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'p_identificacion': usuario,
            'p_password': password,
            'p_catalogo': _seleccionado.clave,
            'p_operacion': operacion,
            'p_valor': valor,
            'p_id': id,
            'p_activo': activo,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detalle =
          response.body.isEmpty
              ? 'No se pudo completar la operación.'
              : response.body;
      throw Exception(detalle);
    }
    return response.body.isEmpty ? null : jsonDecode(response.body);
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final result = await _rpc('listar');
      if (!mounted) return;
      final filas = result is List ? result : <dynamic>[];
      final opciones =
          filas.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      opciones.sort((a, b) {
        final estado = (b['activo'] == true ? 1 : 0).compareTo(
          a['activo'] == true ? 1 : 0,
        );
        if (estado != 0) return estado;
        if (_seleccionado.esSemana) {
          return (int.tryParse(a['valor'].toString()) ?? 0).compareTo(
            int.tryParse(b['valor'].toString()) ?? 0,
          );
        }
        return a['valor'].toString().toLowerCase().compareTo(
          b['valor'].toString().toLowerCase(),
        );
      });
      setState(() => _opciones = opciones);
    } catch (e) {
      if (mounted) _mensajeError(e);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _agregar() async {
    final esSemana = _seleccionado.esSemana;
    final valor = await Get.to<String>(
      () => _CatalogoTextoPage(
        titulo: 'Agregar ${_seleccionado.nombre.toLowerCase()}',
        etiqueta:
            esSemana ? 'Número de semana (1 a 52)' : 'Nombre de la opción',
        textoBoton: 'Agregar',
        esSemana: esSemana,
      ),
    );
    if (valor == null || valor.trim().isEmpty) return;
    await _ejecutar(() async {
      await _rpc('agregar', valor: valor.trim());
      await _cargar();
      Get.snackbar(
        'Opción agregada',
        'La opción aparecerá al abrir de nuevo el formulario.',
      );
    });
  }

  Future<void> _editar(Map<String, dynamic> opcion) async {
    final id = int.tryParse(opcion['id']?.toString() ?? '');
    if (id == null) return;
    final esSemana = _seleccionado.esSemana;
    final valor = await Get.to<String>(
      () => _CatalogoTextoPage(
        titulo: 'Editar opción',
        etiqueta: esSemana ? 'Número de semana (1 a 52)' : 'Nombre',
        textoBoton: 'Guardar',
        esSemana: esSemana,
        valorInicial: opcion['valor']?.toString() ?? '',
      ),
    );
    if (valor == null || valor.trim().isEmpty) return;
    await _ejecutar(() async {
      await _rpc('editar', id: id, valor: valor.trim());
      await _cargar();
      Get.snackbar('Opción actualizada', 'El cambio se guardó correctamente.');
    });
  }

  Future<void> _eliminar(Map<String, dynamic> opcion) async {
    final id = int.tryParse(opcion['id']?.toString() ?? '');
    if (id == null) return;
    final valor = opcion['valor']?.toString() ?? '';
    final confirmado = await Get.to<bool>(
      () => _ConfirmarEliminarCatalogoPage(valor: valor),
    );
    if (confirmado != true) return;
    await _ejecutar(() async {
      await _rpc('eliminar', id: id);
      await _cargar();
      Get.snackbar('Opción eliminada', valor);
    });
  }

  Future<void> _cambiarEstado(Map<String, dynamic> opcion, bool activo) async {
    final id = int.tryParse(opcion['id']?.toString() ?? '');
    if (id == null) return;
    await _ejecutar(() async {
      await _rpc('estado', id: id, activo: activo);
      await _cargar();
      Get.snackbar(
        activo ? 'Opción habilitada' : 'Opción inhabilitada',
        opcion['valor']?.toString() ?? '',
      );
    });
  }

  Future<void> _ejecutar(Future<void> Function() accion) async {
    setState(() => _guardando = true);
    try {
      await accion();
    } catch (e) {
      if (mounted) _mensajeError(e);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _mensajeError(Object error) {
    Get.snackbar(
      'No se pudo actualizar la lista',
      error.toString().replaceFirst('Exception: ', ''),
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 6),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Opciones de listas',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        backgroundColor: const Color(0xFF005F86),
        foregroundColor: Colors.white,
        toolbarHeight: 56,
        actions: [
          IconButton(
            onPressed: _guardando || _cargando ? null : _cargar,
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _guardando ? null : _agregar,
        backgroundColor: const Color(0xFF168B59),
        foregroundColor: Colors.white,
        tooltip: 'Agregar opción',
        child: const Icon(Icons.add_rounded),
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            padding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE1E7EC)),
            ),
            child: Row(
              children: [
                Icon(_seleccionado.icono, color: const Color(0xFF005F86)),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<_Catalogo>(
                      value: _seleccionado,
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(12),
                      items:
                          _catalogos
                              .map(
                                (catalogo) => DropdownMenuItem<_Catalogo>(
                                  value: catalogo,
                                  child: Text(
                                    catalogo.nombre,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                      onChanged:
                          _guardando
                              ? null
                              : (catalogo) {
                                if (catalogo == null) return;
                                setState(() => _seleccionado = catalogo);
                                _cargar();
                              },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_opciones.length}',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (_guardando) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child:
                _cargando
                    ? const Center(child: CircularProgressIndicator())
                    : _opciones.isEmpty
                    ? const Center(child: Text('No hay opciones para mostrar.'))
                    : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 84),
                      itemCount: _opciones.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 5),
                      itemBuilder: (context, index) {
                        final opcion = _opciones[index];
                        final activo = opcion['activo'] == true;
                        final valor = opcion['valor']?.toString() ?? '';
                        final etiqueta =
                            _seleccionado.esSemana ? 'Semana $valor' : valor;
                        return Card(
                          margin: EdgeInsets.zero,
                          elevation: 0,
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: Color(0xFFE8EDF1)),
                          ),
                          child: ListTile(
                            dense: true,
                            visualDensity: const VisualDensity(vertical: -2),
                            contentPadding: const EdgeInsets.only(
                              left: 14,
                              right: 4,
                            ),
                            leading: Icon(
                              activo
                                  ? Icons.check_circle_rounded
                                  : Icons.pause_circle_rounded,
                              size: 21,
                              color:
                                  activo
                                      ? const Color(0xFF168B59)
                                      : Colors.blueGrey,
                            ),
                            title: Text(
                              etiqueta,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color:
                                    activo
                                        ? const Color(0xFF243447)
                                        : Colors.blueGrey,
                              ),
                            ),
                            subtitle: Text(
                              activo ? 'Activa' : 'Inhabilitada',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: PopupMenuButton<String>(
                              enabled: !_guardando,
                              tooltip: 'Acciones',
                              onSelected: (accion) {
                                if (accion == 'estado') {
                                  _cambiarEstado(opcion, !activo);
                                } else if (accion == 'editar') {
                                  _editar(opcion);
                                } else if (accion == 'eliminar') {
                                  _eliminar(opcion);
                                }
                              },
                              itemBuilder:
                                  (context) => [
                                    PopupMenuItem(
                                      value: 'estado',
                                      child: Text(
                                        activo ? 'Inhabilitar' : 'Habilitar',
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'editar',
                                      child: Text('Editar'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'eliminar',
                                      child: Text('Eliminar'),
                                    ),
                                  ],
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}

class _CatalogoTextoPage extends StatefulWidget {
  const _CatalogoTextoPage({
    required this.titulo,
    required this.etiqueta,
    required this.textoBoton,
    this.valorInicial = '',
    this.esSemana = false,
    this.ocultarTexto = false,
  });

  final String titulo;
  final String etiqueta;
  final String textoBoton;
  final String valorInicial;
  final bool esSemana;
  final bool ocultarTexto;

  @override
  State<_CatalogoTextoPage> createState() => _CatalogoTextoPageState();
}

class _CatalogoTextoPageState extends State<_CatalogoTextoPage> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.valorInicial,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _guardar() {
    final texto = _controller.text.trim();
    if (texto.isEmpty) {
      setState(() => _error = 'Este campo es obligatorio.');
      return;
    }
    if (widget.esSemana) {
      final numero = int.tryParse(texto);
      if (numero == null || numero < 1 || numero > 52) {
        setState(() => _error = 'Ingresa un número entre 1 y 52.');
        return;
      }
    }
    Navigator.of(context).pop(texto);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(widget.titulo, style: const TextStyle(fontSize: 19)),
        toolbarHeight: 56,
        backgroundColor: const Color(0xFF005F86),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: !widget.ocultarTexto,
              obscureText: widget.ocultarTexto,
              keyboardType:
                  widget.ocultarTexto
                      ? TextInputType.visiblePassword
                      : widget.esSemana
                      ? TextInputType.number
                      : TextInputType.text,
              textCapitalization:
                  widget.esSemana || widget.ocultarTexto
                      ? TextCapitalization.none
                      : TextCapitalization.words,
              maxLength: widget.ocultarTexto ? null : 100,
              decoration: InputDecoration(
                labelText: widget.etiqueta,
                errorText: _error,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: (_) => _guardar(),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _guardar,
              icon: const Icon(Icons.check_rounded),
              label: Text(widget.textoBoton),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF168B59),
                minimumSize: const Size.fromHeight(46),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmarEliminarCatalogoPage extends StatelessWidget {
  const _ConfirmarEliminarCatalogoPage({required this.valor});
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Eliminar opción', style: TextStyle(fontSize: 19)),
        toolbarHeight: 56,
        backgroundColor: const Color(0xFF005F86),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.delete_outline_rounded,
              size: 54,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 16),
            Text(
              '¿Eliminar "$valor" de la lista?',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Los datos históricos guardados no se modificarán.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.delete_rounded),
              label: const Text('Eliminar'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                minimumSize: const Size.fromHeight(46),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}
