// lib/historial_bloque_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_application_1/formulario_page.dart';
import 'package:flutter_application_1/preview_aspersion_page.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'login_controller.dart';
import 'package:intl/intl.dart';
import 'package:flutter_application_1/excel_service.dart'; // ajusta la ruta si es necesario
import 'offline_sync_service.dart';
import 'dart:math';

enum _ModoHistorial { semana, mes }

class HistorialBloquePage extends StatefulWidget {
  final String bloque;

  const HistorialBloquePage({super.key, required this.bloque});

  @override
  State<HistorialBloquePage> createState() => _HistorialBloquePageState();
}

class _HistorialBloquePageState extends State<HistorialBloquePage> {
  static const Color brandBlue = Color(0xFF008DC5);
  static const Color darkBlue = Color(0xFF005F86);
  late Future<List<dynamic>> futureRegistros;

  String? _mesSeleccionado;
  List<String> _listaMeses = [];
  final Map<String, List<dynamic>> _registrosAgrupados = {};
  _ModoHistorial _modoHistorial = _ModoHistorial.semana;

  // Paginación por semanas del bloque.
  // 0 = semana más reciente del mes.
  int _indiceSemanaMes = 0;

  // progreso
  double _exportProgress = 0.0;
  bool _isExporting = false;
  bool _isCancelRequested = false;

  @override
  void initState() {
    super.initState();
    futureRegistros = fetchRegistrosPorBloque();
  }

