import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart'; // Asegúrate de tener intl en tu pubspec.yaml
import 'login_controller.dart';

class AseguramientoPage extends StatefulWidget {
  final Map<String, dynamic>? dataInicial; // Datos que vienen del historial
  final bool esLectura; // Para saber si bloqueamos el formulario

  const AseguramientoPage({
    super.key,
    this.dataInicial,
    this.esLectura = false,
  });

  @override
  State<AseguramientoPage> createState() => _AseguramientoPageState();
}

class _AseguramientoPageState extends State<AseguramientoPage> {
  final _formKey = GlobalKey<FormState>();
  final LoginController loginController = Get.find<LoginController>();
  bool _isSaving = false;

  final Color brandBlue = const Color(0xFF008DC5);
  final Color brandGreen = const Color(0xFF1DB954);

  // --- CONTROLADORES ---
  final _semanaController = TextEditingController();
  final _productoController = TextEditingController();
  final _proveedorController = TextEditingController();
  final _presentacionController =
      TextEditingController(); // Unidad de medida (Texto)
  final _unidadesController = TextEditingController(); // Total unidades (Int)
  final _loteController = TextEditingController(); // # Lote (Texto)
  final _vencimientoController = TextEditingController(); // Fecha (Texto/Date)
  final _cantidadController =
      TextEditingController(); // Cantidad cc/g (Numeric)
  final _colorController = TextEditingController(); // Color (Texto)
  final _phController = TextEditingController(); // pH (Numeric)
  final _densidadController = TextEditingController(); // Densidad (Numeric)
  final _obsController = TextEditingController(); // Observaciones (Texto)
  final _aseguraController = TextEditingController();
  final _autorizaController = TextEditingController();

  // --- ESTADOS BOTONES SELECCIÓN ---
  String _estadoEtiqueta = 'CUMPLE';
  String _estadoTapa = 'CUMPLE';
  String _sellos = 'CUMPLE';
  String _puntosextraccion = 'CUMPLE';

  void initState() {
    super.initState();
    // Si recibimos datos, llenamos los controladores
    if (widget.dataInicial != null) {
      _semanaController.text = widget.dataInicial!['semana']?.toString() ?? '';
      _productoController.text = widget.dataInicial!['nombre_producto'] ?? '';
      _proveedorController.text = widget.dataInicial!['proveedor'] ?? '';
      _presentacionController.text = widget.dataInicial!['presentacion'] ?? '';
      _unidadesController.text =
          widget.dataInicial!['total_unidades']?.toString() ?? '';
      _loteController.text = widget.dataInicial!['lote'] ?? '';
      _vencimientoController.text =
          widget.dataInicial!['fecha_vencimiento'] ?? '';
      _cantidadController.text =
          widget.dataInicial!['cantidad_cc_g']?.toString() ?? '';
      _colorController.text = widget.dataInicial!['color'] ?? '';
      _phController.text = widget.dataInicial!['ph']?.toString() ?? '';
      _densidadController.text =
          widget.dataInicial!['densidad']?.toString() ?? '';
      _obsController.text = widget.dataInicial!['observaciones'] ?? '';
      _aseguraController.text =
          widget.dataInicial?['identificacion_asegura'] ?? '';
      _autorizaController.text = widget.dataInicial?['autorizacion'] ?? '';

      // Actualizamos los estados de los botones
      _estadoEtiqueta = widget.dataInicial!['estado_etiqueta'] ?? 'CUMPLE';
      _estadoTapa = widget.dataInicial!['estado_tapa'] ?? 'CUMPLE';
      _sellos = widget.dataInicial!['sellos'] ?? 'CUMPLE';
      _puntosextraccion = widget.dataInicial!['puntos_extraccion'] ?? 'CUMPLE';
    }
  }

