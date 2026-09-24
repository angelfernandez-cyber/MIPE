import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'excel_service.dart';
import 'login_controller.dart';
import 'historial_bloque_page.dart';
import 'offline_sync_service.dart';

class ConsultarPage extends StatefulWidget {
  const ConsultarPage({super.key});

  @override
  State<ConsultarPage> createState() => _ConsultarPageState();
}

class _ConsultarPageState extends State<ConsultarPage> {
  final LoginController loginController = Get.find<LoginController>();

  List<String> bloquesPermitidos = [];
  bool esAdmin = false;
  bool _isExporting = false;
  double _exportProgress = 0;
  final Set<int> _bloquesAsperjados = {};
  bool _cargandoAspersiones = false;

  bool get puedeVerAspersiones =>
      esAdmin ||
      (loginController.loggedInUser.value?['lectura']
              ?.toString()
              .toLowerCase()
              .split(',')
              .map((e) => e.trim())
              .contains('ver_aspersiones') ??
          false);

  bool get puedeExportarExcel =>
      esAdmin ||
      (loginController.loggedInUser.value?['lectura']
              ?.toString()
              .toLowerCase()
              .split(',')
              .map((e) => e.trim())
              .contains('exportar_excel') ??
          false);

  @override
  void initState() {
    super.initState();
    _cargarPermisos();
    if (puedeVerAspersiones) _cargarBloquesAsperjados();
  }

  Future<void> _cargarBloquesAsperjados() async {
    setState(() => _cargandoAspersiones = true);
    try {
      final ahora = DateTime.now();
      final inicioLocal = DateTime(ahora.year, ahora.month, ahora.day);
      final inicioUtc = inicioLocal.toUtc().toIso8601String();
      final finUtc = inicioLocal.add(const Duration(days: 1)).toUtc().toIso8601String();
      final claveFecha =
          '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}-${ahora.day.toString().padLeft(2, '0')}';
      final url = Uri.parse(
        '${loginController.supabaseUrl}/rest/v1/aspersiones?select=bloque&fecha_registro=gte.$inicioUtc&fecha_registro=lt.$finUtc',
      );
      final response = await OfflineSyncService.fetchListWithCache(
        cacheKey: 'cache_bloques_asperjados_mapa_$claveFecha',
        url: url,
        headers: {
          'apikey': loginController.apiKey,
          'Authorization': 'Bearer ${loginController.apiKey}',
        },
      );
      if (!mounted) return;
      setState(() {
        _bloquesAsperjados
          ..clear()
          ..addAll(
            response
                .map((r) => int.tryParse('${r['bloque']}'))
                .whereType<int>(),
          );
      });
    } catch (_) {
      // El mapa de accesos sigue disponible aunque no se pueda cargar el estado.
    } finally {
      if (mounted) setState(() => _cargandoAspersiones = false);
    }
  }

  void _cargarPermisos() {
    final user = loginController.loggedInUser.value;

    if (user != null) {
      esAdmin = user['admin']?.toString().trim() == 'S';

      String permisosRaw = user['lectura']?.toString().trim() ?? "";

      if (permisosRaw.isEmpty || permisosRaw == 'N') {
        bloquesPermitidos = [];
      } else if (permisosRaw == 'S') {
        bloquesPermitidos = List.generate(45, (i) => (401 + i).toString());
      } else {
        bloquesPermitidos =
            permisosRaw
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
      }
    }
  }

