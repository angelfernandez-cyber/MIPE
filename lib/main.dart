import 'package:flutter/material.dart';
import 'package:flutter_application_1/formulario_almacen_page.dart';
import 'package:flutter_application_1/gestusu%20_page.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart'; // <--- IMPORTANTE: Faltaba esta línea
import 'historial_aseguramiento_page.dart';
// Importaciones de tus páginas
import 'login_page.dart';
import 'home_page.dart';
import 'formulario_page.dart';

/* import 'bloques_page.dart'; */
import 'consulta_page.dart';

import 'login_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa el idioma español para formateo de fechas
  await initializeDateFormatting('es', null);

  // Inyecta el controlador de forma permanente
  Get.put(LoginController(), permanent: true);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      debugShowCheckedModeBanner: false, // Quita la banda roja de "Debug"
      title: 'Cultivos La Planicie',

      // CONFIGURACIÓN DE IDIOMAS (Ahora funcionará porque importamos la librería)
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'ES')],

      initialRoute: '/login',
      getPages: [
        GetPage(name: '/login', page: () => const LoginPage()),
        GetPage(name: '/home', page: () => const HomePage()),
        GetPage(name: '/formulario', page: () => const FormularioPage()),
        GetPage(name: '/gestusu', page: () => const GestionUsuariosPage()),
        /*  GetPage(name: '/bloques', page: () => const BloquesPage()), */
        GetPage(name: '/consultaexcel', page: () => const ConsultarPage()),
        GetPage(name: '/aseguramiento', page: () => const AseguramientoPage()),
        GetPage(
          name: '/historialaseguramiento',
          page: () => const HistorialAseguramientoPage(),
        ),
      ],
    );
  }
}