  // Función para seleccionar fecha de vencimiento
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime(2040),
      locale: const Locale('es', 'ES'),
    );
    if (picked != null) {
      setState(() {
        _vencimientoController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _guardarEnBaseDeDatos() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      // Obtenemos el ID del usuario logueado
      

      final url = Uri.parse(
        '${loginController.supabaseUrl}/rest/v1/aseguramiento_plaguicidas',
      );

      // Creamos el cuerpo de la petición con los nombres EXACTOS de tu base de datos
      final Map<String, dynamic> body = {
        'semana': int.tryParse(_semanaController.text),

        // 1. FECHA DEL REGISTRO: Obligatoria según tu esquema de base de datos
        'fecha': DateFormat('yyyy-MM-dd').format(DateTime.now()),

        'nombre_producto': _productoController.text.trim(),
        'proveedor': _proveedorController.text.trim(),

        // 2. CAMPOS DE PRESENTACIÓN Y UNIDADES (Asegúrate de que existan en la tabla)
        'presentacion': _presentacionController.text.trim(),
        'total_unidades': int.tryParse(_unidadesController.text) ?? 0,

        'lote': _loteController.text.trim(),
        'fecha_vencimiento': _vencimientoController.text.isEmpty
            ? null
            : _vencimientoController.text,

        'estado_etiqueta': _estadoEtiqueta,
        'estado_tapa': _estadoTapa,
        'sellos': _sellos,
        'puntos_extraccion': _puntosextraccion,

        // 3. CAMPOS NUMÉRICOS (Convertidos correctamente a double/int)
        'cantidad_cc_g': double.tryParse(_cantidadController.text) ?? 0.0,
        'color': _colorController.text.trim().isEmpty
            ? "No definido"
            : _colorController.text.trim(),
        'ph': double.tryParse(_phController.text) ?? 0.0,
        'densidad': double.tryParse(_densidadController.text) ?? 0.0,

        'observaciones': _obsController.text.trim(),
        'autorizacion': _autorizaController.text.trim(),

        // 4. IDENTIFICACIÓN: Se envía como texto según tu esquema
        'identificacion_asegura': _aseguraController.text.trim(),
      };

      final response = await http.post(
        url,
        headers: {
          'apikey': loginController.apiKey,
          'Authorization': 'Bearer ${loginController.apiKey}',
          'Content-Type': 'application/json',
          'Prefer': 'return=minimal',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        Get.snackbar(
          'Éxito',
          'Registro guardado correctamente',
          backgroundColor: brandGreen,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );

        // Limpiamos el formulario después del éxito
        _formKey.currentState?.reset();
        _semanaController.clear();
        _productoController.clear();
        _proveedorController.clear();
        _presentacionController.clear();
        _unidadesController.clear();
        _loteController.clear();
        _vencimientoController.clear();
        _cantidadController.clear();
        _colorController.clear();
        _phController.clear();
        _densidadController.clear();
        _obsController.clear();
        _aseguraController.clear();
        _autorizaController.clear();

        setState(() {
          _estadoEtiqueta = 'CUMPLE';
          _estadoTapa = 'CUMPLE';
          _sellos = 'CUMPLE';
          _puntosextraccion = 'CUMPLE';
        });
      } else {
        // Si Supabase responde con error, lo mostramos para saber qué columna falla
        throw Exception('Error de Supabase: ${response.body}');
      }
    } catch (e) {
      Get.snackbar(
        'Error',
        'No se pudo guardar el registro: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 8),
        snackPosition: SnackPosition.BOTTOM,
      );
      print("DETALLE DEL ERROR: $e");
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: Colors.white,

    appBar: AppBar(
      toolbarHeight: 75,
      elevation: 0,
      backgroundColor: Colors.transparent,
      automaticallyImplyLeading: false,

      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF008DC5),
              Color(0xFF005F86),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(28),
          ),
        ),
      ),

      title: Row(
        children: [
          // BOTÓN ATRÁS
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 18,
              ),
              onPressed: () => Get.back(),
            ),
          ),

          const SizedBox(width: 14),

          // TITULO
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Control de",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  "ASEGURAMIENTO",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),

    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderInfo(),
            const SizedBox(height: 20),

              _sectionTitle("DATOS DEL PRODUCTO"),
              Row(
                children: [
                  Expanded(
                    child: _buildNumberInput(
                      _semanaController,
                      'Semana',
                      Icons.calendar_today,
                      isDecimal: false, // Entero para la semana
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      _productoController,
                      'Nombre Producto',
                      Icons.inventory,
                    ),
                  ),
                ],
              ),

              _buildTextField(
                _proveedorController,
                'Proveedor',
                Icons.business,
              ),

              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      _presentacionController,
                      'Presentación-(Cantidad)',
                      Icons.layers,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildNumberInput(
                      _unidadesController,
                      'Total Unidades',
                      Icons.numbers,
                      isDecimal: false, // Entero para unidades físicas
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      _loteController,
                      '# Lote',
                      Icons.tag, // Texto para permitir códigos de lote
                    ),
                  ),
                ],
              ),

              // Campo de Fecha con selector (Consistente con tu lógica de DatePicker)
              // Así de simple debe quedar en tu lista de campos:
              _buildTextField(
                _vencimientoController,
                'Fecha de Vencimiento',
                Icons.event,
                onTap: () => _selectDate(
                  context,
                ), // Aquí le decimos que abra el calendario
                readOnly: true, // Aquí le decimos que no abra el teclado
              ),

              _sectionTitle("CARACTERÍSTICAS DE SEGURIDAD"),
              _buildOptionSelector(
                "Estado Etiqueta",
                _estadoEtiqueta,
                (val) => setState(() => _estadoEtiqueta = val),
              ),
              _buildOptionSelector(
                "Estado Tapa",
                _estadoTapa,
                (val) => setState(() => _estadoTapa = val),
              ),
              _buildOptionSelector(
                "Sellos",
                _sellos,
                (val) => setState(() => _sellos = val),
              ),
              _buildOptionSelector(
                "Puntos Extracción",
                _puntosextraccion,
                (val) => setState(() => _puntosextraccion = val),
              ),

              _sectionTitle("ANÁLISIS FÍSICO-QUÍMICO"),
              Row(
                children: [
                  Expanded(
                    child: _buildNumberInput(
                      _cantidadController,
                      'Cantidad cc/g',
                      Icons.scale,
                      isDecimal: true, // Decimal para gramajes exactos
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      _colorController,
                      'Color',
                      Icons
                          .colorize, // Cambiado a TextField para escribir el color
                    ),
                  ),
                ],
              ),

              Row(
                children: [
                  Expanded(
                    child: _buildNumberInput(
                      _phController,
                      'pH',
                      Icons.water_drop,
                      isDecimal: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildNumberInput(
                      _densidadController,
                      'Densidad',
                      Icons.shutter_speed,
                      isDecimal: true,
                    ),
                  ),
                ],
              ),

              _buildTextField(
                _obsController,
                'Observaciones',
                Icons.comment,
                isMultiline: true,
              ),
              _buildTextField(
                _aseguraController,
                'Quien Asegura',
                Icons.verified_user,
              ),
              _buildTextField(
                _autorizaController,
                'Quien Autoriza',
                Icons.admin_panel_settings,
              ),

              const SizedBox(height: 30),
              if (!widget
                  .esLectura) // Solo muestra el botón si NO es modo lectura
                _isSaving
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton.icon(
                        onPressed: _guardarEnBaseDeDatos,
                        icon: const Icon(
                          Icons.cloud_upload,
                          color: Colors.white,
                        ),
                        label: const Text(
                          "GUARDAR REGISTRO",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: brandBlue,
                          minimumSize: const Size(double.infinity, 60),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGETS AUXILIARES ---

  Widget _buildOptionSelector(
    String label,
    String currentValue,
    Function(String) onSelected,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        AbsorbPointer(
          absorbing: widget.esLectura, // Evita que cambien CUMPLE/NO CUMPLE
          child: Row(
            children: [
              Expanded(
                child: _optionButton(
                  "CUMPLE",
                  currentValue == "CUMPLE",
                  brandGreen,
                  () => onSelected("CUMPLE"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _optionButton(
                  "NO CUMPLE",
                  currentValue == "NO CUMPLE",
                  Colors.redAccent,
                  () => onSelected("NO CUMPLE"),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 15),
      ],
    );
  }

  Widget _optionButton(
    String text,
    bool isSelected,
    Color activeColor,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor : Colors.grey[300]!,
          ),
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey[600],
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isMultiline = false,
    VoidCallback? onTap,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AbsorbPointer(
        absorbing: widget.esLectura, // Bloquea interacción si es modo lectura
        child: TextFormField(
          controller: controller,
          maxLines: isMultiline ? 3 : 1,
          readOnly: widget.esLectura || readOnly,
          onTap: onTap,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, color: brandBlue, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            filled: true,
            fillColor: widget.esLectura ? Colors.grey[200] : Colors.grey[50],
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          validator: (v) => v!.isEmpty ? 'Requerido' : null,
        ),
      ),
    );
  }

  Widget _buildNumberInput(
    TextEditingController controller,
    String label,
    IconData icon, {
    required bool isDecimal,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AbsorbPointer(
        absorbing: widget.esLectura,
        child: TextFormField(
          controller: controller,
          readOnly: widget.esLectura,
          keyboardType: TextInputType.numberWithOptions(decimal: isDecimal),
          inputFormatters: [
            isDecimal
                ? FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
                : FilteringTextInputFormatter.digitsOnly,
          ],
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, color: brandBlue, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            filled: true,
            fillColor: widget.esLectura ? Colors.grey[200] : Colors.grey[50],
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          validator: (v) => v!.isEmpty ? 'Requerido' : null,
        ),
      ),
    );
  }

  Widget _buildHeaderInfo() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: brandBlue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: brandBlue.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: brandBlue,
            child: const Icon(Icons.person, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Responsable",
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
              Text(
                loginController.loggedInUser.value?['nombres'] ?? 'Usuario',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 15, bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          color: brandBlue,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
