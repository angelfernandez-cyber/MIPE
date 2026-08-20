// lib/historial_aseguramiento_page.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'login_controller.dart';
import 'formulario_almacen_page.dart';
import 'aseguramiento_excel_service.dart';
import 'dart:math';

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

  DateTime? _fechaSeleccionada;
  bool _isLoading = true;

  // Controladores para sincronizar el scroll horizontal
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _headerHorizontalController = ScrollController();

  // progreso exportación
  double _exportProgress = 0.0;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _fetchDatos();

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
    super.dispose();
  }

  Future<void> _fetchDatos() async {
    setState(() => _isLoading = true);
    try {
      final url = Uri.parse(
        '${loginController.supabaseUrl}/rest/v1/aseguramiento_plaguicidas?select=*&order=fecha.desc',
      );
      final response = await http.get(
        url,
        headers: {
          'apikey': loginController.apiKey,
          'Authorization': 'Bearer ${loginController.apiKey}',
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          _todosLosRegistros = json.decode(response.body);
          _registrosFiltrados = _todosLosRegistros;
          _isLoading = false;
          _paginaActual = 0;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      Get.snackbar("Error", "No se pudo conectar con el servidor");
    }
  }

  void _filtrarPorFecha(DateTime? fecha) {
    setState(() {
      _fechaSeleccionada = fecha;
      _paginaActual = 0;
      if (fecha == null) {
        _registrosFiltrados = _todosLosRegistros;
      } else {
        String formato =
            "${fecha.year}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}";
        _registrosFiltrados = _todosLosRegistros
            .where((r) => r['fecha'].toString().startsWith(formato))
            .toList();
      }
    });
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
  // Exportación con modal
  // -------------------------
  void _exportarExcelConModal() {
    if (_registrosFiltrados.isEmpty) {
      Get.snackbar('Error', 'No hay datos para exportar');
      return;
    }

    final registrosParaExportar = _registrosFiltrados
        .map((e) => e is Map ? Map<String, dynamic>.from(e) : e)
        .toList();

    setState(() {
      _isExporting = true;
      _exportProgress = 0.0;
    });

    final ValueNotifier<double> progressNotifier = ValueNotifier<double>(0.0);

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
                ValueListenableBuilder<double>(
                  valueListenable: progressNotifier,
                  builder: (context, value, _) {
                    final percent = (value * 100).clamp(0.0, 100.0);
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ExportProgressDonut(
                          progress: value,
                          size: 110,
                          primaryColor: brandBlue,
                          backgroundColor: const Color(0xFFE9F3F8),
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
                return const SizedBox.shrink();
              },
            ),
          ],
        );
      },
    );

    Future.microtask(() async {
      await Future.delayed(const Duration(milliseconds: 50));

      try {
        final outPath = await AseguramientoExcelService.generarReporte(
          registrosParaExportar,
          nombreArchivo: 'Aseguramiento',
          onProgress: (p) {
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

        await Future.delayed(const Duration(milliseconds: 200));

        try {
          if (Navigator.of(context, rootNavigator: true).canPop()) {
            Navigator.of(context, rootNavigator: true).pop();
          }
        } catch (_) {}

        progressNotifier.dispose();

        Get.snackbar('Exportado', 'Archivo generado: $outPath',
            snackPosition: SnackPosition.BOTTOM);
      } catch (e) {
        if (mounted) {
          setState(() {
            _isExporting = false;
            _exportProgress = 0.0;
          });
        }

        try {
          if (Navigator.of(context, rootNavigator: true).canPop()) {
            Navigator.of(context, rootNavigator: true).pop();
          }
        } catch (_) {}

        try {
          progressNotifier.dispose();
        } catch (_) {}

        Get.snackbar('Error', 'Fallo al exportar: ${e.toString()}',
            snackPosition: SnackPosition.BOTTOM);
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
              colors: [
                Color(0xFF008DC5),
                Color(0xFF005F86),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(28),
            ),
          ),
        ),

        title: Row(
          children: [
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
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: IconButton(
              icon: const Icon(
                Icons.add_rounded,
                color: Colors.white,
              ),
              onPressed: () => Get.to(
                () => const AseguramientoPage(),
              )?.then((value) => _fetchDatos()),
              tooltip: "Nuevo Registro",
            ),
          ),
          if (_registrosFiltrados.isNotEmpty)
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

      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: brandBlue,
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(15, 12, 15, 0),
                  child: _buildFiltroYBanner(),
                ),
                Expanded(
                  child: _registrosFiltrados.isEmpty
                      ? _buildSinInformacion()
                      : Column(
                          children: [
                            Expanded(
                              child: _buildTablaEstructuraFija(),
                            ),
                            if (_registrosFiltrados.length > _filasPorPagina)
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
                _fechaSeleccionada == null
                    ? "Todos los registros"
                    : "Filtrado: ${_fechaSeleccionada.toString().split(' ')[0]}",
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
            backgroundColor: _fechaSeleccionada == null
                ? Colors.white
                : brandBlue.withOpacity(0.1),
            side: const BorderSide(color: brandBlue, width: 1),
            avatar: Icon(
              _fechaSeleccionada == null
                  ? Icons.calendar_month
                  : Icons.filter_alt_off,
              size: 18,
              color: brandBlue,
            ),
            label: Text(
              _fechaSeleccionada == null ? "Filtrar Fecha" : "Limpiar",
              style: const TextStyle(
                color: brandBlue,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: () async {
              if (_fechaSeleccionada != null) {
                _filtrarPorFecha(null);
              } else {
                DateTime? picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2023),
                  lastDate: DateTime(2030),
                  builder: (context, child) => Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.light(primary: brandBlue),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null) _filtrarPorFecha(picked);
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
                      columns: _crearColumnas()
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
                          color: MaterialStateProperty.resolveWith<Color?>(
                            (states) {
                              if (states.contains(MaterialState.hovered)) {
                                return brandBlue.withOpacity(0.12);
                              }
                              return index.isEven
                                  ? Colors.white
                                  : const Color(0xFFF7FAFC);
                            },
                          ),
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
    return [
      DataColumn(
        label: SizedBox(width: 45, child: Text('Sem.', style: st)),
      ),
      DataColumn(
        label: SizedBox(width: 85, child: Text('Fecha', style: st)),
      ),
      DataColumn(
        label: SizedBox(width: 140, child: Text('Producto', style: st)),
      ),
      DataColumn(
        label: SizedBox(width: 110, child: Text('Proveedor', style: st)),
      ),
      DataColumn(
        label: SizedBox(
          width: 90,
          child: Text('Present.\n(Cantidad)', style: st),
        ),
      ),
      DataColumn(
        label: SizedBox(width: 50, child: Text('Cant.', style: st)),
      ),
      DataColumn(
        label: SizedBox(width: 90, child: Text('Lote', style: st)),
      ),
      DataColumn(
        label: SizedBox(width: 85, child: Text('Vence', style: st)),
      ),
      DataColumn(
        label: SizedBox(width: 75, child: Text('Etiqueta', style: st)),
      ),
      DataColumn(
        label: SizedBox(width: 75, child: Text('Tapa', style: st)),
      ),
      DataColumn(
        label: SizedBox(width: 75, child: Text('Sellos', style: st)),
      ),
      DataColumn(
        label: SizedBox(width: 85, child: Text('Extrac.', style: st)),
      ),
      DataColumn(
        label: SizedBox(width: 60, child: Text('cc/g', style: st)),
      ),
      DataColumn(
        label: SizedBox(width: 60, child: Text('Color', style: st)),
      ),
      DataColumn(
        label: SizedBox(width: 60, child: Text('PH', style: st)),
      ),
      DataColumn(
        label: SizedBox(width: 60, child: Text('Densidad', style: st)),
      ),
      DataColumn(
        label: SizedBox(width: 60, child: Text('Observa.', style: st)),
      ),
      DataColumn(
        label: SizedBox(width: 60, child: Text('Asegura', style: st)),
      ),
      DataColumn(
        label: SizedBox(width: 60, child: Text('Autoriza', style: st)),
      ),
    ];
  }

  List<DataCell> _crearCeldas(dynamic item) {
    TextStyle cellStyle = const TextStyle(fontSize: 12, color: Colors.black87, letterSpacing: 0.3);
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
          child: Text(
            item['autorizacion']?.toString() ?? '',
            style: cellStyle,
          ),
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
            onPressed: _paginaActual > 0
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
            onPressed: (_paginaActual + 1) < totalPaginas
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
            onPressed: () => _filtrarPorFecha(null),
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

// ---------- Widgets de progreso (añadidos) ----------

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
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle,
        sweepAngle, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}