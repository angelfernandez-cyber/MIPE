import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'login_controller.dart';

class GestUsuController extends GetxController {
  final LoginController loginController = Get.find<LoginController>();

  // --- REGISTRAR NUEVO USUARIO ---
  Future<bool> registrarUsuario(
    String nombres,
    String identificacion,
    String password,
  ) async {
    try {
      final url = Uri.parse('${loginController.supabaseUrl}/rest/v1/persona');

      final response = await http.post(
        url,
        headers: {
          'apikey': loginController.apiKey,
          'Authorization': 'Bearer ${loginController.apiKey}',
          'Content-Type': 'application/json',
          'Prefer': 'return=minimal',
        },
        body: jsonEncode({
          'nombres': nombres,
          'identificacion': identificacion,
          'password': password,
          'lectura': '', // 👈 IMPORTANTE: string vacío
          'admin': 'N', // 👈 IMPORTANTE: siempre string
        }),
      );

      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) {
      print("Error en registro: $e");
      return false;
    }
  }

  // --- ACTUALIZAR PERMISOS ---
  Future<bool> actualizarPermiso(
    String id,
    String columna,
    String valor,
  ) async {
    try {
      final url = Uri.parse(
        '${loginController.supabaseUrl}/rest/v1/persona?identificacion=eq.$id',
      );

      final response = await http.patch(
        url,
        headers: {
          'apikey': loginController.apiKey,
          'Authorization': 'Bearer ${loginController.apiKey}',
          'Content-Type': 'application/json',
          'Prefer': 'return=minimal',
        },
        body: jsonEncode({
          columna: valor, // 👈 'lectura' o 'admin'
        }),
      );

      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      print("Error actualizando permisos: $e");
      return false;
    }
  }

  // --- GUARDAR PERMISOS DE BLOQUES CON FIRMA DEL ADMINISTRADOR ---
  // Devuelve null si todo salió bien, o el mensaje de error.
  Future<String?> guardarPermisosBloquesFirmado({
    required String identificacionAdmin,
    required String passwordAdmin,
    required String identificacionUsuario,
    required String lectura,
    String? firmaPngBase64,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(
              '${loginController.supabaseUrl}/rest/v1/rpc/guardar_permisos_bloques_firmado',
            ),
            headers: {
              'apikey': loginController.apiKey,
              'Authorization': 'Bearer ${loginController.apiKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'p_identificacion': identificacionAdmin,
              'p_password': passwordAdmin,
              'p_usuario': identificacionUsuario,
              'p_lectura': lectura,
              'p_firma_png_base64': firmaPngBase64,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) return null;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['message'] != null) {
          return decoded['message'].toString();
        }
      } catch (_) {}
      return 'No se pudieron guardar los permisos (${response.statusCode}).';
    } catch (e) {
      print("Error guardando permisos firmados: $e");
      return 'Error de conexión al guardar los permisos.';
    }
  }

  // --- EDITAR USUARIO ---
  Future<bool> editarUsuario(
    String idOriginal,
    String nuevoNombre,
    String nuevaId,
    String nuevaPass,
  ) async {
    try {
      final url = Uri.parse(
        '${loginController.supabaseUrl}/rest/v1/persona?identificacion=eq.$idOriginal',
      );

      final response = await http.patch(
        url,
        headers: {
          'apikey': loginController.apiKey,
          'Authorization': 'Bearer ${loginController.apiKey}',
          'Content-Type': 'application/json',
          'Prefer': 'return=minimal',
        },
        body: jsonEncode({
          'nombres': nuevoNombre,
          'identificacion': nuevaId,
          'password': nuevaPass,
        }),
      );

      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      print("Error al editar: $e");
      return false;
    }
  }

  // --- ELIMINAR USUARIO ---
  Future<bool> eliminarUsuario(String identificacion) async {
    try {
      final url = Uri.parse(
        '${loginController.supabaseUrl}/rest/v1/persona?identificacion=eq.$identificacion',
      );

      final response = await http.delete(
        url,
        headers: {
          'apikey': loginController.apiKey,
          'Authorization': 'Bearer ${loginController.apiKey}',
          'Content-Type': 'application/json',
        },
      );

      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      print("Error al eliminar: $e");
      return false;
    }
  }
}
