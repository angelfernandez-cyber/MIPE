import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Pide una contraseña en un diálogo. Devuelve el texto o null si se cancela.
///
/// El controlador vive dentro del propio widget y se libera en dispose(),
/// cuando el diálogo ya terminó su animación de cierre. Así se evita la
/// pantalla roja "TextEditingController was used after being disposed".
Future<String?> pedirPasswordDialog({
  String titulo = 'Confirma tu contraseña',
  String etiqueta = 'Contraseña actual',
  String textoBoton = 'Continuar',
}) {
  return Get.dialog<String>(
    _PasswordDialog(titulo: titulo, etiqueta: etiqueta, textoBoton: textoBoton),
  );
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({
    required this.titulo,
    required this.etiqueta,
    required this.textoBoton,
  });

  final String titulo;
  final String etiqueta;
  final String textoBoton;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _cerrar([String? resultado]) {
    FocusManager.instance.primaryFocus?.unfocus();
    Get.back(result: resultado);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: TextField(
        controller: _controller,
        obscureText: true,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.etiqueta),
        onSubmitted: (value) => _cerrar(value),
      ),
      actions: [
        TextButton(onPressed: () => _cerrar(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => _cerrar(_controller.text),
          child: Text(widget.textoBoton),
        ),
      ],
    );
  }
}
