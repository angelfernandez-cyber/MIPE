// lib/historial_aseguramiento_page.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'login_controller.dart';
import 'formulario_almacen_page.dart';
import 'aseguramiento_excel_service.dart';
import 'dart:async';
import 'offline_sync_service.dart';

class HistorialAseguramientoPage extends StatefulWidget {
  const HistorialAseguramientoPage({super.key});

  @override
  State<HistorialAseguramientoPage> createState() =>
      _HistorialAseguramientoPageState();
}

class _HistorialAseguramientoPageState
    extends State<HistorialAseguramientoPage> {
  final LoginController loginController = Get.find<LoginController>();
  static const Color brandBlue = Color(0xFF008DC5);

  List<dynamic> _todosLosRegistros = [];
  List<dynamic> _registrosFiltrados = [];

  int _paginaActual = 0;
  final int _filasPorPagina = 15;

  String? _tipoFiltroPeriodo;
  int? _periodoSeleccionado;
  int? _anioFiltro;
  bool _isLoading = true;

  // Controladores para sincronizar el scroll horizontal
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _headerHorizontalController = ScrollController();

  // progreso exportación (estado de la página, usado para resumen pequeño si lo deseas)
  double _exportProgress = 0.0;
  bool _isExporting = false;
  Timer? _refreshTimer;

  bool get _puedeExportar {
    final user = loginController.loggedInUser.value;
    final permisos = (user?['lectura']?.toString() ?? '')
        .toLowerCase()
        .split(',')
        .map((e) => e.trim());
    return user?['admin']?.toString().trim() == 'S' ||
        permisos.contains('exportar_excel');
  }

  @override
  void initState() {
    super.initState();
    _fetchDatos();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) _fetchDatos(showLoading: false);
    });

    // Sincronización de scroll: lo que muevas abajo se mueve arriba
    _horizontalController.addListener(() {
      if (_headerHorizontalController.hasClients) {
        _headerHorizontalController.jumpTo(_horizontalController.offset);
      }
    });
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _headerHorizontalController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchDatos({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);
    try {
      final url = Uri.parse(
        '${loginController.supabaseUrl}/rest/v1/aseguramiento_plaguicidas?select=*&order=fecha.desc',
      );
      final data = await OfflineSyncService.fetchListWithCache(
        cacheKey: 'cache_aseguramiento_plaguicidas',
        url: url,
        headers: {
          'apikey': loginController.apiKey,
          'Authorization': 'Bearer ${loginController.apiKey}',
        },
      );
      if (mounted) {
        setState(() {
          _todosLosRegistros = data;
          _registrosFiltrados = _filtrarLista(
            data,
            _tipoFiltroPeriodo,
            _periodoSeleccionado,
            _anioFiltro,
          );
          _isLoading = false;
          _paginaActual = 0;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filtrarPorPeriodo(String? tipo, int? periodo, int? anio) {
    setState(() {
      _tipoFiltroPeriodo = tipo;
      _periodoSeleccionado = periodo;
      _anioFiltro = anio;
      _paginaActual = 0;
      _registrosFiltrados = _filtrarLista(
        _todosLosRegistros,
        tipo,
        periodo,
        anio,
      );
    });
  }

  List<dynamic> _filtrarLista(
    List<dynamic> registros,
    String? tipo,
    int? periodo,
    int? anio,
  ) {
    if (tipo == null || periodo == null || anio == null) return registros;
    if (tipo == 'semana') {
      return registros.where((registro) {
        final fechaRegistro = DateTime.tryParse(
          registro['fecha']?.toString() ?? '',
        );
        return fechaRegistro != null &&
            fechaRegistro.year == anio &&
            int.tryParse(registro['semana']?.toString() ?? '') == periodo;
      }).toList();
    }
    return registros.where((registro) {
      final fechaRegistro = DateTime.tryParse(
        registro['fecha']?.toString() ?? '',
      );
      return fechaRegistro != null &&
          fechaRegistro.year == anio &&
          fechaRegistro.month == periodo;
    }).toList();
  }

  String get _textoFiltroActivo {
    final periodo = _periodoSeleccionado;
    final anio = _anioFiltro;
    if (periodo == null || anio == null || _tipoFiltroPeriodo == null) {
      return 'Todos los registros';
    }
    if (_tipoFiltroPeriodo == 'semana') {
      return 'Semana $periodo de $anio';
    }
    const meses = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    return '${meses[periodo - 1]} de $anio';
  }

  Future<void> _elegirFiltroPeriodo() async {
    final tipo = await showDialog<String>(
      context: context,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Filtrar registros',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Elige cómo quieres organizar el historial.',
                    style: TextStyle(color: Colors.blueGrey.shade600),
                  ),
                  const SizedBox(height: 20),
                  _opcionFiltroPeriodo(
                    context,
                    icon: Icons.calendar_view_week_rounded,
                    titulo: 'Por semana',
                    detalle: 'Selecciona el número de semana',
                    tipo: 'semana',
                  ),
                  const SizedBox(height: 10),
                  _opcionFiltroPeriodo(
                    context,
                    icon: Icons.calendar_month_rounded,
                    titulo: 'Por mes',
                    detalle: 'Selecciona un mes del año',
                    tipo: 'mes',
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
    if (tipo == null || !mounted) return;

    final anios =
        _todosLosRegistros
            .map(
              (registro) =>
                  DateTime.tryParse(registro['fecha']?.toString() ?? ''),
            )
            .whereType<DateTime>()
            .map((fecha) => fecha.year)
            .toSet();
    anios.add(DateTime.now().year);
    if (_anioFiltro != null) anios.add(_anioFiltro!);
    final aniosOrdenados = anios.toList()..sort((a, b) => b.compareTo(a));
    const meses = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];
    int periodoElegido =
        _tipoFiltroPeriodo == tipo && _periodoSeleccionado != null
            ? _periodoSeleccionado!
            : tipo == 'semana'
            ? 1
            : DateTime.now().month;
    int anioElegido = _anioFiltro ?? DateTime.now().year;

    final seleccion = await showDialog<Map<String, int>>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => Dialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(22, 20, 16, 20),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF0789BD), Color(0xFF00658F)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: Icon(
                                  tipo == 'semana'
                                      ? Icons.calendar_view_week_rounded
                                      : Icons.calendar_month_rounded,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tipo == 'semana'
                                          ? 'Filtro por semana'
                                          : 'Filtro por mes',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 19,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    const Text(
                                      'Escoge el periodo del historial',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                          child: Column(
                            children: [
                              DropdownButtonFormField<int>(
                                initialValue: periodoElegido,
                                decoration: InputDecoration(
                                  labelText:
                                      tipo == 'semana'
                                          ? 'Número de semana'
                                          : 'Mes',
                                  prefixIcon: Icon(
                                    tipo == 'semana'
                                        ? Icons.date_range_rounded
                                        : Icons.calendar_today_rounded,
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFFF4F8FA),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                items:
                                    tipo == 'semana'
                                        ? List.generate(
                                              52,
                                              (index) => index + 1,
                                            )
                                            .map(
                                              (semana) => DropdownMenuItem(
                                                value: semana,
                                                child: Text('Semana $semana'),
                                              ),
                                            )
                                            .toList()
                                        : List.generate(
                                              12,
                                              (index) => index + 1,
                                            )
                                            .map(
                                              (mes) => DropdownMenuItem(
                                                value: mes,
                                                child: Text(meses[mes - 1]),
                                              ),
                                            )
                                            .toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setDialogState(
                                      () => periodoElegido = value,
                                    );
                                  }
                                },
                              ),
                              const SizedBox(height: 14),
                              DropdownButtonFormField<int>(
                                initialValue: anioElegido,
                                decoration: InputDecoration(
                                  labelText: 'Año',
                                  prefixIcon: const Icon(Icons.event_rounded),
                                  filled: true,
                                  fillColor: const Color(0xFFF4F8FA),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                items:
                                    aniosOrdenados
                                        .map(
                                          (anio) => DropdownMenuItem(
                                            value: anio,
                                            child: Text(anio.toString()),
                                          ),
                                        )
                                        .toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setDialogState(() => anioElegido = value);
                                  }
                                },
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => Navigator.pop(context),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                      child: const Text('Cancelar'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed:
                                          () => Navigator.pop(context, {
                                            'periodo': periodoElegido,
                                            'anio': anioElegido,
                                          }),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: brandBlue,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.filter_alt_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Aplicar filtro'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ),
    );
    if (seleccion != null && mounted) {
      _filtrarPorPeriodo(tipo, seleccion['periodo'], seleccion['anio']);
    }
  }

  Widget _opcionFiltroPeriodo(
    BuildContext context, {
    required IconData icon,
    required String titulo,
    required String detalle,
    required String tipo,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.pop(context, tipo),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F9FB),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: brandBlue.withOpacity(0.12)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: brandBlue.withOpacity(0.11),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: brandBlue),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF17324D),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detalle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: brandBlue),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconoEstado(dynamic valor) {
    if (valor == null) return const SizedBox.shrink();

    final String check = valor.toString().trim().toUpperCase();

    if (check == 'CUMPLE') {
      return const Icon(Icons.check_circle, color: Colors.green, size: 22);
    } else if (check == 'NO CUMPLE') {
      return const Icon(Icons.cancel, color: Colors.red, size: 22);
    }

    return Text(valor.toString(), style: const TextStyle(fontSize: 11));
  }

  List<dynamic> _obtenerDatosPaginados() {
    int inicio = _paginaActual * _filasPorPagina;
    int fin = inicio + _filasPorPagina;
    if (fin > _registrosFiltrados.length) fin = _registrosFiltrados.length;
    return _registrosFiltrados.sublist(inicio, fin);
  }

  // -------------------------
  // Exportación con modal (ValueNotifier para que la gráfica se actualice inmediatamente)
  // -------------------------
  Future<void> _exportarExcelConModal() async {
    if (!_puedeExportar) {
      Get.snackbar('Sin permiso', 'No tienes permiso para exportar a Excel');
      return;
    }

    // Trae las firmas recién guardadas o recuperadas desde Supabase antes de
    // copiar los registros para el Excel. La lista en pantalla puede estar en caché.
    await _fetchDatos(showLoading: false);
    if (!mounted) return;

    if (_registrosFiltrados.isEmpty) {
      Get.snackbar('Error', 'No hay datos para exportar');
      return;
    }

    final registrosParaExportar =
        _registrosFiltrados
            .map((e) => e is Map ? Map<String, dynamic>.from(e) : e)
            .toList();

    // Reiniciar estado de la página
    setState(() {
      _isExporting = true;
      _exportProgress = 0.0;
    });

    // Usamos ValueNotifier para que el diálogo escuche cambios y reconstruya solo su contenido
    final ValueNotifier<double> progressNotifier = ValueNotifier<double>(0.0);
    final ValueNotifier<bool> cancelRequestedNotifier = ValueNotifier<bool>(
      false,
    );
    final cancelToken = CancellationToken();

    // Mostrar diálogo inmediatamente (no dismissible)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Exportando Excel'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ValueListenableBuilder actualiza la UI del diálogo cuando cambia progressNotifier.value
                ValueListenableBuilder<double>(
                  valueListenable: progressNotifier,
                  builder: (context, value, _) {
                    final percent = (value * 100).clamp(0.0, 100.0);
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 110,
                          height: 110,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 110,
                                height: 110,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE9F3F8),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              SizedBox(
                                width: 110,
                                height: 110,
                                child: CustomPaint(
                                  painter: _DonutPainter(
                                    progress: value,
                                    color: brandBlue,
                                  ),
                                ),
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${percent.toStringAsFixed(percent >= 10 ? 0 : 1)}%',
                                    style: TextStyle(
                                      color: brandBlue,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    value >= 1.0 ? 'Listo' : 'Exportando',
                                    style: TextStyle(
                                      color: Colors.grey[700],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: value.clamp(0.0, 1.0),
                          color: brandBlue,
                          backgroundColor: Colors.grey[200],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${percent.toStringAsFixed(percent >= 10 ? 0 : 1)}%',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            // El botón cerrar solo aparece cuando la exportación terminó
            ValueListenableBuilder<double>(
              valueListenable: progressNotifier,
              builder: (context, value, _) {
                if (value >= 1.0) {
                  return TextButton(
                    onPressed: () {
                      Navigator.of(context, rootNavigator: true).pop();
                    },
                    child: const Text('Cerrar'),
                  );
                }
                if (value >= 0.94) {
                  return const TextButton(
                    onPressed: null,
                    child: Text('Guardando archivo...'),
                  );
                }
                return ValueListenableBuilder<bool>(
                  valueListenable: cancelRequestedNotifier,
                  builder:
                      (context, cancelRequested, _) => TextButton.icon(
                        onPressed:
                            cancelRequested
                                ? null
                                : () {
                                  cancelToken.cancel();
                                  cancelRequestedNotifier.value = true;
                                },
                        icon:
                            cancelRequested
                                ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Icon(Icons.cancel_outlined),
                        label: Text(
                          cancelRequested
                              ? 'Cancelando...'
                              : 'Cancelar exportación',
                        ),
                      ),
                );
              },
            ),
          ],
        );
      },
    );

    // Ejecutar la exportación en la siguiente iteración para permitir que el diálogo se renderice
    Future.microtask(() async {
      // pequeño retraso opcional para asegurar renderizado en dispositivos lentos
      await Future.delayed(const Duration(milliseconds: 50));

      try {
        final outPath = await AseguramientoExcelService.generarReporte(
          registrosParaExportar,
          nombreArchivo: 'Aseguramiento',
          cancelToken: cancelToken,
          onProgress: (p) {
            // Actualizamos tanto el estado de la página como el ValueNotifier del diálogo
            if (!mounted) return;
            final clamped = p.clamp(0.0, 1.0);
            setState(() {
              _exportProgress = clamped;
            });
            try {
              progressNotifier.value = clamped;
            } catch (_) {}
          },
        );

        if (!mounted) return;
        setState(() {
          _isExporting = false;
          _exportProgress = 1.0;
        });

        // Aseguramos que el diálogo tenga tiempo de mostrar 100% antes de cerrarlo
        await Future.delayed(const Duration(milliseconds: 200));

        // Cerrar diálogo si sigue abierto (usar rootNavigator para asegurar que cerramos el dialog correcto)
        try {
          if (Navigator.of(context, rootNavigator: true).canPop()) {
            Navigator.of(context, rootNavigator: true).pop();
          }
        } catch (_) {}

        // Liberar el notifier
        progressNotifier.dispose();
        cancelRequestedNotifier.dispose();

        Get.snackbar(
          'Exportado',
          'Archivo generado: $outPath',
          snackPosition: SnackPosition.BOTTOM,
        );
      } catch (e) {
        if (mounted) {
          setState(() {
            _isExporting = false;
            _exportProgress = 0.0;
          });
        }

        // Cerrar diálogo si sigue abierto
        try {
          if (Navigator.of(context, rootNavigator: true).canPop()) {
            Navigator.of(context, rootNavigator: true).pop();
          }
        } catch (_) {}

        // Liberar el notifier
        try {
          progressNotifier.dispose();
        } catch (_) {}
        try {
          cancelRequestedNotifier.dispose();
        } catch (_) {}

        if (cancelToken.isCancelled) {
          Get.snackbar(
            'Exportación cancelada',
            'No se generó el archivo Excel.',
            snackPosition: SnackPosition.BOTTOM,
          );
        } else {
          Get.snackbar(
            'Error',
            'Fallo al exportar: ${e.toString()}',
            snackPosition: SnackPosition.BOTTOM,
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),

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

            // TÍTULO
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Historial",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    "ALMACÉN",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        actions: [
          // BOTÓN NUEVO
          if (loginController.visitantePuedeInsertar)
            Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: IconButton(
                icon: const Icon(Icons.add_rounded, color: Colors.white),
                onPressed:
                    () => Get.to(
                      () => const AseguramientoPage(),
                    )?.then((value) => _fetchDatos()),
                tooltip: "Nuevo Registro",
              ),
            ),

          // BOTÓN EXCEL (ahora abre modal y muestra progreso)
          if (_registrosFiltrados.isNotEmpty && _puedeExportar)
            Container(
              margin: const EdgeInsets.only(right: 15),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.file_download_rounded,
                  color: Colors.white,
                ),
                onPressed: _exportarExcelConModal,
                tooltip: "Exportar Excel",
              ),
            ),
        ],
      ),

      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator(color: brandBlue))
              : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(15, 12, 15, 0),
                    child: _buildFiltroYBanner(),
                  ),

                  Expanded(
                    child:
                        _registrosFiltrados.isEmpty
                            ? _buildSinInformacion()
                            : Column(
                              children: [
                                Expanded(child: _buildTablaEstructuraFija()),

                                if (_registrosFiltrados.length >
                                    _filasPorPagina)
                                  _buildControlesPaginacion(),
                              ],
                            ),
                  ),
                ],
              ),
    );
  }

  Widget _buildFiltroYBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _periodoSeleccionado == null
                    ? _textoFiltroActivo
                    : 'Filtrado: $_textoFiltroActivo',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                  fontSize: 14,
                ),
              ),
              Text(
                "${_registrosFiltrados.length} registros encontrados",
                style: const TextStyle(
                  color: brandBlue,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          ActionChip(
            elevation: 2,
            backgroundColor:
                _periodoSeleccionado == null
                    ? Colors.white
                    : brandBlue.withOpacity(0.1),
            side: const BorderSide(color: brandBlue, width: 1),
            avatar: Icon(
              _periodoSeleccionado == null
                  ? Icons.calendar_month
                  : Icons.filter_alt_off,
              size: 18,
              color: brandBlue,
            ),
            label: Text(
              _periodoSeleccionado == null ? 'Filtrar semana / mes' : 'Limpiar',
              style: const TextStyle(
                color: brandBlue,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: () async {
              if (_periodoSeleccionado != null) {
                _filtrarPorPeriodo(null, null, null);
              } else {
                await _elegirFiltroPeriodo();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTablaEstructuraFija() {
    final datosPaginados = _obtenerDatosPaginados();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF8FBFF), Colors.white],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: brandBlue.withOpacity(0.15),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: Column(
          children: [
            // 🔥 HEADER ULTRA PRO
            Container(
              padding: const EdgeInsets.symmetric(vertical: 5),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF008DC5), Color(0xFF005F86)],
                ),
              ),
              child: SingleChildScrollView(
                controller: _headerHorizontalController,
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: IntrinsicWidth(
                  child: DataTable(
                    showCheckboxColumn: false,
                    headingRowHeight: 60,
                    horizontalMargin: 18,
                    columnSpacing: 28,
                    headingTextStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                    columns: _crearColumnas(),
                    rows: const [],
                  ),
                ),
              ),
            ),

            // 🔥 CUERPO PREMIUM
            Expanded(
              child: SingleChildScrollView(
                controller: _horizontalController,
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: IntrinsicWidth(
                    child: DataTable(
                      showCheckboxColumn: false,
                      headingRowHeight: 0,
                      horizontalMargin: 18,
                      columnSpacing: 28,
                      dataRowHeight: 60,
                      dividerThickness: 0,

                      columns:
                          _crearColumnas()
                              .map(
                                (c) => DataColumn(
                                  label: SizedBox(
                                    width: (c.label as SizedBox).width,
                                  ),
                                ),
                              )
                              .toList(),

                      rows: List.generate(datosPaginados.length, (index) {
                        final item = datosPaginados[index];

                        return DataRow(
                          color: MaterialStateProperty.resolveWith<Color?>((
                            states,
                          ) {
                            if (states.contains(MaterialState.hovered)) {
                              return brandBlue.withOpacity(0.12);
                            }
                            return index.isEven
                                ? Colors.white
                                : const Color(0xFFF7FAFC);
                          }),
                          onSelectChanged: (_) {
                            Get.to(
                              () => AseguramientoPage(
                                dataInicial: item,
                                esLectura: true,
                              ),
                            );
                          },
                          cells: _crearCeldas(item),
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<DataColumn> _crearColumnas() {
    TextStyle st = const TextStyle(
      fontWeight: FontWeight.bold,
      color: Colors.white,
      fontSize: 13,
    );
    // Definimos anchos fijos para que coincidan perfectamente header y body
    return [
      DataColumn(label: SizedBox(width: 45, child: Text('Sem.', style: st))),
      DataColumn(label: SizedBox(width: 85, child: Text('Fecha', style: st))),
      DataColumn(
        label: SizedBox(width: 140, child: Text('Producto', style: st)),
      ),
      DataColumn(
        label: SizedBox(width: 110, child: Text('Casa Comercial', style: st)),
      ),
      DataColumn(
        label: SizedBox(width: 75, child: Text('Formula C', style: st)),
      ),
      DataColumn(
        label: SizedBox(width: 75, child: Text('Cat Toxic', style: st)),
      ),
      DataColumn(
        label: SizedBox(
          width: 90,
          child: Text('Present.\n(Cantidad)', style: st),
        ),
      ),
      DataColumn(
        label: SizedBox(width: 50, child: Text('Cantidad', style: st)),
      ),
      DataColumn(label: SizedBox(width: 90, child: Text('Lote', style: st))),
      DataColumn(label: SizedBox(width: 85, child: Text('Vence', style: st))),
      DataColumn(
        label: SizedBox(width: 75, child: Text('Etiqueta', style: st)),
      ),
      DataColumn(label: SizedBox(width: 75, child: Text('Tapa', style: st))),
      DataColumn(label: SizedBox(width: 75, child: Text('Sellos', style: st))),
      DataColumn(label: SizedBox(width: 85, child: Text('Extrac.', style: st))),
      DataColumn(label: SizedBox(width: 60, child: Text('cc/g', style: st))),
      DataColumn(label: SizedBox(width: 60, child: Text('Color', style: st))),
      DataColumn(label: SizedBox(width: 60, child: Text('PH', style: st))),
      DataColumn(
        label: SizedBox(width: 60, child: Text('Densidad', style: st)),
      ),
      DataColumn(
        label: SizedBox(width: 60, child: Text('Observa.', style: st)),
      ),
      DataColumn(label: SizedBox(width: 60, child: Text('Asegura', style: st))),
      DataColumn(
        label: SizedBox(width: 60, child: Text('Autoriza', style: st)),
      ),
    ];
  }

  List<DataCell> _crearCeldas(dynamic item) {
    TextStyle cellStyle = const TextStyle(
      fontSize: 12,
      color: Colors.black87,
      letterSpacing: 0.3,
    );
    return [
      DataCell(
        SizedBox(
          width: 45,
          child: Text(item['semana']?.toString() ?? '', style: cellStyle),
        ),
      ),
      DataCell(
        SizedBox(
          width: 85,
          child: Text(item['fecha']?.toString() ?? '', style: cellStyle),
        ),
      ),
      DataCell(
        SizedBox(
          width: 140,
          child: Text(
            item['nombre_producto']?.toString().toUpperCase() ?? '',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              color: brandBlue,
            ),
          ),
        ),
      ),
      DataCell(
        SizedBox(
          width: 110,
          child: Text(
            item['proveedor']?.toString().toUpperCase() ?? '',
            style: cellStyle,
          ),
        ),
      ),
      DataCell(
        SizedBox(
          width: 75,
          child: Text(item['formula_c']?.toString() ?? '', style: cellStyle),
        ),
      ),
      DataCell(
        SizedBox(
          width: 75,
          child: Text(item['cat_toxic']?.toString() ?? '', style: cellStyle),
        ),
      ),
      DataCell(
        SizedBox(
          width: 100,
          child: Text(item['presentacion']?.toString() ?? '', style: cellStyle),
        ),
      ),
      DataCell(
        SizedBox(
          width: 50,
          child: Text(
            item['total_unidades']?.toString() ?? '',
            style: cellStyle,
          ),
        ),
      ),
      DataCell(
        SizedBox(
          width: 90,
          child: Text(item['lote']?.toString() ?? '', style: cellStyle),
        ),
      ),
      DataCell(
        SizedBox(
          width: 85,
          child: Text(
            item['fecha_vencimiento']?.toString() ?? '',
            style: cellStyle,
          ),
        ),
      ),
      DataCell(
        SizedBox(
          width: 75,
          child: Center(child: _buildIconoEstado(item['estado_etiqueta'])),
        ),
      ),
      DataCell(
        SizedBox(
          width: 75,
          child: Center(child: _buildIconoEstado(item['estado_tapa'])),
        ),
      ),
      DataCell(
        SizedBox(
          width: 75,
          child: Center(child: _buildIconoEstado(item['sellos'])),
        ),
      ),
      DataCell(
        SizedBox(
          width: 85,
          child: Center(child: _buildIconoEstado(item['puntos_extraccion'])),
        ),
      ),
      DataCell(
        SizedBox(
          width: 60,
          child: Text(
            item['cantidad_cc_g']?.toString() ?? '',
            style: cellStyle,
          ),
        ),
      ),
      DataCell(
        SizedBox(
          width: 60,
          child: Text(item['color']?.toString() ?? '', style: cellStyle),
        ),
      ),
      DataCell(
        SizedBox(
          width: 60,
          child: Text(item['ph']?.toString() ?? '', style: cellStyle),
        ),
      ),
      DataCell(
        SizedBox(
          width: 60,
          child: Text(item['densidad']?.toString() ?? '', style: cellStyle),
        ),
      ),
      DataCell(
        SizedBox(
          width: 60,
          child: Text(
            item['observaciones']?.toString() ?? '',
            style: cellStyle,
          ),
        ),
      ),
      DataCell(
        SizedBox(
          width: 60,
          child: Text(
            item['identificacion_asegura']?.toString() ?? '',
            style: cellStyle,
          ),
        ),
      ),
      DataCell(
        SizedBox(
          width: 60,
          child: Text(item['autorizacion']?.toString() ?? '', style: cellStyle),
        ),
      ),
    ];
  }

  Widget _buildControlesPaginacion() {
    int totalPaginas = (_registrosFiltrados.length / _filasPorPagina).ceil();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: brandBlue,
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(10),
            ),
            onPressed:
                _paginaActual > 0
                    ? () => setState(() => _paginaActual--)
                    : null,
            child: const Icon(Icons.chevron_left),
          ),
          const SizedBox(width: 20),
          Text(
            "Página ${_paginaActual + 1} de $totalPaginas",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey,
            ),
          ),
          const SizedBox(width: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: brandBlue,
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(10),
            ),
            onPressed:
                (_paginaActual + 1) < totalPaginas
                    ? () => setState(() => _paginaActual++)
                    : null,
            child: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Widget _buildSinInformacion() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 15),
          const Text(
            "No se encontraron registros",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => _filtrarPorPeriodo(null, null, null),
            child: const Text(
              "Limpiar filtros",
              style: TextStyle(color: brandBlue),
            ),
          ),
        ],
      ),
    );
  }
}

/// Donut painter reutilizable (sin dependencias externas)
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

    final basePaint =
        Paint()
          ..color = color.withOpacity(0.12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round;

    final progressPaint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, basePaint);

    final startAngle = -3.1415926535897932 / 2;
    final sweepAngle = 2 * 3.1415926535897932 * progress.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
