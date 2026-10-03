import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'dart:async';
import 'offline_sync_service.dart';
import 'visitante_service.dart';

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
  bool _autenticacionBiometricaEnCurso = false;
  Timer? _offlineSyncTimer;
  Timer? _visitorSessionTimer;
  String? _passwordEnMemoria;
  final Completer<void> _credencialesInicializadas = Completer<void>();
  static const String _visitorPreviousUserKey = 'usuario_anterior_visitante';
  static const String _visitorSessionActiveKey = 'visitante_sesion_activa';

  Future<void> get credencialesInicializadas =>
      _credencialesInicializadas.future;

  String? get passwordEnMemoria => _passwordEnMemoria;
  bool get esVisitante => loggedInUser.value?['visitante'] == true;
  bool get visitantePuedeInsertar =>
      !esVisitante || loggedInUser.value?['puede_insertar'] == true;

  // Ajusta tu URL y apiKey
  final String supabaseUrl = 'https://dakdyrgfwimwytotkzca.supabase.co';
  final String apiKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRha2R5cmdmd2ltd3l0b3RremNhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYxNDkxMzUsImV4cCI6MjA5MTcyNTEzNX0.C9p5hPtQ95ZVRS0yzwfKs1O_kKyR4ayxvQlxcXoq1oE';

  @override
  void onInit() {
    super.onInit();
    _offlineSyncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      OfflineSyncService.syncPending(supabaseUrl: supabaseUrl, apiKey: apiKey);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _handleFreshInstallCleanup();
        await _restaurarSesionInterrumpidaVisitante();
        await cargarUsuarioRecordado();
      } finally {
        if (!_credencialesInicializadas.isCompleted) {
          _credencialesInicializadas.complete();
        }
      }
      verificarSesionExistente();
    });
  }

  @override
  void onClose() {
    _offlineSyncTimer?.cancel();
    super.onClose();
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

      if (usuarioGuardado == null) {
        loggedInUser.value = null;
        message.value =
            'Inicia sesión con tu usuario para habilitar la huella.';
        return;
      }

      if (usuarioGuardado.isNotEmpty) {
        final usuarioPersistido = json.decode(usuarioGuardado);
        // En PC entramos directo (sin biometría)
        if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
          loggedInUser.value = usuarioPersistido;
          _passwordEnMemoria =
              await _secureStorage.read(key: 'password_recordado') ??
              prefs.getString('password_recordado_fallback');
          Get.offAllNamed('/home');
          return;
        }

        // En móvil, solo intentamos biometría si el flag está habilitado
        if (biometriaHabilitada) {
          await autenticarBiometrico(usuarioPersistido);
        } else {
          loggedInUser.value = null;
          message.value =
              'La huella no está habilitada. Inicia sesión primero.';
        }
      }
    } catch (e, st) {
      message.value = 'Error verificar sesión: ${e.toString()}';
      debugPrint('verificarSesionExistente error: $e\n$st');
    }
  }

  Future<void> _restaurarSesionInterrumpidaVisitante() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_visitorSessionActiveKey) ?? false)) return;

    final usuarioAnterior = prefs.getString(_visitorPreviousUserKey);
    if (usuarioAnterior == null) {
      await prefs.remove('user_data');
    } else {
      await prefs.setString('user_data', usuarioAnterior);
    }
    await prefs.remove(_visitorPreviousUserKey);
    await prefs.remove(_visitorSessionActiveKey);
  }

  // ─────────────────────────────────────────────
  // AUTENTICACIÓN BIOMÉTRICA
  // ─────────────────────────────────────────────
  Future<void> autenticarBiometrico(Map<String, dynamic> datos) async {
    if (_autenticacionBiometricaEnCurso) return;
    _autenticacionBiometricaEnCurso = true;
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
        _passwordEnMemoria =
            await _secureStorage.read(key: 'password_recordado') ??
            (await SharedPreferences.getInstance()).getString(
              'password_recordado_fallback',
            );
        // El plugin termina de cerrar el diálogo biométrico de Android al
        // completar authenticate; deja que Flutter procese ese frame primero.
        await WidgetsBinding.instance.endOfFrame;
        Get.offAllNamed('/home');
      } else {
        message.value = "Autenticación requerida";
      }
    } catch (e, st) {
      message.value = "Error biométrico: ${e.toString()}";
      debugPrint('autenticarBiometrico error: $e\n$st');
    } finally {
      _autenticacionBiometricaEnCurso = false;
    }
  }

  // ─────────────────────────────────────────────
  // LOGIN NORMAL
  // ─────────────────────────────────────────────
  Future<void> login(String identificacion, String password) async {
    await credencialesInicializadas;
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

      final http.Response response;
      try {
        response = await http
            .get(
              url,
              headers: {'apikey': apiKey, 'Authorization': 'Bearer $apiKey'},
            )
            .timeout(const Duration(seconds: 10));
      } on TimeoutException {
        await _loginSinConexion(identificacion, password);
        return;
      } on http.ClientException {
        await _loginSinConexion(identificacion, password);
        return;
      } on SocketException {
        await _loginSinConexion(identificacion, password);
        return;
      } on HandshakeException {
        await _loginSinConexion(identificacion, password);
        return;
      }

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
          _passwordEnMemoria = password;
          await _guardarCredencialOffline(userMap, password);

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

  // ─────────────────────────────────────────────
  // LOGIN SIN INTERNET
  // ─────────────────────────────────────────────
  // Tras cada ingreso exitoso con internet se guarda (cifrado en el
  // almacenamiento seguro del celular) el usuario y un hash de su contraseña.
  // Sin conexión se permite entrar si coinciden, para seguir trabajando y
  // dejar los registros pendientes por subir.
  String _offlineKey(String identificacion) =>
      'offline_login_${identificacion.trim()}';

  String _hashPassword(String identificacion, String password) =>
      sha256.convert(utf8.encode('${identificacion.trim()}|$password|mipe')).toString();

  Future<void> _guardarCredencialOffline(
    Map<String, dynamic> userMap,
    String password,
  ) async {
    try {
      final id = userMap['identificacion'].toString();
      await _secureStorage.write(
        key: _offlineKey(id),
        value: json.encode({
          'hash': _hashPassword(id, password),
          'user': userMap,
        }),
      );
    } catch (e) {
      debugPrint('No se pudo guardar el acceso offline: $e');
    }
  }

  Future<void> _loginSinConexion(String identificacion, String password) async {
    try {
      final raw = await _secureStorage.read(key: _offlineKey(identificacion));
      if (raw == null) {
        message.value =
            'Sin internet. Este usuario debe ingresar una vez con conexión en este celular.';
        return;
      }
      final guardado = json.decode(raw) as Map<String, dynamic>;
      if (guardado['hash'] != _hashPassword(identificacion, password)) {
        message.value = 'Usuario o contraseña incorrectos';
        return;
      }
      final userMap = Map<String, dynamic>.from(guardado['user'] as Map);
      loggedInUser.value = userMap;
      _passwordEnMemoria = password;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_data', json.encode(userMap));
      await prefs.setBool('biometria_habilitada', true);
      if (recordarUsuario.value) {
        await guardarUsuarioRecordado(userMap['identificacion'], password);
      }
      Get.offAllNamed('/home');
      Get.snackbar(
        'Modo sin conexión',
        'Ingresaste sin internet. Los registros quedarán pendientes y se subirán al recuperar la conexión.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      message.value = 'Sin internet y no se pudo validar el acceso guardado.';
      debugPrint('_loginSinConexion error: $e');
    }
  }

  // ─────────────────────────────────────────────
  // LOGOUT / BORRADO
  // ─────────────────────────────────────────────
  Future<void> logout({bool limpiarBiometria = false}) async {
    final eraVisitante = esVisitante;
    _visitorSessionTimer?.cancel();
    _visitorSessionTimer = null;
    _passwordEnMemoria = null;
    loggedInUser.value = null;
    message.value = "Sesión cerrada";
    final prefs = await SharedPreferences.getInstance();
    if (limpiarBiometria) {
      await prefs.setBool('biometria_habilitada', false);
      await prefs.remove('user_data');
      await prefs.remove(_visitorPreviousUserKey);
      await prefs.remove(_visitorSessionActiveKey);
    } else if (eraVisitante) {
      final usuarioAnterior = prefs.getString(_visitorPreviousUserKey);
      if (usuarioAnterior == null) {
        await prefs.remove('user_data');
      } else {
        await prefs.setString('user_data', usuarioAnterior);
      }
      await prefs.remove(_visitorPreviousUserKey);
      await prefs.remove(_visitorSessionActiveKey);
    }
    Get.offAllNamed('/login');
  }

  Future<bool> iniciarSesionVisitante(String codigo) async {
    if (codigo.trim().length != 6) {
      message.value = 'El código debe tener 6 dígitos.';
      return false;
    }
    try {
      isLoading.value = true;
      final visitante = await VisitanteService.validarCodigo(
        supabaseUrl: supabaseUrl,
        apiKey: apiKey,
        codigo: codigo.trim(),
      );
      // La configuración administrativa actual prevalece sobre una sesión
      // creada antes de que se cambiaran los permisos del visitante.
      Map<String, dynamic> configuracion = const {};
      try {
        configuracion = await VisitanteService.obtenerConfiguracion(
          supabaseUrl: supabaseUrl,
          apiKey: apiKey,
        );
      } catch (_) {
        // Si falla la segunda consulta, se conservan los permisos del RPC
        // que validó el código.
      }
      bool permiso(String clave) {
        final valor =
            configuracion.containsKey(clave)
                ? configuracion[clave]
                : visitante[clave];
        return valor == true || valor?.toString().toLowerCase() == 'true';
      }

      final puedeInsertar = permiso('puede_insertar');
      final puedeExportar = permiso('puede_exportar');
      final puedeVerAspersiones = permiso('puede_ver_aspersiones');
      final modulos =
          (visitante['lectura']?.toString() ?? '')
              .split(',')
              .map((modulo) => modulo.trim())
              .where((modulo) => modulo.isNotEmpty)
              .toSet();
      if (puedeExportar) {
        modulos.add('exportar_excel');
      } else {
        modulos.remove('exportar_excel');
      }
      if (puedeVerAspersiones) {
        modulos.add('ver_aspersiones');
      } else {
        modulos.remove('ver_aspersiones');
      }
      visitante['lectura'] = modulos.join(',');
      visitante['puede_insertar'] = puedeInsertar;
      visitante['puede_exportar'] = puedeExportar;
      visitante['visitante'] = true;
      loggedInUser.value = visitante;
      _passwordEnMemoria = null;
      final expiracion =
          DateTime.tryParse(visitante['expira_en']?.toString() ?? '') ??
          DateTime.now().add(const Duration(hours: 5));
      _visitorSessionTimer?.cancel();
      _visitorSessionTimer = Timer(
        expiracion.difference(DateTime.now()).isNegative
            ? Duration.zero
            : expiracion.difference(DateTime.now()),
        () => logout(),
      );
      final prefs = await SharedPreferences.getInstance();
      final usuarioAnterior = prefs.getString('user_data');
      if (usuarioAnterior == null) {
        await prefs.remove(_visitorPreviousUserKey);
      } else {
        await prefs.setString(_visitorPreviousUserKey, usuarioAnterior);
      }
      await prefs.setBool(_visitorSessionActiveKey, true);
      await prefs.remove('user_data');
      return true;
    } catch (e) {
      message.value = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<Map<String, dynamic>> obtenerCodigoVisitante({
    String? confirmarPassword,
  }) async {
    final usuario = loggedInUser.value;
    if (usuario?['admin']?.toString().trim() != 'S') {
      throw Exception('Solo el administrador puede consultar el código.');
    }
    final password = confirmarPassword ?? _passwordEnMemoria;
    if (password == null || password.isEmpty) {
      throw Exception(
        'Confirma tu contraseña de administrador para mostrar el código.',
      );
    }
    final result = await VisitanteService.generarCodigo(
      supabaseUrl: supabaseUrl,
      apiKey: apiKey,
      identificacion: usuario!['identificacion'].toString(),
      password: password,
    );
    _passwordEnMemoria = password;
    return result;
  }

  Future<void> guardarConfiguracionVisitantes({
    required bool habilitado,
    required bool puedeInsertar,
    required bool puedeExportar,
    required bool puedeVerAspersiones,
    String? confirmarPassword,
  }) async {
    final usuario = loggedInUser.value;
    final password = confirmarPassword ?? _passwordEnMemoria;
    if (usuario?['admin']?.toString().trim() != 'S' ||
        password == null ||
        password.isEmpty) {
      throw Exception('Confirma la contraseña del administrador para guardar.');
    }
    await VisitanteService.configurar(
      supabaseUrl: supabaseUrl,
      apiKey: apiKey,
      identificacion: usuario!['identificacion'].toString(),
      password: password,
      habilitado: habilitado,
      puedeInsertar: puedeInsertar,
      puedeExportar: puedeExportar,
      puedeVerAspersiones: puedeVerAspersiones,
    );
    _passwordEnMemoria = password;
  }

  Future<bool> actualizarCuentaAdministrador({
    required String nuevaPassword,
  }) async {
    final actual = loggedInUser.value;
    if (actual == null || actual['admin']?.toString().trim() != 'S') {
      message.value = 'Solo un administrador puede cambiar esta cuenta';
      return false;
    }

    final nuevaPasswordLimpia = nuevaPassword.trim();
    if (nuevaPasswordLimpia.isEmpty) {
      message.value = 'Escribe la nueva contraseña.';
      return false;
    }

    try {
      final identificacionActual = actual['identificacion'].toString();

      final url = Uri.parse(
        '$supabaseUrl/rest/v1/persona?identificacion=eq.$identificacionActual&admin=eq.S',
      );
      final response = await http.patch(
        url,
        headers: {
          'apikey': apiKey,
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'Prefer': 'return=representation',
        },
        // Nunca enviamos 'identificacion'. Esa columna es la llave
        // primaria de persona y esta referenciada por
        // firmas_usuarios_identificacion_fkey; con el esquema actual
        // (sin ON UPDATE CASCADE) Postgres rechaza cualquier UPDATE que
        // incluya esa columna si el usuario ya tiene firmas registradas,
        // aunque el valor nuevo sea igual al anterior. Por eso este
        // formulario solo permite cambiar la contraseña.
        body: jsonEncode({'password': nuevaPasswordLimpia}),
      );

      debugPrint(
        'actualizarCuentaAdministrador -> status=${response.statusCode} body=${response.body}',
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        String detalle = 'codigo ${response.statusCode}';
        try {
          final error = json.decode(response.body);
          if (error is Map && error['message'] != null) {
            detalle = error['message'].toString();
          }
        } catch (_) {}
        message.value = 'No se pudo guardar: $detalle';
        return false;
      }

      if (response.statusCode == 200) {
        final filas = json.decode(response.body);
        if (filas is List && filas.isEmpty) {
          message.value =
              'No se encontro tu cuenta de administrador para actualizar. '
              'Vuelve a iniciar sesion e intentalo de nuevo.';
          return false;
        }
      }

      final actualizado = Map<String, dynamic>.from(actual);
      _passwordEnMemoria = nuevaPasswordLimpia;
      loggedInUser.value = actualizado;
      await _guardarCredencialOffline(actualizado, nuevaPasswordLimpia);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_data', json.encode(actualizado));
      if (recordarUsuario.value) {
        await guardarUsuarioRecordado(identificacionActual, nuevaPasswordLimpia);
      }
      return true;
    } catch (e, st) {
      debugPrint('Error al actualizar la cuenta del administrador: $e\n$st');
      message.value = 'No se pudo guardar: ${e.toString()}';
      return false;
    }
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
    logout(limpiarBiometria: true);
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
      String? storedPassword;
      try {
        storedPassword = await _secureStorage.read(key: 'password_recordado');
      } catch (e) {
        // Si el almacén seguro no está disponible, usa el fallback guardado.
        debugPrint('No se pudo leer password_recordado en secure storage: $e');
      }
      if (storedPassword != null && storedPassword.isNotEmpty) {
        passwordRecordado.value = storedPassword;
      } else {
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
