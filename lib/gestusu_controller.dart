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
