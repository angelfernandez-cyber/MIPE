import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'login_controller.dart';
import 'visitante_service.dart';

Future<void> mostrarConfiguracionVisitantes(BuildContext context) async {
  final login = Get.find<LoginController>();
  Map<String, dynamic> config;
  try {
    config = await VisitanteService.obtenerConfiguracion(
      supabaseUrl: login.supabaseUrl,
      apiKey: login.apiKey,
    );
  } catch (e) {
    Get.snackbar(
      'Error al cargar visitantes',
      e.toString().replaceFirst('Exception: ', ''),
      duration: const Duration(seconds: 6),
    );
    return;
  }
  if (!context.mounted) return;

  var habilitado = config['habilitado'] == true;
  var puedeInsertar = config['puede_insertar'] == true;
  var puedeExportar = config['puede_exportar'] == true;
  final passwordController = TextEditingController();
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (dialogContext, setDialogState) => Dialog(
                  backgroundColor: Colors.transparent,
                  insetPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 28,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF008DC5), Color(0xFF005F86)],
                              ),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.badge_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Perfil visitante',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 19,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      SizedBox(height: 3),
                                      Text(
                                        'Habilita o inhabilita el ingreso con código.',
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
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                            child: Column(
                              children: [
                                SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  activeColor: const Color(0xFF168B59),
                                  value: habilitado,
                                  onChanged:
                                      (value) => setDialogState(
                                        () => habilitado = value,
                                      ),
                                  title: const Text(
                                    'Permitir ingreso con código',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    habilitado
                                        ? 'El perfil está activo y puede iniciar sesión.'
                                        : 'El perfil se conserva, pero nadie puede ingresar.',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                                SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  activeColor: const Color(0xFF008DC5),
                                  value: puedeInsertar,
                                  onChanged:
                                      (value) => setDialogState(
                                        () => puedeInsertar = value,
                                      ),
                                  title: const Text(
                                    'Añadir datos',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: const Text(
                                    'Permite registrar datos desde el aplicativo.',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                                SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  activeColor: const Color(0xFF087F5B),
                                  value: puedeExportar,
                                  onChanged:
                                      (value) => setDialogState(
                                        () => puedeExportar = value,
                                      ),
                                  title: const Text(
                                    'Exportar a Excel',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: const Text(
                                    'Permite descargar reportes.',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(13),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF2F6F8),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Text(
                                    'Este perfil es permanente: se puede inhabilitar, pero no eliminar.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF526575),
                                    ),
                                  ),
                                ),
                                if (login.passwordEnMemoria == null) ...[
                                  const SizedBox(height: 14),
                                  TextField(
                                    controller: passwordController,
                                    obscureText: true,
                                    decoration: InputDecoration(
                                      labelText:
                                          'Confirma la contraseña de administrador',
                                      prefixIcon: const Icon(
                                        Icons.lock_outline_rounded,
                                      ),
                                      filled: true,
                                      fillColor: const Color(0xFFF3F7F9),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed:
                                        () => Navigator.pop(dialogContext),
                                    child: const Text('Cancelar'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () async {
                                      try {
                                        await login.guardarConfiguracionVisitantes(
                                          habilitado: habilitado,
                                          puedeInsertar: puedeInsertar,
                                          puedeExportar: puedeExportar,
                                          puedeVerAspersiones:
                                              config['puede_ver_aspersiones'] ==
                                              true,
                                          confirmarPassword:
                                              passwordController.text.isEmpty
                                                  ? null
                                                  : passwordController.text,
                                        );
                                        if (dialogContext.mounted) {
                                          Navigator.pop(dialogContext);
                                        }
                                        Get.snackbar(
                                          'Guardado',
                                          'El perfil visitante fue actualizado.',
                                        );
                                      } catch (e) {
                                        Get.snackbar(
                                          'No se pudo guardar',
                                          e.toString().replaceFirst(
                                            'Exception: ',
                                            '',
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.check_rounded),
                                    label: const Text('Guardar'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF087F5B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ),
    );
  } finally {
    passwordController.dispose();
  }
}