  Future<void> _exportarMapa() async {
    if (!puedeExportarExcel) {
      Get.snackbar('Sin permiso', 'No tienes permiso para exportar a Excel.');
      return;
    }
    if (_isExporting) return;

    setState(() {
      _isExporting = true;
      _exportProgress = 0;
    });

    try {
      final bloques =
          esAdmin
              ? List.generate(45, (index) => 401 + index)
              : bloquesPermitidos
                  .map(int.tryParse)
                  .whereType<int>()
                  .where((bloque) => bloque >= 401 && bloque <= 445)
                  .toList();

      if (bloques.isEmpty) {
        throw Exception('No tienes bloques autorizados para exportar.');
      }

      final bloquesQuery = bloques.join(',');
      final url = Uri.parse(
        '${loginController.supabaseUrl}/rest/v1/aspersiones?bloque=in.($bloquesQuery)&select=*&order=fecha_registro.desc',
      );
      final registros = await OfflineSyncService.fetchListWithCache(
        cacheKey: 'cache_aspersiones_mapa_${bloques.join('_')}',
        url: url,
        headers: {
          'apikey': loginController.apiKey,
          'Authorization': 'Bearer ${loginController.apiKey}',
        },
      );

      if (registros.isEmpty) {
        throw Exception(
          'No hay registros para exportar en los bloques autorizados.',
        );
      }

      final outPath = await MIPEExcelService.generarReporteMIPE(
        registros,
        nombreArchivo: 'Mapa_de_bloques',
        onProgress: (progress) {
          if (mounted) {
            setState(() => _exportProgress = progress.clamp(0.0, 1.0));
          }
        },
        abrirArchivoAlFinal: true,
      );

      if (mounted) {
        Get.snackbar(
          'Exportado',
          'Archivo generado: $outPath',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (e) {
      if (mounted) {
        Get.snackbar('Error', e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _exportProgress = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color brandBlue = Color(0xFF008DC5);
    const Color brandBlueLight = Color(0xFF4FC3F7);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),

      appBar: AppBar(
        toolbarHeight: 78,
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
                onPressed: () => Get.back(),
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 18,
                ),
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
                    "Panel de",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    "CONSULTA",
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
          if (puedeExportarExcel)
            IconButton(
              onPressed: _isExporting ? null : _exportarMapa,
              tooltip: 'Exportar mapa a Excel',
              icon:
                  _isExporting
                      ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          value: _exportProgress == 0 ? null : _exportProgress,
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                      : const Icon(Icons.download_rounded, color: Colors.white),
            ),
        ],
      ),

      body: Column(
        children: [
          // TEXTO INFORMATIVO
          Container(
            margin: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: brandBlue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.grid_view_rounded,
                    color: brandBlue,
                    size: 22,
                  ),
                ),

                const SizedBox(width: 14),

                const Expanded(
                  child: Text(
                    "Selecciona un bloque para consultar el historial de aspersiones.",
                    style: TextStyle(
                      color: Color(0xFF2D3142),
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // GRID
          Expanded(
            child: LayoutBuilder(
              builder: (context, _) {
                return GridView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 125,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.18,
                  ),
                  itemCount: 45,
                  itemBuilder: (context, index) {
                    int numeroBloque = 401 + index;
                    String bloqueStr = numeroBloque.toString();

                    bool tieneAcceso =
                        esAdmin || bloquesPermitidos.contains(bloqueStr);

                    return _buildBloqueConsulta(
                      numeroBloque,
                      brandBlueLight,
                      brandBlue,
                      tieneAcceso,
                      puedeVerAspersiones &&
                          _bloquesAsperjados.contains(numeroBloque),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBloqueConsulta(
    int numero,
    Color colorLight,
    Color colorDark,
    bool tieneAcceso,
    bool asperjado,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap:
          tieneAcceso
              ? () {
                String bloqueId = numero.toString().trim();
                Get.to(
                  () => HistorialBloquePage(bloque: bloqueId),
                  preventDuplicates: false,
                );
              }
              : null,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient:
              asperjado
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF43B66B), Color(0xFF168345)],
                    )
                  : tieneAcceso
                  ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [colorLight, colorDark],
                  )
                  : null,
          color: (tieneAcceso || asperjado) ? null : Colors.grey[300],
          boxShadow:
              tieneAcceso
                  ? [
                    BoxShadow(
                      color: colorDark.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                  : [],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              '$numero',
              style: TextStyle(
              color: (tieneAcceso || asperjado) ? Colors.white : Colors.black45,
                fontSize: 25,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
