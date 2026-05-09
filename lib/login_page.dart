import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:ui';
import 'login_controller.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _identificacionController =
      TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Usamos find si ya está inyectado, o put si es la primera vez
  final LoginController loginController = Get.put(
    LoginController(),
    permanent: true,
  );

  @override
  void dispose() {
    _identificacionController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF008DC5);
    const accentColor = Color(0xFF1DB954);

    return Scaffold(
      body: Stack(
        children: [
          // 1. FONDO DECORATIVO
          Container(color: Colors.white),
          Positioned(
            top: -100,
            right: -50,
            child: _buildCircle(300, primaryColor.withOpacity(0.2)),
          ),
          Positioned(
            bottom: -50,
            left: -80,
            child: _buildCircle(250, primaryColor.withOpacity(0.1)),
          ),

          // 2. CONTENIDO PRINCIPAL
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 30.0),
                child: Column(
                  children: [
                    // --- LOGO ---
                    Hero(
                      tag: 'logo',
                      child: Container(
                        height: 140,
                        width: 140,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: primaryColor.withOpacity(0.2),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: Image.asset(
                              'lib/img/logo.jpg',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(
                                    Icons.eco,
                                    size: 80,
                                    color: primaryColor,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),

                    // --- TÍTULOS ---
                    const Text(
                      "LA PLANICIE",
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: primaryColor,
                        letterSpacing: 2,
                      ),
                    ),
                    Container(
                      height: 3,
                      width: 50,
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "SISTEMA DE CONTROL MIPE",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // --- TARJETA DE LOGIN ---
                    ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.all(25),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              _buildCustomField(
                                controller: _identificacionController,
                                label: "Identificación",
                                icon: Icons.badge_outlined,
                                color: primaryColor,
                              ),
                              const SizedBox(height: 20),
                              _buildCustomField(
                                controller: _passwordController,
                                label: "Contraseña",
                                icon: Icons.lock_open_rounded,
                                color: primaryColor,
                                isPassword: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),

                    // --- BOTÓN PRINCIPAL Y BIOMETRÍA ---
                    Obx(
                      () => loginController.isLoading.value
                          ? const CircularProgressIndicator(color: primaryColor)
                          : Column(
                              children: [
                                Container(
                                  width: double.infinity,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    gradient: const LinearGradient(
                                      colors: [primaryColor, Color(0xFF00B4DB)],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: primaryColor.withOpacity(0.4),
                                        blurRadius: 15,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                    ),
                                    onPressed: () {
                                      loginController.login(
                                        _identificacionController.text,
                                        _passwordController.text,
                                      );
                                    },
                                    child: const Text(
                                      'INICIAR SESIÓN',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                  ),
                                ),

                                // --- ACCESO RÁPIDO BIOMÉTRICO ---
                                const SizedBox(height: 20),
                                IconButton(
                                  icon: const Icon(
                                    Icons.fingerprint_rounded,
                                    size: 50,
                                  ),
                                  color: accentColor,
                                  tooltip: 'Ingresar con huella',
                                  onPressed: () => loginController
                                      .verificarSesionExistente(),
                                ),
                                const Text(
                                  "Toque para usar biometría",
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                    ),

                    const SizedBox(height: 20),

                    // MENSAJE DE ERROR
                    Obx(
                      () => loginController.message.value.isNotEmpty
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                loginController.message.value,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),

                    // BOTÓN REGISTRO
                    TextButton(
                      onPressed: () => Get.toNamed('/register'),
                      child: RichText(
                        text: const TextSpan(
                          text: "¿No tienes cuenta? ",
                          style: TextStyle(color: Colors.blueGrey),
                          children: [
                            TextSpan(
                              text: "Regístrate",
                              style: TextStyle(
                                color: primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _buildCustomField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color color,
    bool isPassword = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(15),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: isPassword,
        style: const TextStyle(fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.grey, fontSize: 14),
          prefixIcon: Icon(icon, color: color),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 15,
          ),
        ),
      ),
    );
  }
}