  Future<List<dynamic>> fetchRegistrosPorBloque() async {
    final LoginController loginController = Get.find<LoginController>();
    try {
      final int numeroBloque = int.parse(widget.bloque.trim());
      final url = Uri.parse(
        '${loginController.supabaseUrl}/rest/v1/aspersiones?bloque=eq.$numeroBloque&select=*&order=fecha_registro.desc',
      );

      final response = await http
          .get(
            url,
            headers: {
              'apikey': loginController.apiKey,
              'Authorization': 'Bearer ${loginController.apiKey}',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final registros = json.decode(response.body);
        await OfflineSyncService.guardarCacheBloque(widget.bloque, registros);
        return registros;
      } else {
        return OfflineSyncService.leerCacheBloque(widget.bloque);
      }
    } catch (e) {
      return OfflineSyncService.leerCacheBloque(widget.bloque);
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

    if ((_mesSeleccionado == null ||
            !_registrosAgrupados.containsKey(_mesSeleccionado)) &&
        _listaMeses.isNotEmpty) {
      _mesSeleccionado = _listaMeses[0];
    }
  }

  String _semanaDeRegistro(List<dynamic> registros) {
    for (final registro in registros) {
      final fecha = DateTime.tryParse(
        registro['fecha_registro']?.toString() ?? '',
      )?.toLocal();
      if (fecha != null) return _numeroSemanaISO(fecha).toString();
    }
    return '-';
  }

  int _numeroSemanaISO(DateTime fecha) {
    final jueves = DateTime(
      fecha.year,
      fecha.month,
      fecha.day,
    ).add(Duration(days: 4 - fecha.weekday));
    final inicioPrimeraSemana = _inicioDeSemana(DateTime(jueves.year, 1, 4));
    return (jueves.difference(inicioPrimeraSemana).inDays ~/ 7) + 1;
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
      ..sort((a, b) => b.key.compareTo(a.key));
    return entradas;
  }

  /// Texto con el rango de fechas de la semana (lunes a domingo).
  String _rangoSemana(DateTime inicio) {
    final fin = inicio.add(const Duration(days: 6));
    final f1 = DateFormat("d 'de' MMM", 'es').format(inicio);
    final f2 = DateFormat("d 'de' MMM", 'es').format(fin);
    return '$f1 - $f2';
  }

  void _exportarSemana() async {
    final registros = await futureRegistros;
    final List<dynamic> registrosExportar;
    if (_modoHistorial == _ModoHistorial.mes) {
      _agruparRegistrosPorMes(registros);
      registrosExportar = _mesSeleccionado == null
          ? <dynamic>[]
          : (_registrosAgrupados[_mesSeleccionado] ?? []);
    } else {
      final semanas = _agruparPorSemana(registros);
      if (semanas.isEmpty) return;
      final indice = _indiceSemanaMes.clamp(0, semanas.length - 1).toInt();
      registrosExportar = semanas[indice].value;
    }
    if (registrosExportar.isEmpty) return;

    setState(() {
      _isExporting = true;
      _isCancelRequested = false;
      _exportProgress = 0.0;
    });
    final cancelToken = MIPECancellationToken();
    void Function(void Function())? dialogSetState;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          dialogSetState = setDialogState;
          return AlertDialog(
            title: Text(_modoHistorial == _ModoHistorial.mes
                ? 'Exportando mes'
                : 'Exportando semana'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExportProgressDonut(
                  progress: _exportProgress,
                  size: 110,
                  primaryColor: brandBlue,
                  backgroundColor: const Color(0xFFE9F3F8),
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _exportProgress, color: brandBlue),
                const SizedBox(height: 8),
                Text(_isCancelRequested
                    ? 'Cancelando...'
                    : '${(_exportProgress * 100).toStringAsFixed(0)}%'),
              ],
            ),
            actions: [
              TextButton.icon(
                onPressed: _isCancelRequested
                    ? () => Navigator.of(dialogContext).pop()
                    : () {
                        setState(() => _isCancelRequested = true);
                        cancelToken.cancel();
                      },
                icon: Icon(_isCancelRequested
                    ? Icons.close
                    : Icons.cancel_outlined),
                label: Text(_isCancelRequested ? 'Cerrar' : 'Cancelar'),
              ),
            ],
          );
        },
      ),
    );

    try {
      final outPath = await MIPEExcelService.generarReporteMIPE(
        registrosExportar,
        nombreArchivo: _modoHistorial == _ModoHistorial.mes
            ? 'Bloque_${widget.bloque}_Mes_${_mesSeleccionado ?? 'seleccionado'}'
            : 'Bloque_${widget.bloque}_Semana_${_semanaDeRegistro(registrosExportar)}',
        onProgress: (progress) {
          setState(() => _exportProgress = progress.clamp(0.0, 1.0));
          dialogSetState?.call(() {});
        },
        abrirArchivoAlFinal: true,
        bloqueHeader: widget.bloque,
        cancelToken: cancelToken,
      );

      setState(() {
        _isExporting = false;
        _isCancelRequested = false;
        _exportProgress = 1.0;
      });
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      Get.snackbar('Exportado', 'Archivo generado: $outPath', snackPosition: SnackPosition.BOTTOM);
    } catch (error) {
      setState(() {
        _isExporting = false;
        _isCancelRequested = false;
        _exportProgress = 0.0;
      });
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      if (error is MIPECanceledException) {
        Get.snackbar('Exportación cancelada', 'No se creó ningún archivo.', snackPosition: SnackPosition.BOTTOM);
      } else {
        Get.snackbar('Error', 'Fallo al exportar: $error', snackPosition: SnackPosition.BOTTOM);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F8),
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
            padding: const EdgeInsets.fromLTRB(18, 50, 18, 24),
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
                  blurRadius: 22,
                  offset: const Offset(0, 9),
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
                        "BLOQUE ${widget.bloque}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Historial de aspersiones",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(.22)),
                  ),
                  child: const Icon(
                    Icons.water_drop_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ],
            ),
          ),

          // FILTROS
          Container(
            margin: const EdgeInsets.fromLTRB(14, 14, 14, 4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE1EBEF)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0C14343D),
                  blurRadius: 14,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    SegmentedButton<_ModoHistorial>(
                      segments: const [
                        ButtonSegment(
                          value: _ModoHistorial.semana,
                          label: Text('Semana'),
                          icon: Icon(Icons.view_week_rounded),
                        ),
                        ButtonSegment(
                          value: _ModoHistorial.mes,
                          label: Text('Mes'),
                          icon: Icon(Icons.calendar_month_rounded),
                        ),
                      ],
                      selected: {_modoHistorial},
                      onSelectionChanged: (seleccion) {
                        setState(() {
                          _modoHistorial = seleccion.first;
                          _indiceSemanaMes = 0;
                        });
                      },
                    ),
                    const Spacer(),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        onPressed: _exportarSemana,
                        icon: const Icon(Icons.download_rounded, color: brandBlue),
                        tooltip: 'Exportar registros',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_modoHistorial == _ModoHistorial.mes)
                  FutureBuilder<List<dynamic>>(
                    future: futureRegistros,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || snapshot.hasError) {
                        return const SizedBox();
                      }
                      _agruparRegistrosPorMes(snapshot.data!);
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F7F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButton<String>(
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          underline: const SizedBox(),
                          value: _mesSeleccionado,
                          hint: const Text('Elegir mes'),
                          items: _listaMeses.map((mes) {
                            return DropdownMenuItem<String>(
                              value: mes,
                              child: Text(mes, overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() => _mesSeleccionado = value);
                          },
                        ),
                      );
                    },
                  )
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F7F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.date_range_rounded,
                            color: Color(0xFF52727D),
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Semana calculada por fecha',
                            style: TextStyle(
                              color: Color(0xFF52727D),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
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

                  final registrosBloque = snapshot.data!;

                  if (registrosBloque.isEmpty) {
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

                  if (_modoHistorial == _ModoHistorial.mes) {
                    _agruparRegistrosPorMes(registrosBloque);
                    final registrosMes = _mesSeleccionado == null
                        ? <dynamic>[]
                        : (_registrosAgrupados[_mesSeleccionado] ?? []);

                    if (registrosMes.isEmpty) {
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

                    return Column(
                      children: [
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE7F3F7),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_month_rounded, color: darkBlue, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '$_mesSeleccionado · ${registrosMes.length} registros',
                                  style: const TextStyle(color: darkBlue, fontWeight: FontWeight.w800),
                                ),
                              ),
                              Tooltip(
                                message: 'Ver plantilla del mes',
                                child: IconButton(
                                  onPressed: () {
                                    Get.to(
                                      () => PreviewAspersionPage(
                                        bloque: widget.bloque,
                                        registros: registrosMes,
                                      ),
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.visibility_rounded,
                                    color: darkBlue,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            itemCount: registrosMes.length,
                            itemBuilder: (context, index) => _buildItemCard(registrosMes[index]),
                          ),
                        ),
                      ],
                    );
                  }

                  final semanas = _agruparPorSemana(registrosBloque);

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

    final String semanaRegistro = _numeroSemanaISO(inicio).toString();

    // Hay semana más antigua disponible cuando idx puede aumentar.
    final bool puedeMasAntigua = idx < total - 1;
    // Hay semana más reciente disponible cuando idx puede disminuir.
    final bool puedeMasReciente = idx > 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F3F7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD4E8EE)),
        boxShadow: [
          BoxShadow(
            color: brandBlue.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
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
                  'Semana $semanaRegistro',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: darkBlue,
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
          Tooltip(
            message: 'Ver plantilla de esta semana',
            child: IconButton(
              onPressed: () {
                Get.to(
                  () => PreviewAspersionPage(
                    bloque: widget.bloque,
                    registros: semana.value,
                  ),
                );
              },
              icon: const Icon(Icons.visibility_rounded, color: darkBlue),
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
    final String semanaCalendario = _numeroSemanaISO(fecha).toString();

    final resumenProducto = _productoResumen(reg['producto']);
    final listaProductos = _parseProductoFieldToList(reg['producto']);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1EBEF)),
        boxShadow: [
          BoxShadow(
            color: const Color(0x1214343D),
            blurRadius: 16,
            offset: const Offset(0, 6),
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
                    Icons.water_drop_outlined,
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
                          color: darkBlue,
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
                      Row(
                        children: [
                          Text(
                            fechaCorta,
                            style: TextStyle(color: Colors.grey[500], fontSize: 11),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'SEM. $semanaCalendario',
                              style: const TextStyle(
                                color: darkBlue,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F7F9),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          '${reg['tipo_aplicacion'] ?? 'Aplicación'}  ·  ${reg['equipo'] ?? 'Equipo no indicado'}',
                          style: const TextStyle(
                            color: Color(0xFF52727D),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
                        color: darkBlue,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        size: 17,
                        color: brandBlue,
                      ),
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
