import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'offline_sync_service.dart';

class LoginController extends GetxController {
  var isLoading = false.obs;
  var message = ''.obs;
  var loggedInUser = Rx<Map<String, dynamic>?>(null);

  // Recordar usuario/contraseña
  var recordarUsuario = false.obs;
  var usuarioRecordado = ''.obs;
  var passwordRecordado = ''.obs;

  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // Ajusta tu URL y apiKey
  final String supabaseUrl = 'https://dakdyrgfwimwytotkzca.supabase.co';
  final String apiKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRha2R5cmdmd2ltd3l0b3RremNhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYxNDkxMzUsImV4cCI6MjA5MTcyNTEzNX0.C9p5hPtQ95ZVRS0yzwfKs1O_kKyR4ayxvQlxcXoq1oE';

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _handleFreshInstallCleanup();
      await cargarUsuarioRecordado();
      verificarSesionExistente();
    });
  }

  /// Detecta instalación nueva y limpia credenciales guardadas si corresponde.
  Future<void> _handleFreshInstallCleanup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool alreadyInitialized = prefs.getBool('app_initialized') ?? false;

      if (!alreadyInitialized) {
        debugPrint(
          'Instalación nueva detectada: limpiando credenciales guardadas.',
        );

        // Borrar password guardada en flutter_secure_storage (si existe)
        try {
          await _secureStorage.delete(key: 'password_recordado');
        } catch (e) {
          debugPrint(
            'No se pudo borrar password_recordado en secure storage: $e',
          );
        }

        // Borrar fallback en SharedPreferences (si existe)
        try {
          await prefs.remove('password_recordado_fallback');
          await prefs.remove('password_recordado');
          await prefs.remove('usuario_recordado');
          await prefs.setBool('recordar_usuario', false);
        } catch (e) {
          debugPrint('Error limpiando SharedPreferences: $e');
        }

        // Marcar que ya inicializamos la app
        await prefs.setBool('app_initialized', true);
      } else {
        debugPrint('App ya inicializada anteriormente.');
      }
    } catch (e) {
      debugPrint('Error en _handleFreshInstallCleanup: $e');
    }
  }

  // ─────────────────────────────────────────────
  // VERIFICAR SESIÓN GUARDADA
  // ─────────────────────────────────────────────
  Future<void> verificarSesionExistente() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? usuarioGuardado = prefs.getString('user_data');
      final bool biometriaHabilitada =
          prefs.getBool('biometria_habilitada') ?? false;

      if (usuarioGuardado != null) {
        // En web y escritorio entramos directo: el navegador no tiene la
        // biometría nativa de local_auth.
        if (kIsWeb || [
          TargetPlatform.windows,
          TargetPlatform.macOS,
          TargetPlatform.linux,
        ].contains(defaultTargetPlatform)) {
          loggedInUser.value = json.decode(usuarioGuardado);
          await sincronizarPendientes();
          Get.offAllNamed('/home');
          return;
        }

        // En móvil, solo intentamos biometría si el flag está habilitado
        if (biometriaHabilitada) {
          autenticarBiometrico(json.decode(usuarioGuardado));
        } else {
          loggedInUser.value = null;
        }
      } else {
        loggedInUser.value = null;
      }
    } catch (e, st) {
      message.value = 'Error verificar sesión: ${e.toString()}';
      debugPrint('verificarSesionExistente error: $e\n$st');
    }
  }

  // ─────────────────────────────────────────────
  // AUTENTICACIÓN BIOMÉTRICA
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
          biometricOnly: false,
        ),
      );

      if (exito) {
        loggedInUser.value = datos;
        await sincronizarPendientes();
        Get.offAllNamed('/home');
      } else {
        message.value = "Autenticación requerida";
      }
    } catch (e, st) {
      message.value = "Error biométrico: ${e.toString()}";
      debugPrint('autenticarBiometrico error: $e\n$st');
    }
  }

  // ─────────────────────────────────────────────
  // LOGIN NORMAL
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

      debugPrint('Request login: $url');

      final response = await http.get(
        url,
        headers: {'apikey': apiKey, 'Authorization': 'Bearer $apiKey'},
      );

      debugPrint('Status: ${response.statusCode}');
      debugPrint('Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data.isNotEmpty) {
          final persona = data[0];
          final userMap = {
            'identificacion': persona['identificacion'].toString(),
            'nombres': persona['nombres'],
            'lectura': persona['lectura'] ?? '',
            'admin': persona['admin'] ?? 'N',
          };

          loggedInUser.value = userMap;

          await sincronizarPendientes();

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_data', json.encode(userMap));
          await prefs.setBool('biometria_habilitada', true);

          if (recordarUsuario.value) {
            await guardarUsuarioRecordado(userMap['identificacion'], password);
          } else {
            await borrarUsuarioRecordado();
          }

          Get.offAllNamed('/home');
        } else {
          message.value = 'Usuario o contraseña incorrectos';
        }
      } else {
        message.value = 'Error servidor (${response.statusCode})';
      }
    } catch (e, st) {
      message.value = 'Error de conexión: ${e.toString()}';
      debugPrint('login error: $e\n$st');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> sincronizarPendientes() async {
    await OfflineSyncService.sincronizarAspersiones(
      supabaseUrl: supabaseUrl,
      apiKey: apiKey,
    );
  }

  // ─────────────────────────────────────────────
  // LOGOUT / BORRADO
  // ─────────────────────────────────────────────
  Future<void> logout({bool limpiarBiometria = false}) async {
    loggedInUser.value = null;
    message.value = "Sesión cerrada";
    if (limpiarBiometria) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('biometria_habilitada', false);
      await prefs.remove('user_data');
    }
    Get.offAllNamed('/login');
  }

  Future<void> borrarRastroTotal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_data');
    await prefs.remove('biometria_habilitada');
    await prefs.remove('usuario_recordado');
    await prefs.remove('recordar_usuario');
    try {
      await _secureStorage.delete(key: 'password_recordado');
    } catch (e) {
      debugPrint('No se pudo borrar password_recordado: $e');
    }
    await prefs.remove('password_recordado_fallback');
    await prefs.remove('password_recordado');
    logout();
  }

  // ─────────────────────────────────────────────
  // Métodos para "Recordar usuario" y "Recordar contraseña"
  // ─────────────────────────────────────────────

  // Cargar preferencia, usuario y contraseña recordada al iniciar
  Future<void> cargarUsuarioRecordado() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      recordarUsuario.value = prefs.getBool('recordar_usuario') ?? false;
      usuarioRecordado.value = prefs.getString('usuario_recordado') ?? '';
      final storedPassword = await _secureStorage.read(
        key: 'password_recordado',
      );
      if (storedPassword != null && storedPassword.isNotEmpty) {
        passwordRecordado.value = storedPassword;
      } else {
        // fallback inseguro si secure storage no funciona
        passwordRecordado.value =
            prefs.getString('password_recordado_fallback') ?? '';
      }
      debugPrint(
        'cargarUsuarioRecordado -> user: ${usuarioRecordado.value}, hasPass: ${passwordRecordado.value.isNotEmpty}',
      );
    } catch (e, st) {
      debugPrint('Error cargarUsuarioRecordado: $e\n$st');
      recordarUsuario.value = false;
      usuarioRecordado.value = '';
      passwordRecordado.value = '';
    }
  }

  // Guardar el usuario recordado y la contraseña (intenta secure storage, fallback a prefs)
  Future<void> guardarUsuarioRecordado(
    String identificacion,
    String password,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('recordar_usuario', true);
      await prefs.setString('usuario_recordado', identificacion);
      await _secureStorage.write(key: 'password_recordado', value: password);
      await prefs.remove('password_recordado_fallback');
      recordarUsuario.value = true;
      usuarioRecordado.value = identificacion;
      passwordRecordado.value = password;
      debugPrint('guardarUsuarioRecordado OK (secure storage)');
    } catch (e, st) {
      debugPrint('guardarUsuarioRecordado error: $e\n$st');
      // fallback inseguro
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('recordar_usuario', true);
      await prefs.setString('usuario_recordado', identificacion);
      await prefs.setString('password_recordado_fallback', password);
      recordarUsuario.value = true;
      usuarioRecordado.value = identificacion;
      passwordRecordado.value = password;
      debugPrint('guardarUsuarioRecordado OK (fallback prefs)');
    }
  }

  // Borrar el usuario recordado y la contraseña (intenta borrar secure storage y prefs)
  Future<void> borrarUsuarioRecordado() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('recordar_usuario', false);
      await prefs.remove('usuario_recordado');
      await prefs.remove(
        'password_recordado',
      ); // si guardas en prefs (fallback)
      // Intentar borrar secure storage también
      try {
        await _secureStorage.delete(key: 'password_recordado');
      } catch (e) {
        debugPrint('Error borrando password_recordado en secure storage: $e');
      }
      await prefs.remove('password_recordado_fallback');
      recordarUsuario.value = false;
      usuarioRecordado.value = '';
      passwordRecordado.value = '';
      debugPrint('borrarUsuarioRecordado OK');
    } catch (e, st) {
      debugPrint('borrarUsuarioRecordado error: $e\n$st');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('recordar_usuario', false);
      await prefs.remove('usuario_recordado');
      await prefs.remove('password_recordado_fallback');
      recordarUsuario.value = false;
      usuarioRecordado.value = '';
      passwordRecordado.value = '';
    }
  }
}
