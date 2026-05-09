import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'login_controller.dart';
import 'gestusu_controller.dart';

class GestionUsuariosPage extends StatefulWidget {
  const GestionUsuariosPage({super.key});

  @override
  State<GestionUsuariosPage> createState() => _GestionUsuariosPageState();
}

class _GestionUsuariosPageState extends State<GestionUsuariosPage> {
  final LoginController loginController = Get.find<LoginController>();
  final GestUsuController gestUsuCtrl = Get.put(GestUsuController());

  List<dynamic> usuarios = [];
  bool isLoading = true;

  final Color brandBlue = const Color(0xFF008DC5);
  final Color darkBlue = const Color(0xFF005F86);

  @override
  void initState() {
    super.initState();
    _fetchUsuarios();
  }

  Future<void> _fetchUsuarios() async {
    setState(() => isLoading = true);
    try {
      final url = Uri.parse(
        '${loginController.supabaseUrl}/rest/v1/persona?select=nombres,identificacion,password,lectura',
      );

      final response = await http.get(
        url,
        headers: {
          'apikey': loginController.apiKey,
          'Authorization': 'Bearer ${loginController.apiKey}',
        },
      );

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);

        // 🔥 OCULTAR EL USUARIO ADMIN ACTUAL
        data.removeWhere(
          (u) =>
              u['identificacion'].toString() ==
              loginController.loggedInUser.value?['identificacion'].toString(),
        );

        setState(() {
          usuarios = data;
        });
      }
    } catch (e) {
      Get.snackbar('Error', 'Error de conexión');
    } finally {
      setState(() => isLoading = false);
    }
  }

  // ─── Parsear la cadena "401,402,410" → Set<int> ───────────────────────────
  Set<int> _parsearBloques(String? lectura) {
    if (lectura == null || lectura.trim().isEmpty || lectura.trim() == 'N') {
      return {};
    }
    return lectura
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toSet();
  }

  void _mostrarDialogoModulos(Map<String, dynamic> user) {
    // Extraer módulos actuales (valores no numéricos del campo lectura)
    final todosLosModulos = ['scanner', 'mapa', 'almacen'];
    String lecturaActual = user['lectura']?.toString().trim() ?? '';

    Set<String> modulosActivos = lecturaActual
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => todosLosModulos.contains(e))
        .toSet();

    // Íconos y colores para cada módulo
    final moduloInfo = {
      'scanner': {
        'label': 'ESCÁNER QR',
        'subtitle': 'Registro rápido por bloque',
        'icon': Icons.qr_code_scanner_rounded,
        'color': brandBlue,
      },
      'mapa': {
        'label': 'MAPA DE BLOQUES',
        'subtitle': 'Control de aspersión',
        'icon': Icons.map_rounded,
        'color': const Color(0xFF1DB954),
      },
      'almacen': {
        'label': 'ALMACÉN',
        'subtitle': 'Control de plaguicidas',
        'icon': Icons.storage_rounded,
        'color': const Color(0xFF38158A),
      },
    };

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 40,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 25,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // HEADER
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.teal.shade400, Colors.teal.shade700],
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.dashboard_customize_rounded,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "MÓDULOS DE ACCESO",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  user['nombres']?.toString().toUpperCase() ??
                                      '',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // LISTA DE MÓDULOS
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: todosLosModulos.map((modulo) {
                          final info = moduloInfo[modulo]!;
                          final activo = modulosActivos.contains(modulo);
                          final color = info['color'] as Color;

                          return GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                if (activo) {
                                  modulosActivos.remove(modulo);
                                } else {
                                  modulosActivos.add(modulo);
                                }
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: activo
                                    ? color.withOpacity(0.08)
                                    : Colors.grey[100],
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: activo
                                      ? color.withOpacity(0.4)
                                      : Colors.grey.shade200,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: activo
                                          ? color.withOpacity(0.15)
                                          : Colors.grey[200],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      info['icon'] as IconData,
                                      color: activo ? color : Colors.grey,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          info['label'] as String,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                            color: activo
                                                ? color
                                                : Colors.grey[600],
                                          ),
                                        ),
                                        Text(
                                          info['subtitle'] as String,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: Icon(
                                      activo
                                          ? Icons.toggle_on_rounded
                                          : Icons.toggle_off_rounded,
                                      key: ValueKey(activo),
                                      color: activo ? color : Colors.grey[400],
                                      size: 36,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    // BOTONES
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text("Cancelar"),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                              ),
                              onPressed: () async {
                                // ✅ Leer lectura ACTUAL del objeto, no la variable capturada
                                final lecturaViva =
                                    user['lectura']?.toString().trim() ?? '';

                                final bloquesActuales = lecturaViva
                                    .split(',')
                                    .map((e) => e.trim())
                                    .where((e) => int.tryParse(e) != null)
                                    .toList();

                                final nuevaLectura = [
                                  ...modulosActivos,
                                  ...bloquesActuales,
                                ].join(',');

                                bool ok = await gestUsuCtrl.actualizarPermiso(
                                  user['identificacion'],
                                  'lectura',
                                  nuevaLectura.isEmpty ? 'N' : nuevaLectura,
                                );

                                if (ok) {
                                  // Actualizar el mapa en memoria
                                  user['lectura'] = nuevaLectura.isEmpty
                                      ? 'N'
                                      : nuevaLectura;
                                  setState(() {
                                    final index = usuarios.indexWhere(
                                      (u) =>
                                          u['identificacion'].toString() ==
                                          user['identificacion'].toString(),
                                    );
                                    if (index != -1) {
                                      usuarios[index]['lectura'] =
                                          user['lectura'];
                                    }
                                  });

                                  Navigator.of(ctx).pop();
                                  Get.snackbar(
                                    'Éxito',
                                    'Módulos actualizados',
                                    backgroundColor: Colors.teal,
                                    colorText: Colors.white,
                                  );
                                }
                              },
                              child: const Text("Guardar"),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ─── Serializar Set<int> → "401,402,410" ──────────────────────────────────


  // ─── Diálogo principal de permisos con grid de bloques ────────────────────
  void _mostrarDialogoBloques(Map<String, dynamic> user) {
    Set<int> seleccionados = _parsearBloques(user['lectura']?.toString());
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final todosSeleccionados = seleccionados.length == 45;

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 25,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 🔥 HEADER
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [brandBlue, darkBlue]),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.grid_on,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "PERMISOS DE BLOQUES",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  user['nombres']?.toString().toUpperCase() ??
                                      '',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 🔹 CONTROLES
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: brandBlue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Text(
                              "${seleccionados.length} / 45",
                              style: TextStyle(
                                color: brandBlue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setDialogState(() {
                                if (todosSeleccionados) {
                                  seleccionados.clear();
                                } else {
                                  seleccionados = Set.from(
                                    List.generate(45, (i) => 401 + i),
                                  );
                                }
                              });
                            },
                            child: Text(
                              todosSeleccionados
                                  ? "Limpiar"
                                  : "Seleccionar todo",
                              style: TextStyle(color: brandBlue),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 🔥 GRID
                    SizedBox(
                      height: 330,
                      child: GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: 45,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 5,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                        itemBuilder: (_, index) {
                          final bloque = 401 + index;
                          final activo = seleccionados.contains(bloque);

                          return GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                if (activo) {
                                  seleccionados.remove(bloque);
                                } else {
                                  seleccionados.add(bloque);
                                }
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                gradient: activo
                                    ? LinearGradient(
                                        colors: [brandBlue, darkBlue],
                                      )
                                    : null,
                                color: activo ? null : Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  '$bloque',
                                  style: TextStyle(
                                    color: activo
                                        ? Colors.white
                                        : Colors.black54,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // 🔥 BOTONES
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text("Cancelar"),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                              

                                // Preservar módulos al guardar bloques
                                final modulosExistentes =
                                    user['lectura']
                                        ?.toString()
                                        .split(',')
                                        .map((e) => e.trim().toLowerCase())
                                        .where(
                                          (e) => [
                                            'scanner',
                                            'mapa',
                                            'almacen',
                                          ].contains(e),
                                        )
                                        .toList() ??
                                    [];

                                final bloquesOrdenados = seleccionados.toList()
                                  ..sort();

                                final nuevaLectura = [
                                  ...modulosExistentes,
                                  ...bloquesOrdenados.map((e) => e.toString()),
                                ].join(',');

                                bool ok = await gestUsuCtrl.actualizarPermiso(
                                  user['identificacion'],
                                  'lectura',
                                  nuevaLectura.isEmpty ? 'N' : nuevaLectura,
                                );

                                if (ok) {
                                  // ✅ AGREGAR ESTA LÍNEA - actualizar el objeto user directamente
                                  user['lectura'] = nuevaLectura.isEmpty
                                      ? 'N'
                                      : nuevaLectura;

                                  setState(() {
                                    final index = usuarios.indexWhere(
                                      (u) =>
                                          u['identificacion'].toString() ==
                                          user['identificacion'].toString(),
                                    );
                                    if (index != -1) {
                                      usuarios[index]['lectura'] =
                                          user['lectura'];
                                    }
                                  });

                                  Navigator.of(ctx).pop();
                                  Get.snackbar(
                                    'Éxito',
                                    'Permisos actualizados',
                                    backgroundColor: Colors.green,
                                    colorText: Colors.white,
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: brandBlue,
                              ),
                              child: const Text("Guardar"),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

Widget _buildModernUserCard(Map<String, dynamic> user) {
  String nombre = user['nombres']?.toString().toUpperCase() ?? 'SIN NOMBRE';
  String inicial = nombre.isNotEmpty ? nombre[0] : '?';

  String lectura = user['lectura']?.toString().trim() ?? "";
  bool tieneAcceso = lectura.isNotEmpty && lectura != 'N';

  Set<int> bloques = _parsearBloques(lectura);

  final partesLectura = lectura.split(',').map((e) => e.trim()).toList();
  final modulos = ['scanner', 'mapa', 'almacen']
      .where((m) => partesLectura.contains(m))
      .length;

  return Container(
    margin: const EdgeInsets.only(bottom: 18),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(
        colors: [Colors.white, Color(0xFFF8FBFF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      boxShadow: [
        BoxShadow(
          color: brandBlue.withOpacity(0.08),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
      border: Border.all(color: brandBlue.withOpacity(0.08)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔥 AVATAR
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [brandBlue, brandBlue.withOpacity(0.75)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: brandBlue.withOpacity(0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                inicial,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
            ),
          ),

          const SizedBox(width: 15),

          // 🔥 INFORMACIÓN
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: Color(0xFF1F2937),
                    letterSpacing: 0.3,
                  ),
                ),

                const SizedBox(height: 4),

                Row(
                  children: [
                    Icon(Icons.badge_outlined, size: 15, color: Colors.grey[600]),
                    const SizedBox(width: 5),
                    Text(
                      user['identificacion'] ?? '',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // 🔥 DOS CHIPS COMPACTOS
                if (!tieneAcceso)
                  // Sin acceso
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.red.withOpacity(0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.block_rounded,
                            size: 12, color: Colors.redAccent),
                        SizedBox(width: 4),
                        Text(
                          "Sin acceso",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Row(
                    children: [
                      // CHIP BLOQUES
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: brandBlue.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: brandBlue.withOpacity(0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.grid_view_rounded,
                                size: 12, color: brandBlue),
                            const SizedBox(width: 4),
                            Text(
                              "${bloques.length} bloq.",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: brandBlue,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 6),

                      // CHIP MÓDULOS
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: modulos > 0
                              ? Colors.teal.withOpacity(0.10)
                              : Colors.orange.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: modulos > 0
                                ? Colors.teal.withOpacity(0.25)
                                : Colors.orange.withOpacity(0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.dashboard_customize_rounded,
                              size: 12,
                              color: modulos > 0
                                  ? Colors.teal
                                  : Colors.orange,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "$modulos mód.",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: modulos > 0
                                    ? Colors.teal
                                    : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // 🔥 ACCIONES
          Column(
            children: [
              _buildActionButton(
                icon: Icons.grid_on_rounded,
                color: brandBlue,
                onTap: () => _mostrarDialogoBloques(user),
              ),
              const SizedBox(height: 8),
              _buildActionButton(
                icon: Icons.dashboard_customize_rounded,
                color: Colors.teal,
                onTap: () => _mostrarDialogoModulos(user),
              ),
              const SizedBox(height: 8),
              _buildActionButton(
                icon: Icons.edit_rounded,
                color: Colors.orange,
                onTap: () => _mostrarDialogoEditar(user),
              ),
              const SizedBox(height: 8),
              _buildActionButton(
                icon: Icons.delete_rounded,
                color: Colors.redAccent,
                onTap: () => _confirmarEliminar(user['identificacion']),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

  // 🔥 BOTONES MODERNOS
  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }

  // ─── Diálogo editar ───────────────────────────────────────────────────────
  void _mostrarDialogoEditar(Map<String, dynamic> user) {
    TextEditingController nameCtrl = TextEditingController(
      text: user['nombres'],
    );
    TextEditingController passCtrl = TextEditingController(
      text: user['password'],
    );

    bool ocultarPassword = true;

    Get.dialog(
      StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                color: Colors.white,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 🔵 Icono
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: const Color(0xFF008DC5).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.edit,
                      color: Color(0xFF008DC5),
                      size: 30,
                    ),
                  ),

                  const SizedBox(height: 15),

                  const Text(
                    "Editar Usuario",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 20),

                  // 👤 Nombre
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Nombre',
                      prefixIcon: const Icon(Icons.person),
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),

                  const SizedBox(height: 15),

                  // 🔒 Contraseña con ojo 👁️
                  TextField(
                    controller: passCtrl,
                    obscureText: ocultarPassword,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          ocultarPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            ocultarPassword = !ocultarPassword;
                          });
                        },
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),

                  const SizedBox(height: 25),

                  // 🔘 Botones
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Get.back(),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text("Cancelar"),
                        ),
                      ),

                      const SizedBox(width: 10),

                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            bool ok = await gestUsuCtrl.editarUsuario(
                              user['identificacion'],
                              nameCtrl.text,
                              user['identificacion'],
                              passCtrl.text,
                            );

                            if (ok) {
                              Get.back();
                              _fetchUsuarios();

                              Get.snackbar(
                                "Éxito",
                                "Usuario actualizado correctamente",
                                backgroundColor: Colors.green,
                                colorText: Colors.white,
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF008DC5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            "Guardar",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Diálogo confirmar eliminar ───────────────────────────────────────────
  void _confirmarEliminar(String id) {
    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            color: Colors.white,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🔴 Icono de alerta
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_forever_rounded,
                  color: Colors.red,
                  size: 40,
                ),
              ),

              const SizedBox(height: 15),

              // 📝 Título
              const Text(
                "Eliminar Usuario",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              // ⚠️ Mensaje
              const Text(
                "Esta acción no se puede deshacer.\n¿Deseas continuar?",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),

              const SizedBox(height: 25),

              // 🔘 Botones
              Row(
                children: [
                  // Cancelar
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Get.back(),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text("Cancelar"),
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Eliminar
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Get.back(); // cerrar dialogo primero

                        // Loader mientras elimina
                        Get.dialog(
                          const Center(child: CircularProgressIndicator()),
                          barrierDismissible: false,
                        );

                        bool ok = await gestUsuCtrl.eliminarUsuario(id);

                        Get.back(); // cerrar loader

                        if (ok) {
                          _fetchUsuarios();

                          Get.snackbar(
                            "Eliminado",
                            "Usuario eliminado correctamente",
                            backgroundColor: Colors.green,
                            colorText: Colors.white,
                          );
                        } else {
                          Get.snackbar(
                            "Error",
                            "No se pudo eliminar el usuario",
                            backgroundColor: Colors.orange,
                            colorText: Colors.white,
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        elevation: 5,
                        shadowColor: Colors.red.withOpacity(0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "Eliminar",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
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

  // ─── Diálogo crear usuario ────────────────────────────────────────────────
  void _mostrarDialogoCrear() {
    TextEditingController nameCtrl = TextEditingController();
    TextEditingController idCtrl = TextEditingController();
    TextEditingController passCtrl = TextEditingController();

    bool ocultarPassword = true;

    Get.dialog(
      StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(25),
                  color: Colors.white,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 🔵 Icono superior
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: const Color(0xFF008DC5).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_add_alt_1_rounded,
                        color: Color(0xFF008DC5),
                        size: 35,
                      ),
                    ),

                    const SizedBox(height: 15),

                    // 📝 Título
                    const Text(
                      "Nuevo Usuario",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 👤 Nombre
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Nombre completo',
                        prefixIcon: const Icon(Icons.person),
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 15),

                    // 🆔 Identificación
                    TextField(
                      controller: idCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Identificación',
                        prefixIcon: const Icon(Icons.badge),
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 15),

                    // 🔒 Contraseña con ojo 👁️
                    TextField(
                      controller: passCtrl,
                      obscureText: ocultarPassword,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(
                            ocultarPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              ocultarPassword = !ocultarPassword;
                            });
                          },
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 25),

                    // 🔘 Botones
                    Row(
                      children: [
                        // Cancelar
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Get.back(),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text("Cancelar"),
                          ),
                        ),

                        const SizedBox(width: 10),

                        // Guardar
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              // 🔍 Validación básica
                              if (nameCtrl.text.isEmpty ||
                                  idCtrl.text.isEmpty ||
                                  passCtrl.text.isEmpty) {
                                Get.snackbar(
                                  "Campos requeridos",
                                  "Todos los campos son obligatorios",
                                  backgroundColor: Colors.orange,
                                  colorText: Colors.white,
                                );
                                return;
                              }

                              Get.back(); // cerrar dialogo

                              // ⏳ Loader
                              Get.dialog(
                                const Center(
                                  child: CircularProgressIndicator(),
                                ),
                                barrierDismissible: false,
                              );

                              bool ok = await gestUsuCtrl.registrarUsuario(
                                nameCtrl.text,
                                idCtrl.text,
                                passCtrl.text,
                              );

                              Get.back(); // cerrar loader

                              if (ok) {
                                _fetchUsuarios();

                                Get.snackbar(
                                  "Éxito",
                                  "Usuario creado correctamente",
                                  backgroundColor: Colors.green,
                                  colorText: Colors.white,
                                );
                              } else {
                                Get.snackbar(
                                  "Error",
                                  "No se pudo crear el usuario",
                                  backgroundColor: Colors.red,
                                  colorText: Colors.white,
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF008DC5),
                              elevation: 5,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              "Crear",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
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
        },
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarDialogoCrear,
        backgroundColor: brandBlue,
        foregroundColor: Colors.white,
        elevation: 5,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text(
          "NUEVO PERFIL",
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      body: RefreshIndicator(
        onRefresh: _fetchUsuarios,
        color: brandBlue,

        child: Column(
          children: [
            // HEADER MODERNO
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(
                top: 50,
                left: 18,
                right: 18,
                bottom: 22,
              ),

              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [brandBlue, darkBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),

                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),

                boxShadow: [
                  BoxShadow(
                    color: brandBlue.withOpacity(0.20),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),

              child: Column(
                children: [
                  // FILA PRINCIPAL
                  Row(
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
                              "GESTIÓN PERSONAL",
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

                  const SizedBox(height: 18),

                  // INFORMACIÓN
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 12,
                    ),

                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24),
                    ),

                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.people_alt_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),

                        const SizedBox(width: 12),

                        Expanded(
                          child: Text(
                            "${usuarios.length} usuarios registrados en el sistema",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.95),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // LISTADO
            Expanded(
              child: isLoading
                  ? Center(child: CircularProgressIndicator(color: brandBlue))
                  : usuarios.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.people_outline_rounded,
                            size: 70,
                            color: Colors.grey[300],
                          ),

                          const SizedBox(height: 12),

                          const Text(
                            "No hay registros",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                      itemCount: usuarios.length,
                      itemBuilder: (context, index) {
                        return _buildModernUserCard(usuarios[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
