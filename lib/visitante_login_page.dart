import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'login_controller.dart';

class VisitanteLoginPage extends StatefulWidget {
  const VisitanteLoginPage({super.key});

  @override
  State<VisitanteLoginPage> createState() => _VisitanteLoginPageState();
}

class _VisitanteLoginPageState extends State<VisitanteLoginPage> {
  final LoginController loginController = Get.find<LoginController>();
  final TextEditingController _codigoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loginController.message.value = '';
  }

  @override
  void dispose() {
    _codigoController.dispose();
    super.dispose();
  }

  Future<void> _ingresar() async {
    final ingresoCorrecto = await loginController.iniciarSesionVisitante(
      _codigoController.text,
    );
    if (!ingresoCorrecto || !mounted) return;

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    Get.offAllNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    const azul = Color(0xFF008DC5);
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F8),
      appBar: AppBar(
        backgroundColor: azul,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Acceso visitante'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 9),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: azul.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(19),
                    ),
                    child: const Icon(
                      Icons.badge_outlined,
                      color: azul,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Ingresa el código vigente',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF17324D),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'Solicítalo al administrador de la finca.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.blueGrey.shade600),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _codigoController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 8,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '••••••',
                      filled: true,
                      fillColor: const Color(0xFFF2F6F8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _ingresar(),
                  ),
                  const SizedBox(height: 8),
                  Obx(
                    () =>
                        loginController.message.value.isEmpty
                            ? const SizedBox.shrink()
                            : Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                loginController.message.value,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: Obx(
                      () => FilledButton(
                        onPressed:
                            loginController.isLoading.value ? null : _ingresar,
                        style: FilledButton.styleFrom(
                          backgroundColor: azul,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        child:
                            loginController.isLoading.value
                                ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Text('Ingresar'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
