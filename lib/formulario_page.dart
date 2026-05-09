import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'login_controller.dart';
import 'excel_service.dart';

class FormularioPage extends StatefulWidget {
  const FormularioPage({super.key});

  @override
  State<FormularioPage> createState() => _FormularioPageState();
}

class _FormularioPageState extends State<FormularioPage> {
  bool esModoLectura = false;
  final _formKey = GlobalKey<FormState>();
  final LoginController loginController = Get.find<LoginController>();
  bool _isSaving = false;

  final Color brandBlue = const Color(0xFF008DC5);
  final Color brandGreen = const Color(0xFF1DB954);
  final Color bgColor = const Color(0xFFF4F7F9);

  // Controladores
  final _bloqueController = TextEditingController();
  final _jefeMipeController = TextEditingController();
  final _bomberoController = TextEditingController();
  final _blancoBioController = TextEditingController();
  final _tempController = TextEditingController();
  final _humedadController = TextEditingController();
  final _tipoController = TextEditingController();
  final _productoController = TextEditingController();
  final _dosisController = TextEditingController();
  final _catToxicController = TextEditingController();
  final _volumenCamaController = TextEditingController();
  final _direccionController = TextEditingController();
  final _numCamasController = TextEditingController();
  final _equipoController = TextEditingController();
  final _ireController = TextEditingController();
  final _grupoFumigadoresController = TextEditingController();
  final _semanaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (Get.arguments != null) {
      if (Get.arguments is Map) {
        if (Get.arguments.containsKey('id') || Get.arguments.containsKey('producto')) {
          esModoLectura = true;
          _llenarCamposParaLectura(Get.arguments);
        } else if (Get.arguments.containsKey('bloque')) {
          _bloqueController.text = Get.arguments['bloque'].toString();
          esModoLectura = false;
        }
      } else {
        _bloqueController.text = Get.arguments.toString();
        esModoLectura = false;
      }
    }
  }

  void _llenarCamposParaLectura(Map<String, dynamic> data) {
    _bloqueController.text = data['bloque']?.toString() ?? "";
    _jefeMipeController.text = data['jefe_mipe'] ?? "";
    _bomberoController.text = data['bombero'] ?? "";
    _blancoBioController.text = data['blanco_biologico'] ?? "";
    _tempController.text = data['temperatura']?.toString() ?? "";
    _humedadController.text = data['humedad_relativa']?.toString() ?? "";
    _tipoController.text = data['tipo_aplicacion'] ?? "";
    _productoController.text = data['producto'] ?? "";
    _dosisController.text = data['dosis'] ?? "";
    _catToxicController.text = data['cat_toxic'] ?? "";
    _volumenCamaController.text = data['volumen_cama'] ?? "";
    _direccionController.text = data['direccion'] ?? "";
    _numCamasController.text = data['num_camas']?.toString() ?? "";
    _equipoController.text = data['equipo'] ?? "";
    _ireController.text = data['ire_horas']?.toString() ?? "";
    _grupoFumigadoresController.text = data['grupo_fumigadores'] ?? "";
    _semanaController.text = data['semana']?.toString()??"";
  }

  void _limpiarCampos() {
    FocusManager.instance.primaryFocus?.unfocus();
    _formKey.currentState?.reset();
    _jefeMipeController.clear();
    _bomberoController.clear();
    _blancoBioController.clear();
    _tempController.clear();
    _humedadController.clear();
    _tipoController.clear();
    _productoController.clear();
    _dosisController.clear();
    _catToxicController.clear();
    _volumenCamaController.clear();
    _direccionController.clear();
    _numCamasController.clear();
    _equipoController.clear();
    _ireController.clear();
    _grupoFumigadoresController.clear();
    _semanaController.clear();
    setState(() {});
  }

  Future<void> _guardarEnSupabase() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final url = Uri.parse('${loginController.supabaseUrl}/rest/v1/aspersiones');
      final response = await http.post(
        url,
        headers: {
          'apikey': loginController.apiKey,
          'Authorization': 'Bearer ${loginController.apiKey}',
          'Content-Type': 'application/json',
          'Prefer': 'return=minimal',
        },
        body: jsonEncode({
          'bloque': _bloqueController.text.trim(),
          'jefe_mipe': _jefeMipeController.text,
          'bombero': _bomberoController.text,
          'blanco_biologico': _blancoBioController.text,
          'temperatura': _tempController.text,
          'humedad_relativa': _humedadController.text,
          'tipo_aplicacion': _tipoController.text,
          'producto': _productoController.text,
          'dosis': _dosisController.text,
          'cat_toxic': _catToxicController.text,
          'volumen_cama': _volumenCamaController.text,
          'direccion': _direccionController.text,
          'num_camas': _numCamasController.text,
          'equipo': _equipoController.text,
          'ire_horas': _ireController.text,
          'grupo_fumigadores': _grupoFumigadoresController.text,
          'usuario_registro': loginController.loggedInUser.value?['nombres'] ?? 'Operario',
          'semana':_semanaController.text,
          'fecha_registro': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        _limpiarCampos();
        Get.snackbar('Éxito', 'Registro guardado correctamente',
            backgroundColor: brandGreen, colorText: Colors.white, snackPosition: SnackPosition.BOTTOM);
      } else {
        Get.snackbar('Error', 'No se pudo guardar');
      }
    } catch (e) {
      Get.snackbar('Error Crítico', 'Verifica tu conexión');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(esModoLectura ? 'DETALLE DE ASPERSIÓN' : 'NUEVO REGISTRO MIPE', 
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
        backgroundColor: esModoLectura ? Colors.blueGrey[800] : brandBlue,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15.0, vertical: 10),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildSectionTitle("DATOS DE UBICACIÓN Y RESPONSABLE"),
                    _buildCard([
                      Row(
                        children: [
                          Expanded(child: _buildInput(_bloqueController, 'Bloque', Icons.grid_view, TextInputType.number)),
                          const SizedBox(width: 10),
                          Expanded(child: _buildInput(_bomberoController, 'Bombero', Icons.person, TextInputType.text)),
                        ],
                      ),
                      _buildInput(_jefeMipeController, 'Jefe MIPE', Icons.assignment_ind, TextInputType.text),
                      _buildInput(_direccionController, 'Dirección', Icons.navigation, TextInputType.text),
                    ]),

                    _buildSectionTitle("CONDICIONES AMBIENTALES"),
                    _buildCard([
                      _buildInput(_blancoBioController, 'Blanco Biológico', Icons.bug_report, TextInputType.text),
                      Row(
                        children: [
                          Expanded(child: _buildInput(_tempController, 'Temp (°C)', Icons.thermostat, TextInputType.number)),
                          const SizedBox(width: 10),
                          Expanded(child: _buildInput(_humedadController, 'Humedad (%)', Icons.water_drop, TextInputType.number)),
                        ],
                      ),
                    ]),

                    _buildSectionTitle("DETALLES TÉCNICOS Y PRODUCTO"),
                    _buildCard([
                      _buildInput(_productoController, 'Nombre del Producto', Icons.science, TextInputType.text),
                      Row(
                        children: [
                          Expanded(child: _buildInput(_tipoController, 'Tipo de Aplicación', Icons.category, TextInputType.number)),
                          const SizedBox(width: 10),
                          Expanded(child: _buildInput(_semanaController, 'Semana', Icons.category, TextInputType.number)),

                        ],
                      ),
                      Row(
                        children: [
                          Expanded(child: _buildInput(_dosisController, 'Dosis', Icons.straighten, TextInputType.number)),
                          const SizedBox(width: 10),
                          Expanded(child: _buildInput(_catToxicController, 'Cat. Toxic', Icons.warning_amber_rounded, TextInputType.number)),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(child: _buildInput(_volumenCamaController, 'Vol. Cama', Icons.layers, TextInputType.number)),
                          const SizedBox(width: 10),
                          Expanded(child: _buildInput(_numCamasController, 'No. Camas', Icons.format_list_numbered, TextInputType.number)),
                        ],
                      ),
                    ]),

                    _buildSectionTitle("OPERACIÓN Y SEGURIDAD"),
                    _buildCard([
                      _buildInput(_equipoController, 'Equipo Utilizado', Icons.handyman, TextInputType.text),
                      _buildInput(_grupoFumigadoresController, 'Grupo Fumigadores', Icons.groups, TextInputType.text),
                      _buildInput(_ireController, 'I.R.E (Horas de Reingreso)', Icons.timer, TextInputType.number),
                    ]),

                    const SizedBox(height: 30),
                    _buildButtons(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 25),
      decoration: BoxDecoration(
        color: esModoLectura ? Colors.blueGrey[800] : brandBlue,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(35)),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 35,
            backgroundColor: Colors.white.withOpacity(0.2),
            child: Icon(
              esModoLectura ? Icons.description_outlined : Icons.post_add_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            esModoLectura ? "Consulta de Registro" : "Completar Formulario",
            style: const TextStyle(color: Colors.white70, letterSpacing: 1.2, fontWeight: FontWeight.w500),
          )
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Container(
      padding: const EdgeInsets.only(left: 5, top: 20, bottom: 8),
      alignment: Alignment.centerLeft,
      child: Text(title, style: TextStyle(color: brandBlue, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.1)),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildInput(TextEditingController controller, String label, IconData icon, TextInputType type) {
    bool isReadOnly = esModoLectura || (label == 'Bloque');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: type,
        readOnly: isReadOnly,
        style: TextStyle(fontWeight: isReadOnly ? FontWeight.bold : FontWeight.normal, color: isReadOnly ? Colors.blueGrey[800] : Colors.black),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 13),
          filled: isReadOnly,
          fillColor: isReadOnly ? Colors.blueGrey[50] : Colors.white,
          prefixIcon: Icon(icon, size: 20, color: isReadOnly ? Colors.blueGrey : brandBlue),
          contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)),
        ),
        validator: (val) => (val!.isEmpty && !esModoLectura) ? 'Campo obligatorio' : null,
      ),
    );
  }


 // Busca el método _buildButtons dentro de FormularioPage y reemplázalo:

