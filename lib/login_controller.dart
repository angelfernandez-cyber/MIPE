import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth_android/local_auth_android.dart';

class LoginController extends GetxController {
  var isLoading = false.obs;
  var message = ''.obs;
  var loggedInUser = Rx<Map<String, dynamic>?>(null);

  final LocalAuthentication _auth = LocalAuthentication();

  final String supabaseUrl = 'https://dakdyrgfwimwytotkzca.supabase.co';
  final String apiKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRha2R5cmdmd2ltd3l0b3RremNhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYxNDkxMzUsImV4cCI6MjA5MTcyNTEzNX0.C9p5hPtQ95ZVRS0yzwfKs1O_kKyR4ayxvQlxcXoq1oE';
  // 🔥 coloca tu api key

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      verificarSesionExistente();
    });
  }

  // ─────────────────────────────────────────────
  // 🔐 VERIFICAR SESIÓN GUARDADA
  // ─────────────────────────────────────────────
  Future<void> verificarSesionExistente() async {
    final prefs = await SharedPreferences.getInstance();
    final String? usuarioGuardado = prefs.getString('user_data');

    if (usuarioGuardado != null) {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        // 💻 En PC entra directo (sin biometría)
        loggedInUser.value = json.decode(usuarioGuardado);
        Get.offAllNamed('/home');
      } else {
        autenticarBiometrico(json.decode(usuarioGuardado));
      }
    }
  }

  // ─────────────────────────────────────────────
  // 👆 AUTENTICACIÓN BIOMÉTRICA
  // ─────────────────────────────────────────────
  Future<void> autenticarBiometrico(Map<String, dynamic> datos) async {
    try {
      bool dispositivoSoportado = await _auth.isDeviceSupported();
      if (!dispositivoSoportado) {
        message.value = "Dispositivo no soporta biometría";
        return;
      }

      bool puedeVerificar = await _auth.canCheckBiometrics;
      if (!puedeVerificar) {
        message.value = "No hay biometría configurada";
        return;
      }

      bool exito = await _auth.authenticate(
        localizedReason: 'Accede a La Planicie',
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'Acceso Seguro',
            deviceCredentialsRequiredTitle: 'Ingrese su PIN',
            cancelButton: 'Cancelar',
          ),
        ],
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // permite PIN si falla huella
        ),
      );

      if (exito) {
        loggedInUser.value = datos;
        Get.offAllNamed('/home');
      } else {
        message.value = "Autenticación requerida";
      }
    } catch (e) {
      message.value = "Error biométrico";
    }
  }

  // ─────────────────────────────────────────────
  // 🔑 LOGIN NORMAL
  // ─────────────────────────────────────────────
  Future<void> login(String identificacion, String password) async {
    if (identificacion.isEmpty || password.isEmpty) {
      message.value = 'Ingrese datos';
      return;
    }

    try {
      isLoading.value = true;
      message.value = '';

      final url = Uri.parse(
        '$supabaseUrl/rest/v1/persona?identificacion=eq.$identificacion&password=eq.$password&select=*',
      );

      final response = await http.get(
        url,
        headers: {'apikey': apiKey, 'Authorization': 'Bearer $apiKey'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data.isNotEmpty) {
          final persona = data[0];

          // 🔥 IMPORTANTE: TODO EN STRING (compatibilidad total)
          final userMap = {
            'identificacion': persona['identificacion'].toString(),
            'nombres': persona['nombres'],
            'lectura': persona['lectura'] ?? '',
            'admin': persona['admin'] ?? 'N',
          };

          loggedInUser.value = userMap;

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_data', json.encode(userMap));

          Get.offAllNamed('/home');
        } else {
          message.value = 'Usuario o contraseña incorrectos';
        }
      } else {
        message.value = 'Error servidor (${response.statusCode})';
      }
    } catch (e) {
      message.value = 'Error de conexión';
    } finally {
      isLoading.value = false;
    }
  }

  // ─────────────────────────────────────────────
  // 🚪 LOGOUT (mantiene biometría)
  // ─────────────────────────────────────────────
  Future<void> logout() async {
    loggedInUser.value = null;
    message.value = "Sesión cerrada";
    Get.offAllNamed('/login');
  }

  // ─────────────────────────────────────────────
  // 🧹 BORRAR TODO (opcional)
  // ─────────────────────────────────────────────
  Future<void> borrarRastroTotal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_data');
    logout();
  }
}
