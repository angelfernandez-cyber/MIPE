import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'login_controller.dart';
import 'historial_bloque_page.dart';

class ConsultarPage extends StatefulWidget {
  const ConsultarPage({super.key});

  @override
  State<ConsultarPage> createState() => _ConsultarPageState();
}

class _ConsultarPageState extends State<ConsultarPage> {
  final LoginController loginController = Get.find<LoginController>();

  List<String> bloquesPermitidos = [];
  bool esAdmin = false;

  @override
  void initState() {
    super.initState();
    _cargarPermisos();
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
        bloquesPermitidos = permisosRaw
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
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
    ),

    body: Column(
      children: [
        // TEXTO INFORMATIVO
        Container(
          margin: const EdgeInsets.fromLTRB(18, 18, 18, 10),
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
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
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 10,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 1,
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
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: tieneAcceso
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
          gradient: tieneAcceso
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colorLight, colorDark],
                )
              : null,
          color: tieneAcceso ? null : Colors.grey[300],
          boxShadow: tieneAcceso
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
          children: [
            Positioned(
              right: -2,
              bottom: -2,
              child: Icon(
                Icons.manage_search_rounded,
                size: 35,
                color: tieneAcceso
                    ? Colors.white.withOpacity(0.2)
                    : Colors.black26,
              ),
            ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "BLOQUE",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Text(
                    '$numero',
                    style: TextStyle(
                      color: tieneAcceso ? Colors.white : Colors.black45,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
