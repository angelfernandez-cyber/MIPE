// lib/historial_bloque_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_application_1/formulario_page.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'login_controller.dart';
import 'package:intl/intl.dart';
import 'package:flutter_application_1/excel_service.dart'; // ajusta la ruta si es necesario
import 'dart:math';

class HistorialBloquePage extends StatefulWidget {
  final String bloque;

  const HistorialBloquePage({super.key, required this.bloque});

  @override
  State<HistorialBloquePage> createState() => _HistorialBloquePageState();
}

class _HistorialBloquePageState extends State<HistorialBloquePage> {
  static const Color brandBlue = Color(0xFF008DC5);
  late Future<List<dynamic>> futureRegistros;

  final TextEditingController _searchController = TextEditingController();
  String? _mesSeleccionado;
  List<String> _listaMeses = [];

  // Agrupación por mes (etiqueta -> registros del mes)
  final Map<String, List<dynamic>> _registrosAgrupados = {};

  // Paginación por semanas dentro del mes seleccionado.
  // 0 = semana más reciente del mes.
  int _indiceSemanaMes = 0;

  // progreso
  double _exportProgress = 0.0;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    futureRegistros = fetchRegistrosPorBloque();
    _searchController.addListener(() {
      setState(() {
        // Al cambiar la búsqueda, las semanas disponibles pueden variar:
        // volvemos a la primera (más reciente).
        _indiceSemanaMes = 0;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<dynamic>> fetchRegistrosPorBloque() async {
    final LoginController loginController = Get.find<LoginController>();
    try {
      final int numeroBloque = int.parse(widget.bloque.trim());
      final url = Uri.parse(
        '${loginController.supabaseUrl}/rest/v1/aspersiones?bloque=eq.$numeroBloque&select=*&order=fecha_registro.desc',
      );

      final response = await http.get(
        url,
        headers: {
          'apikey': loginController.apiKey,
          'Authorization': 'Bearer ${loginController.apiKey}',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  // -------------------------
  // Helpers para producto JSON
  // -------------------------

  List<Map<String, dynamic>> _parseProductoFieldToList(dynamic productoField) {
    try {
      if (productoField == null) return [];
      if (productoField is String) {
        final decoded = jsonDecode(productoField);
        if (decoded is List) {
          return List<Map<String, dynamic>>.from(
              decoded.map((e) => Map<String, dynamic>.from(e)));
        }
        return [];
      } else if (productoField is List) {
        return List<Map<String, dynamic>>.from(
            productoField.map((e) => Map<String, dynamic>.from(e)));
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  String _productoResumen(dynamic productoField) {
    final lista = _parseProductoFieldToList(productoField);
    if (lista.isEmpty) return 'Sin producto';
    final p = lista[0];
    final nombre = (p['producto'] ?? '').toString();
    final dosis = (p['dosis'] ?? '').toString();
    final cat = (p['cat_toxic'] ?? '').toString();
    final parts = <String>[];
    if (nombre.isNotEmpty) parts.add(nombre);
    if (dosis.isNotEmpty) parts.add(dosis);
    final main = parts.join(' — ');
    if (cat.isNotEmpty && main.isNotEmpty) return '$main ($cat)';
    if (main.isNotEmpty) return main;
    if (cat.isNotEmpty) return cat;
    return 'Sin producto';
  }

  // -------------------------
  // Agrupación por mes
  // -------------------------
  void _agruparRegistrosPorMes(List<dynamic> registros) {
    _registrosAgrupados.clear();
    _listaMeses.clear();

    for (var reg in registros) {
      DateTime fechaReg = DateTime.tryParse(
            reg['fecha_registro'] ?? '',
          )?.toLocal() ??
          DateTime.now();

      // Agrupar por mes
      String mesLabel = DateFormat('MMMM y', 'es').format(fechaReg);
      DateTime ahora = DateTime.now();

      String tag;
      if (fechaReg.year == ahora.year && fechaReg.month == ahora.month) {
        tag = "ESTE MES";
      } else {
        tag = mesLabel;
      }

      if (!_registrosAgrupados.containsKey(tag)) {
        _registrosAgrupados[tag] = [];
      }

      _registrosAgrupados[tag]!.add(reg);
    }

    _listaMeses = _registrosAgrupados.keys.toList();

    if (_mesSeleccionado == null && _listaMeses.isNotEmpty) {
      _mesSeleccionado = _listaMeses[0];
    }
  }

  // -------------------------
  // Agrupación por semana (dentro del mes)
  // -------------------------

  /// Devuelve el lunes (inicio) de la semana que contiene a [d].
  DateTime _inicioDeSemana(DateTime d) {
    final base = DateTime(d.year, d.month, d.day);
    // weekday: lunes = 1 ... domingo = 7
    return base.subtract(Duration(days: base.weekday - 1));
  }

  /// Agrupa los registros (ya filtrados) en semanas.
  /// Devuelve una lista de entradas ordenadas de la semana más reciente
  /// a la más antigua. La clave es el lunes de cada semana.
  List<MapEntry<DateTime, List<dynamic>>> _agruparPorSemana(
      List<dynamic> registros) {
    final Map<DateTime, List<dynamic>> mapa = {};

    for (final reg in registros) {
      final fecha =
          DateTime.tryParse(reg['fecha_registro'] ?? '')?.toLocal() ??
              DateTime.now();
      final inicio = _inicioDeSemana(fecha);
      mapa.putIfAbsent(inicio, () => []).add(reg);
    }

    final entradas = mapa.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key)); // más reciente primero
    return entradas;
  }

  /// Texto con el rango de fechas de la semana (lunes a domingo).
  String _rangoSemana(DateTime inicio) {
    final fin = inicio.add(const Duration(days: 6));
    final f1 = DateFormat("d 'de' MMM", 'es').format(inicio);
    final f2 = DateFormat("d 'de' MMM", 'es').format(fin);
    return '$f1 - $f2';
  }

  List<dynamic> _filtrarRegistros(List<dynamic> registros) {
    if (_searchController.text.isEmpty) {
      return registros;
    }
    final busqueda = _searchController.text.toLowerCase();
    return registros.where((reg) {
      final lista = _parseProductoFieldToList(reg['producto']);
      for (var p in lista) {
        final nombre = (p['producto'] ?? '').toString().toLowerCase();
        final dosis = (p['dosis'] ?? '').toString().toLowerCase();
        final cat = (p['cat_toxic'] ?? '').toString().toLowerCase();
        if (nombre.contains(busqueda) ||
            dosis.contains(busqueda) ||
            cat.contains(busqueda)) {
          return true;
        }
      }
      final raw = (reg['producto'] ?? '').toString().toLowerCase();
      return raw.contains(busqueda);
    }).toList();
  }

  // -------------------------
  // Exportación con modal
  // -------------------------
  void _exportarSemana() async {
    if (_mesSeleccionado == null) return;

    List<dynamic> registrosExportar = _registrosAgrupados[_mesSeleccionado] ?? [];

    if (registrosExportar.isEmpty) {
      Get.snackbar('Error', 'No hay datos para exportar en este mes');
      return;
    }

    // Reiniciar estado
    setState(() {
      _isExporting = true;
      _exportProgress = 0.0;
    });

    // Variable para actualizar el estado dentro del diálogo
    void Function(void Function())? dialogSetState;

    // Mostrar diálogo modal (no dismissible mientras exporta)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(builder: (context, setStateDialog) {
          dialogSetState = setStateDialog;
          return AlertDialog(
            title: const Text('Exportando mes'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExportProgressDonut(
                    progress: _exportProgress,
                    size: 110,
                    primaryColor: brandBlue,
                    backgroundColor: const Color(0xFFE9F3F8),
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: _exportProgress,
                    color: brandBlue,
                    backgroundColor: Colors.grey[200],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(_exportProgress * 100).toStringAsFixed((_exportProgress * 100) >= 10 ? 0 : 1)}%',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
            actions: [
              if (!_isExporting)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('Cerrar'),
                ),
            ],
          );
        });
      },
    );

    try {
      final outPath = await MIPEExcelService.generarReporteMIPE(
        registrosExportar,
        nombreArchivo: 'Bloque_${widget.bloque}_Mes_$_mesSeleccionado',
        onProgress: (p) {
          // Actualizar estado de la página
          setState(() {
            _exportProgress = p.clamp(0.0, 1.0);
          });
          // Actualizar estado del diálogo si está disponible
          try {
            dialogSetState?.call(() {});
          } catch (_) {}
        },
        abrirArchivoAlFinal: true,
        bloqueHeader: widget.bloque,
      );

      // Finalizado correctamente
      setState(() {
        _isExporting = false;
        _exportProgress = 1.0;
      });

      // Cerrar diálogo si sigue abierto
      try {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      } catch (_) {}

      Get.snackbar('Exportado', 'Archivo generado: $outPath', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      // Error durante exportación
      setState(() {
        _isExporting = false;
        _exportProgress = 0.0;
      });

      // Cerrar diálogo si sigue abierto
      try {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      } catch (_) {}

      Get.snackbar('Error', 'Fallo al exportar: ${e.toString()}', snackPosition: SnackPosition.BOTTOM);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Get.to(
            () => const FormularioPage(),
            arguments: {'bloque': widget.bloque},
          );
        },
        backgroundColor: brandBlue,
        elevation: 5,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          "REGISTRAR",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      body: Column(
        children: [
          // HEADER
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(
              top: 50,
              left: 18,
              right: 18,
              bottom: 18,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [brandBlue, const Color(0xFF005F86)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: brandBlue.withOpacity(0.18),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: () => Get.back(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "HISTORIAL BLOQUE ${widget.bloque}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Consulta de registros y aspersiones",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // BARRA DE BÚSQUEDA Y FILTROS
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar por producto...',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    prefixIcon: const Icon(Icons.search, color: brandBlue),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: brandBlue, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FutureBuilder<List<dynamic>>(
                        future: futureRegistros,
                        builder: (context, snapshot) {
                          if (snapshot.hasData && !snapshot.hasError) {
                            _agruparRegistrosPorMes(snapshot.data!);
                            return DropdownButton<String>(
                              isExpanded: true,
                              value: _mesSeleccionado,
                              hint: const Text('Filtrar por mes'),
                              items: _listaMeses.map((mes) {
                                return DropdownMenuItem<String>(
                                  value: mes,
                                  child: Text(mes, overflow: TextOverflow.ellipsis),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _mesSeleccionado = value;
                                  // Al cambiar de mes, volver a la semana más reciente.
                                  _indiceSemanaMes = 0;
                                });
                              },
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: brandBlue,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: IconButton(
                        onPressed: _exportarSemana,
                        icon: const Icon(Icons.download, color: Colors.white),
                        tooltip: 'Exportar mes',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // CONTENIDO
          Expanded(
            child: RefreshIndicator(
              color: brandBlue,
              onRefresh: () async {
                setState(() {
                  futureRegistros = fetchRegistrosPorBloque();
                  _indiceSemanaMes = 0;
                });
                try {
                  await futureRegistros;
                } catch (_) {}
              },
              child: FutureBuilder<List<dynamic>>(
                future: futureRegistros,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 250),
                        Center(
                          child: CircularProgressIndicator(color: brandBlue),
                        ),
                      ],
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: _buildEmptyState(),
                        ),
                      ],
                    );
                  }

                  _agruparRegistrosPorMes(snapshot.data!);

                  if (_mesSeleccionado == null ||
                      !_registrosAgrupados.containsKey(_mesSeleccionado)) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: _buildEmptyState(),
                        ),
                      ],
                    );
                  }

                  List<dynamic> registrosMes =
                      _filtrarRegistros(_registrosAgrupados[_mesSeleccionado]!);

                  if (registrosMes.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: Center(
                            child: Text(
                              'No hay registros que coincidan con tu búsqueda',
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  // Paginación por semanas dentro del mes seleccionado.
                  final semanas = _agruparPorSemana(registrosMes);

                  if (semanas.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: _buildEmptyState(),
                        ),
                      ],
                    );
                  }

                  // Aseguramos que el índice esté dentro de rango.
                  final int idx =
                      _indiceSemanaMes.clamp(0, semanas.length - 1).toInt();
                  final semanaActual = semanas[idx];
                  final registrosSemana = semanaActual.value;

                  return Column(
                    children: [
                      _buildNavegadorSemanas(semanas, idx),
                      Expanded(
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: registrosSemana.length,
                          itemBuilder: (context, index) {
                            return _buildItemCard(registrosSemana[index]);
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------
  // Navegador de semanas (paginación)
  // -------------------------
  Widget _buildNavegadorSemanas(
      List<MapEntry<DateTime, List<dynamic>>> semanas, int idx) {
    final int total = semanas.length;
    final semana = semanas[idx];
    final DateTime inicio = semana.key;
    final int cantidad = semana.value.length;

    // idx 0 = semana más reciente. Numeramos cronológicamente:
    // la más antigua es "Semana 1".
    final int numeroSemana = total - idx;

    // Hay semana más antigua disponible cuando idx puede aumentar.
    final bool puedeMasAntigua = idx < total - 1;
    // Hay semana más reciente disponible cuando idx puede disminuir.
    final bool puedeMasReciente = idx > 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          _navButton(
            icon: Icons.chevron_left_rounded,
            enabled: puedeMasAntigua,
            tooltip: 'Semana anterior',
            onTap: () {
              setState(() {
                _indiceSemanaMes = idx + 1;
              });
            },
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Semana $numeroSemana de $total',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: brandBlue,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _rangoSemana(inicio),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$cantidad ${cantidad == 1 ? 'registro' : 'registros'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          _navButton(
            icon: Icons.chevron_right_rounded,
            enabled: puedeMasReciente,
            tooltip: 'Semana siguiente',
            onTap: () {
              setState(() {
                _indiceSemanaMes = idx - 1;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _navButton({
    required IconData icon,
    required bool enabled,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: enabled ? brandBlue.withOpacity(0.10) : Colors.grey[100],
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              color: enabled ? brandBlue : Colors.grey[400],
              size: 26,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItemCard(dynamic reg) {
    DateTime fecha = DateTime.parse(reg['fecha_registro']).toLocal();
    String hora = DateFormat('hh:mm a').format(fecha);
    String fechaCorta = DateFormat("d 'de' MMMM, y", 'es').format(fecha);

    final resumenProducto = _productoResumen(reg['producto']);
    final listaProductos = _parseProductoFieldToList(reg['producto']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Get.to(() => const FormularioPage(), arguments: reg);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: brandBlue.withOpacity(0.1),
                  radius: 22,
                  child: const Icon(
                    Icons.water_drop_rounded,
                    color: brandBlue,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        resumenProducto,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF2D3142),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Operario: ${reg['usuario_registro'] ?? 'Operario'}",
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        fechaCorta,
                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                      ),
                      if (listaProductos.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          listaProductos.map((p) {
                            final n = p['producto'] ?? '';
                            final d = p['dosis'] ?? '';
                            final c = p['cat_toxic'] ?? '';
                            final parts = <String>[];
                            if ((n ?? '').toString().isNotEmpty) parts.add(n.toString());
                            if ((d ?? '').toString().isNotEmpty) parts.add('Dosis: ${d.toString()}');
                            if ((c ?? '').toString().isNotEmpty) parts.add('Cat: ${c.toString()}');
                            return parts.join(' • ');
                          }).join('\n'),
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      hora,
                      style: const TextStyle(
                        color: brandBlue,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: Colors.grey,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: brandBlue.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.calendar_month_rounded,
              size: 70,
              color: brandBlue.withOpacity(0.3),
            ),
          ),
          const SizedBox(height: 15),
          const Text(
            "Sin registros este mes",
            style: TextStyle(
              color: Colors.blueGrey,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          Text(
            "Los datos semanales aparecerán aquí.",
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Donut de progreso (sin dependencias externas)
class ExportProgressDonut extends StatelessWidget {
  final double progress; // 0.0 .. 1.0
  final double size;
  final Color primaryColor;
  final Color backgroundColor;

  const ExportProgressDonut({
    Key? key,
    required this.progress,
    this.size = 120,
    this.primaryColor = const Color(0xFF008DC5),
    this.backgroundColor = const Color(0xFFE9F3F8),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final double p = progress.clamp(0.0, 1.0);
    final percent = (p * 100);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _DonutPainter(progress: p, color: primaryColor),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${percent.toStringAsFixed(percent >= 10 ? 0 : 1)}%',
                style: TextStyle(
                  color: primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: size * 0.20,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                p >= 1.0 ? 'Listo' : (p > 0 ? 'Exportando' : 'Sin exportar'),
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: size * 0.10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final double progress;
  final Color color;

  _DonutPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.12;
    final rect = Offset.zero & size;
    
    final center = rect.center;
    final radius = (size.width - stroke) / 2;
    final bgPaint = Paint()
      ..color = Colors.transparent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);
    
    final basePaint = Paint()
      ..color = color.withOpacity(0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, basePaint);

    final startAngle = -pi / 2;
    final sweepAngle = 2 * pi * progress;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