Widget _buildButtons() {
  if (!esModoLectura) {
    return _isSaving
        ? const CircularProgressIndicator()
        : ElevatedButton.icon(
            onPressed: _guardarEnSupabase,
            icon: const Icon(Icons.cloud_upload_rounded, color: Colors.white),
            label: const Text('FINALIZAR REGISTRO', 
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            style: ElevatedButton.styleFrom(
              backgroundColor: brandBlue,
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              elevation: 5,
            ),
          );
  }

  return Column(
    children: [
      ElevatedButton.icon(
        onPressed: () async {
          Get.snackbar("Procesando", "Obteniendo datos de la semana...", 
              backgroundColor: brandBlue, colorText: Colors.white);

          try {
            // Consultamos todos los registros de este bloque en Supabase
            final String bloqueId = _bloqueController.text;
            final url = Uri.parse(
              '${loginController.supabaseUrl}/rest/v1/aspersiones?bloque=eq.$bloqueId&select=*&order=fecha_registro.desc'
            );

            final response = await http.get(
              url,
              headers: {
                'apikey': loginController.apiKey,
                'Authorization': 'Bearer ${loginController.apiKey}',
              },
            );

            if (response.statusCode == 200) {
              List<dynamic> listaDatos = json.decode(response.body);
              if (listaDatos.isNotEmpty) {
                // Llamamos al servicio con todos los registros encontrados
                await MIPEExcelService.generarReporteMIPE(listaDatos);
              } else {
                Get.snackbar("Aviso", "No se encontraron datos para exportar");
              }
            } else {
              Get.snackbar("Error", "Error al conectar con el servidor");
            }
          } catch (e) {
            Get.snackbar("Error", "Ocurrió un problema al generar el archivo");
          }
        },
        icon: const Icon(Icons.file_download_rounded, color: Colors.white),
        label: const Text("EXPORTAR A EXCEL (SEMANAL)", 
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: brandGreen,
          minimumSize: const Size(double.infinity, 55),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () => Get.back(),
        icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.blueGrey[700]),
        label: Text("VOLVER AL HISTORIAL", 
          style: TextStyle(color: Colors.blueGrey[700], fontWeight: FontWeight.bold)),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 55),
          side: BorderSide(color: Colors.blueGrey[200]!),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
      ),
    ],
  );
}
}