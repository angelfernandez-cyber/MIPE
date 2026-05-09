import 'package:flutter/material.dart';
import 'package:flutter_application_1/formulario_page.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'login_controller.dart';
import 'package:intl/intl.dart';

class HistorialBloquePage extends StatefulWidget {
  final String bloque;

  const HistorialBloquePage({super.key, required this.bloque});

  @override
  State<HistorialBloquePage> createState() => _HistorialBloquePageState();
}

class _HistorialBloquePageState extends State<HistorialBloquePage> {
  static const Color brandBlue = Color(0xFF008DC5);
  late Future<List<dynamic>> futureRegistros;
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
          // 🔥 HEADER MÁS LIMPIO
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
                // BOTÓN ATRÁS
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

                // TITULO
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

          // CONTENIDO
          Expanded(
            child: RefreshIndicator(
              color: brandBlue,

              onRefresh: () async {
                setState(() {
                  futureRegistros = fetchRegistrosPorBloque();
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

                  // --- AGRUPACIÓN ---
                  Map<String, List<dynamic>> registrosAgrupados = {};

                  for (var reg in snapshot.data!) {
                    DateTime fechaReg =
                        DateTime.tryParse(
                          reg['fecha_registro'] ?? '',
                        )?.toLocal() ??
                        DateTime.now();

                    int diasRestar = fechaReg.weekday - 1;

                    DateTime lunes = DateTime(
                      fechaReg.year,
                      fechaReg.month,
                      fechaReg.day,
                    ).subtract(Duration(days: diasRestar));

                    DateTime domingo = lunes.add(const Duration(days: 6));

                    String tag;

                    DateTime ahora = DateTime.now();

                    DateTime inicioSemanaActual = ahora.subtract(
                      Duration(days: ahora.weekday - 1),
                    );

                    inicioSemanaActual = DateTime(
                      inicioSemanaActual.year,
                      inicioSemanaActual.month,
                      inicioSemanaActual.day,
                    );

                    if (lunes.isAtSameMomentAs(inicioSemanaActual)) {
                      tag = "ESTA SEMANA";
                    } else {
                      tag =
                          "SEMANA DEL ${DateFormat('d MMMM', 'es').format(lunes)} AL ${DateFormat('d MMMM', 'es').format(domingo)}";
                    }

                    if (!registrosAgrupados.containsKey(tag)) {
                      registrosAgrupados[tag] = [];
                    }

                    registrosAgrupados[tag]!.add(reg);
                  }

                  List<String> secciones = registrosAgrupados.keys.toList();

                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: secciones.length,
                    itemBuilder: (context, index) {
                      String tituloSeccion = secciones[index];

                      List<dynamic> items = registrosAgrupados[tituloSeccion]!;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(
                              top: 10,
                              bottom: 12,
                              left: 8,
                            ),

                            child: Text(
                              tituloSeccion.toUpperCase(),
                              style: TextStyle(
                                color: tituloSeccion == "ESTA SEMANA"
                                    ? brandBlue
                                    : Colors.blueGrey[400],

                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),

                          ...items.map((item) => _buildItemCard(item)).toList(),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(dynamic reg) {
    DateTime fecha = DateTime.parse(reg['fecha_registro']).toLocal();
    String hora = DateFormat('hh:mm a').format(fecha);
    String fechaCorta = DateFormat("d 'de' MMMM, y", 'es').format(fecha);

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
                        reg['producto'] ?? 'Sin producto',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF2D3142),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Operario: ${reg['usuario_registro']}",
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      // --- FECHA DEBAJO DEL OPERARIO ---
                      Text(
                        fechaCorta,
                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                      ),
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
