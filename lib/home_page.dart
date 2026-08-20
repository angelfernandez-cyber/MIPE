import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_barcode_scanner/simple_barcode_scanner.dart';
import 'login_controller.dart';
import 'formulario_page.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Color brandBlue = const Color(0xFF008DC5);
  final Color brandGreen = const Color(0xFF1DB954);
  final Color darkBlue = const Color(0xFF005F86);

  final LoginController loginController = Get.find<LoginController>();

  Future<void> _scanBarcode() async {
    var res = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SimpleBarcodeScannerPage()),
    );

    if (res != null && res != "-1") {
      String codigoLimpio = res.toString().trim();
      int? numeroBloque = int.tryParse(codigoLimpio);

      if (numeroBloque == null || numeroBloque < 401 || numeroBloque > 445) {
        Get.snackbar(
          "BLOQUE NO REGISTRADO",
          "El código '$codigoLimpio' no pertenece al rango permitido (401-445).",
          backgroundColor: Colors.redAccent,
          colorText: Colors.white,
        );
        return;
      }

      _procesarEntradaBloque(codigoLimpio);
    }
  }

  Set<String> _obtenerModulos() {
    String lectura = loginController.loggedInUser.value?['lectura'] ?? '';

    if (lectura.trim().isEmpty) {
      return {};
    }

    return lectura.split(',').map((e) => e.trim().toLowerCase()).toSet();
  }

  Future<void> _procesarEntradaBloque(String bloque) async {
    Get.dialog(
      const Center(child: CircularProgressIndicator()),
      barrierDismissible: false,
    );

    try {
      final url = Uri.parse(
        '${loginController.supabaseUrl}/rest/v1/aspersiones?bloque=eq.$bloque&select=*&order=id.desc&limit=1',
      );

      final response = await http.get(
        url,
        headers: {
          'apikey': loginController.apiKey,
          'Authorization': 'Bearer ${loginController.apiKey}',
        },
      );

      Get.back();

      if (response.statusCode == 200) {
        List<dynamic> datos = json.decode(response.body);

        if (datos.isNotEmpty) {
          Get.to(
            () => const FormularioPage(),
            arguments: {
              ...Map<String, dynamic>.from(datos[0]),
              'esLecturaForzada': true,
            },
          );
        } else {
          Get.to(() => const FormularioPage(), arguments: {'bloque': bloque});
        }
      } else {
        Get.snackbar("Error", "No se pudo consultar el bloque");
      }
    } catch (e) {
      Get.back();
      Get.snackbar("Error", "Verifica tu conexión");
    }
  }

  @override
  Widget build(BuildContext context) {
    final lectura = _obtenerModulos();
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: RefreshIndicator(
        color: brandBlue,

        onRefresh: () async {
          // 🔥 PEQUEÑA RECARGA VISUAL
          setState(() {});

          // Opcional:
          await Future.delayed(const Duration(milliseconds: 700));
        },

        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 150.0,
              pinned: true,
              backgroundColor: darkBlue,
              elevation: 0,
              title: const Text(
                "LA PLANICIE",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                  color: Colors.white70,
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [brandBlue, darkBlue]),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(50),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: darkBlue.withOpacity(0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: -40,
                        left: -40,
                        child: CircleAvatar(
                          radius: 80,
                          backgroundColor: Colors.white.withOpacity(0.05),
                        ),
                      ),
                      Positioned(
                        bottom: 20,
                        right: -30,
                        child: CircleAvatar(
                          radius: 60,
                          backgroundColor: Colors.white.withOpacity(0.05),
                        ),
                      ),
                      _buildUserInfoContent(),
                    ],
                  ),
                ),
              ),
              actions: [
                Container(
                  margin: const EdgeInsets.only(right: 15),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.info_outline, color: Colors.white),
                    onPressed: () => _showDevDialog(context),
                  ),
                ),
              ],
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
                child: Column(
                  children: [
                    if (lectura.contains("scanner"))
                      _buildActionCard(
                        title: "ESCÁNER QR",
                        subtitle: "búsqueda rápida por bloque",
                        icon: Icons.qr_code_scanner_rounded,
                        gradient: [brandBlue, darkBlue],
                        onTap: _scanBarcode,
                      ),
                    const SizedBox(height: 20),
                    if (lectura.contains("mapa"))
                      _buildActionCard(
                        title: "MAPA DE BLOQUES",
                        subtitle: "Control De Aspersion",
                        icon: Icons.map_rounded,
                        gradient: [brandGreen, const Color(0xFF158A3E)],
                        onTap: () => Get.toNamed('/consultaexcel'),
                      ),
                    const SizedBox(height: 20),
                    if (lectura.contains("almacen"))
                      _buildActionCard(
                        title: "ALMACEN",
                        subtitle: "Control De Entrada De Plaguicidas",
                        icon: Icons.storage_rounded,
                        gradient: [
                          const Color(0xFF38158A),
                          const Color(0xFF38158A),
                        ],
                        onTap: () => Get.toNamed('/historialaseguramiento'),
                      ),
                    if (loginController.loggedInUser.value?['admin'] ==
                        'S') ...[
                      const SizedBox(height: 20),
                      _buildActionCard(
                        title: "ADMINISTRACIÓN",
                        subtitle: "Panel de control de personal",
                        icon: Icons.admin_panel_settings_rounded,
                        gradient: [
                          const Color(0xFF455A64),
                          const Color(0xFF263238),
                        ],
                        onTap: () => Get.toNamed('/gestusu'),
                      ),
                    ],
                    const SizedBox(height: 50),
                    _buildLogoutButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserInfoContent() {
    String nombre =
        loginController.loggedInUser.value?['nombres'] ?? "Operario";

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(),
            const Text(
              "Panel de Control MIPE",
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            Text(
              "HOLA, ${nombre.split(' ')[0].toUpperCase()}",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 10),
              height: 2,
              width: 40,
              color: Colors.white30,
            ),
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: brandGreen,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                "SESIÓN ACTIVA",
                style: TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 130,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: gradient[1].withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: Colors.white24,
          highlightColor: Colors.white10,
          borderRadius: BorderRadius.circular(30),
          child: Padding(
            padding: const EdgeInsets.all(25),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon, color: Colors.white, size: 30),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.white54),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return InkWell(
      onTap: () {
        Get.dialog(
          Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),

            child: Container(
              padding: const EdgeInsets.all(22),

              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),

              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 🔥 ICONO
                  Container(
                    padding: const EdgeInsets.all(16),

                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.10),
                      shape: BoxShape.circle,
                    ),

                    child: const Icon(
                      Icons.logout_rounded,
                      color: Colors.redAccent,
                      size: 42,
                    ),
                  ),

                  const SizedBox(height: 18),

                  // 🔥 TITULO
                  const Text(
                    "Cerrar sesión",
                    style: TextStyle(
                      color: Color(0xFF1E293B),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // 🔥 MENSAJE
                  Text(
                    "¿Seguro que deseas salir del sistema?",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: 25),

                  // 🔥 BOTONES
                  Row(
                    children: [
                      // CANCELAR
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey[700],
                            side: BorderSide(color: Colors.grey.shade300),

                            padding: const EdgeInsets.symmetric(vertical: 14),

                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),

                          onPressed: () => Get.back(),

                          child: const Text(
                            "Cancelar",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // SALIR
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            elevation: 0,

                            padding: const EdgeInsets.symmetric(vertical: 14),

                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),

                          onPressed: () {
                            Get.back();
                            loginController.logout();
                          },

                          child: const Text(
                            "Salir",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },

      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12),

        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
          ),

          borderRadius: BorderRadius.circular(20),

          boxShadow: [
            BoxShadow(color: Colors.red.withOpacity(0.25), blurRadius: 10),
          ],
        ),

        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.logout_rounded, color: Colors.white),

            SizedBox(width: 10),

            Text(
              "SALIR",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDevDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            gradient: const LinearGradient(
              colors: [Color(0xFF008DC5), Color(0xFF005F86)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),

          child: Stack(
            children: [
              // 🌸 CLAVEL SUPERIOR
              Positioned(
                top: -15,
                right: -10,
                child: Opacity(
                  opacity: 0.14,
                  child: Transform.rotate(
                    angle: 0.3,
                    child: const Icon(
                      Icons.local_florist_rounded,
                      size: 95,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              // 🌸 CLAVEL INFERIOR
              Positioned(
                bottom: -18,
                left: -10,
                child: Opacity(
                  opacity: 0.10,
                  child: Transform.rotate(
                    angle: -0.4,
                    child: const Icon(
                      Icons.local_florist_rounded,
                      size: 85,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ICONO
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.code_rounded,
                      color: Colors.white,
                      size: 45,
                    ),
                  ),

                  const SizedBox(height: 18),

                  // TITULO
                  const Text(
                    "DESARROLLADOR",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // NOMBRE
                  const Text(
                    "ANGEL FERNANDEZ",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),

                  const SizedBox(height: 6),

                  // CARGO
                  const Text(
                    "PASANTE DE SISTEMAS",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // TELEFONO
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      await Clipboard.setData(
                        const ClipboardData(text: '3028329414'),
                      );

                      Get.snackbar(
                        "Copiado",
                        "Número copiado al portapapeles",
                        backgroundColor: Colors.green,
                        colorText: Colors.white,
                        snackPosition: SnackPosition.BOTTOM,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        children: const [
                          Icon(FontAwesomeIcons.whatsapp, color: Colors.white),

                          SizedBox(width: 12),

                          Expanded(
                            child: Text(
                              "WhatsApp: 302 8329414",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),

                          Icon(Icons.copy, color: Colors.white70, size: 18),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // CORREO
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      await Clipboard.setData(
                        const ClipboardData(
                          text: 'angel.manuel.fernandez2005@gmail.com',
                        ),
                      );

                      Get.snackbar(
                        "Copiado",
                        "Correo copiado al portapapeles",
                        backgroundColor: Colors.green,
                        colorText: Colors.white,
                        snackPosition: SnackPosition.BOTTOM,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        children: const [
                          Icon(FontAwesomeIcons.envelope, color: Colors.white),

                          SizedBox(width: 12),

                          Expanded(
                            child: Text(
                              "angel.manuel.fernandez2005@gmail.com",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),

                          Icon(Icons.copy, color: Colors.white70, size: 18),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  // BOTON
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF008DC5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Get.back(),
                      child: const Text(
                        "CERRAR",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
