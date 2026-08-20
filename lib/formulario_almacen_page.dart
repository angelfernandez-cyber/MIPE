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
  final _presentacionController = TextEditingController(); // Unidad de medida (Texto)
  final _unidadesController = TextEditingController(); // Total unidades (Int)
  final _loteController = TextEditingController(); // # Lote (Texto)
  final _vencimientoController = TextEditingController(); // Fecha (Texto/Date)
  final _cantidadController = TextEditingController(); // Cantidad cc/g (Numeric)
  final _colorController = TextEditingController(); // Color (Texto)
  final _phController = TextEditingController(); // pH (Numeric)
  final _densidadController = TextEditingController(); // Densidad (Numeric)
  final _obsController = TextEditingController(); // Observaciones (Texto)
  final _aseguraController = TextEditingController();
  final _autorizaController = TextEditingController();

  // --- campo para que el usuario escriba porcentaje (ej: "100" o "100%") ---
  final _cumplimientoController = TextEditingController();

  // --- ESTADOS BOTONES SELECCIÓN ---
  String _estadoEtiqueta = 'CUMPLE';
  String _estadoTapa = 'CUMPLE';
  String _sellos = 'CUMPLE';
  String _puntosextraccion = 'CUMPLE';

  // --- cumplimiento textual (solo UI) ---
  String _cumplimiento = 'CUMPLE'; // valores: 'CUMPLE' | 'NO CUMPLE'

  @override
  void initState() {
    super.initState();
    // Si recibimos datos, llenamos los controladores
    if (widget.dataInicial != null) {
      _semanaController.text = widget.dataInicial!['semana']?.toString() ?? '';
      _productoController.text = widget.dataInicial!['nombre_producto'] ?? '';
      _proveedorController.text = widget.dataInicial!['proveedor'] ?? '';
      _presentacionController.text = widget.dataInicial!['presentacion'] ?? '';
      _unidadesController.text = widget.dataInicial!['total_unidades']?.toString() ?? '';
      _loteController.text = widget.dataInicial!['lote'] ?? '';
      _vencimientoController.text = widget.dataInicial!['fecha_vencimiento'] ?? '';
      _cantidadController.text = widget.dataInicial!['cantidad_cc_g']?.toString() ?? '';
      _colorController.text = widget.dataInicial!['color'] ?? '';
      _phController.text = widget.dataInicial!['ph']?.toString() ?? '';
      _densidadController.text = widget.dataInicial!['densidad']?.toString() ?? '';
      _obsController.text = widget.dataInicial!['observaciones'] ?? '';
      _aseguraController.text = widget.dataInicial?['identificacion_asegura'] ?? '';
      _autorizaController.text = widget.dataInicial?['autorizacion'] ?? '';

      // Si viene cumplimiento (texto con % o sin) en los datos, mostrarlo en el controlador
      if (widget.dataInicial!['cumplimiento'] != null) {
        _cumplimientoController.text = widget.dataInicial!['cumplimiento'].toString();
      } else if (widget.dataInicial!['cumplimiento_pct'] != null) {
        // fallback: si solo existe cumplimiento_pct (texto), mostrarlo con %
        final raw = widget.dataInicial!['cumplimiento_pct'].toString().trim();
        if (raw.isNotEmpty) {
          _cumplimientoController.text = raw.endsWith('%') ? raw : '$raw%';
        }
      }

      // Actualizamos los estados de los botones
      _estadoEtiqueta = widget.dataInicial!['estado_etiqueta'] ?? 'CUMPLE';
      _estadoTapa = widget.dataInicial!['estado_tapa'] ?? 'CUMPLE';
      _sellos = widget.dataInicial!['sellos'] ?? 'CUMPLE';
      _puntosextraccion = widget.dataInicial!['puntos_extraccion'] ?? 'CUMPLE';

      // Cumplimiento textual: si viene 'NO CUMPLE' lo respetamos, cualquier otro valor lo tratamos como 'CUMPLE'
      final incomingCumpl = (widget.dataInicial!['cumplimiento'] ?? '').toString().toUpperCase();
      _cumplimiento = incomingCumpl == 'NO CUMPLE' ? 'NO CUMPLE' : 'CUMPLE';
    }
  }

  @override
  void dispose() {
    _semanaController.dispose();
    _productoController.dispose();
    _proveedorController.dispose();
    _presentacionController.dispose();
    _unidadesController.dispose();
    _loteController.dispose();
    _vencimientoController.dispose();
    _cantidadController.dispose();
    _colorController.dispose();
    _phController.dispose();
    _densidadController.dispose();
    _obsController.dispose();
    _aseguraController.dispose();
    _autorizaController.dispose();
    _cumplimientoController.dispose();
    super.dispose();
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

  // Normaliza entradas como "100", "100%", " 75% ", "75.5" -> texto con porcentaje "100%"
  String? _normalizePctText(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    final cleaned = s.endsWith('%') ? s.substring(0, s.length - 1).trim() : s;
    final int? asInt = int.tryParse(cleaned);
    if (asInt != null) {
      final int clamped = asInt < 0 ? 0 : (asInt > 100 ? 100 : asInt);
      return '$clamped%';
    }
    final double? asDouble = double.tryParse(cleaned.replaceAll(',', '.'));
    if (asDouble == null) return null;
    final int rounded = asDouble.round();
    final int clamped = rounded < 0 ? 0 : (rounded > 100 ? 100 : rounded);
    return '$clamped%';
  }

  Future<void> _guardarEnBaseDeDatos() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      // Helper local para convertir a mayúsculas y devolver null si vacío
      String? up(String? s) {
        if (s == null) return null;
        final t = s.trim();
        return t.isEmpty ? null : t.toUpperCase();
      }

      // Normalizar cumplimiento como texto con % (si el usuario escribió algo)
      final String? cumplimientoTexto = _normalizePctText(
        _cumplimientoController.text.isNotEmpty
            ? _cumplimientoController.text
            : (_cumplimiento == 'CUMPLE' ? '100' : '0'),
      );

      // Determinar valor final a guardar en la columna 'cumplimiento'
      String? cumplimientoToSave;
      if (cumplimientoTexto != null) {
        cumplimientoToSave = cumplimientoTexto; // e.g. "100%"
      } else {
        // fallback: si por alguna razón no hay texto, usar selector
        cumplimientoToSave = _cumplimiento == 'NO CUMPLE' ? '0%' : '100%';
      }

      // Campos numéricos y fecha se mantienen igual; los textos se pasan por up(...)
      final Map<String, dynamic> body = {
        'semana': int.tryParse(_semanaController.text),

        // Fecha del registro (se guarda en formato ISO yyyy-MM-dd)
        'fecha': DateFormat('yyyy-MM-dd').format(DateTime.now()),

        // Campos de texto convertidos a MAYÚSCULAS
        'nombre_producto': up(_productoController.text),
        'proveedor': up(_proveedorController.text),

        'presentacion': up(_presentacionController.text),
        'total_unidades': int.tryParse(_unidadesController.text) ?? 0,

        'lote': up(_loteController.text),
        'fecha_vencimiento': _vencimientoController.text.isEmpty ? null : _vencimientoController.text,

        // Estados ya vienen en mayúsculas (CUMPLE / NO CUMPLE)
        'estado_etiqueta': _estadoEtiqueta,
        'estado_tapa': _estadoTapa,
        'sellos': _sellos,
        'puntos_extraccion': _puntosextraccion,

        // Guardar el texto con porcentaje en la columna 'cumplimiento'
        'cumplimiento': cumplimientoToSave,

        // Campos numéricos
        // cantidad como entero (si está vacío queda 0)
        'cantidad_cc_g': int.tryParse(_cantidadController.text) ?? 0,
        'color': up(_colorController.text) ?? "NO DEFINIDO",

        // ph y densidad NO obligatorios: si están vacíos se envía null
        'ph': _phController.text.trim().isEmpty
            ? null
            : (int.tryParse(_phController.text) ?? (double.tryParse(_phController.text)?.round())),
        'densidad': _densidadController.text.trim().isEmpty
            ? null
            : (double.tryParse(_densidadController.text) ?? null),

        'observaciones': up(_obsController.text),
        'autorizacion': up(_autorizaController.text),

        'identificacion_asegura': up(_aseguraController.text),
      };

      final url = Uri.parse('${loginController.supabaseUrl}/rest/v1/aseguramiento_plaguicidas');

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

        // Limpiar formulario
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
        _cumplimientoController.clear();

        setState(() {
          _estadoEtiqueta = 'CUMPLE';
          _estadoTapa = 'CUMPLE';
          _sellos = 'CUMPLE';
          _puntosextraccion = 'CUMPLE';
          _cumplimiento = 'CUMPLE';
        });
      } else {
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

              // selector de cumplimiento textual (solo UI)
              _sectionTitle("CUMPLIMIENTO"),
              _buildCumplimientoSelector(),

              // campo donde el usuario puede escribir porcentaje "100" o "100%"
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AbsorbPointer(
                  absorbing: widget.esLectura,
                  child: TextFormField(
                    controller: _cumplimientoController,
                    keyboardType: TextInputType.text,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^[0-9%\s.,-]*$')),
                    ],
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Cumplimiento (%) - escribe 100 o 100%',
                      prefixIcon: Icon(Icons.percent, color: brandBlue, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: widget.esLectura ? Colors.grey[200] : Colors.grey[50],
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null; // opcional
                      final normalized = _normalizePctText(v);
                      if (normalized == null) return 'Ingrese un porcentaje válido 0-100';
                      return null;
                    },
                  ),
                ),
              ),

              _sectionTitle("ANÁLISIS FÍSICO-QUÍMICO"),
              Row(
                children: [
                  Expanded(
                    child: _buildNumberInput(
                      _cantidadController,
                      'Cantidad cc/g',
                      Icons.scale,
                      isDecimal: false, // Entero para gramajes exactos
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      _colorController,
                      'Color',
                      Icons.colorize,
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
                      requiredField: false, // ahora opcional
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildNumberInput(
                      _densidadController,
                      'Densidad',
                      Icons.shutter_speed,
                      isDecimal: true,
                      requiredField: false, // ahora opcional
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
              if (!widget.esLectura) // Solo muestra el botón si NO es modo lectura
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

  Widget _buildCumplimientoSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        AbsorbPointer(
          absorbing: widget.esLectura,
          child: Row(
            children: [
              Expanded(child: _optionButton("CUMPLE", _cumplimiento == "CUMPLE", brandGreen, () {
                setState(() {
                  _cumplimiento = "CUMPLE";
                  // si el usuario usa el selector, también actualizamos el campo de texto a 100%
                  _cumplimientoController.text = '100%';
                });
              })),
              const SizedBox(width: 10),
              Expanded(child: _optionButton("NO CUMPLE", _cumplimiento == "NO CUMPLE", Colors.redAccent, () {
                setState(() {
                  _cumplimiento = "NO CUMPLE";
                  _cumplimientoController.text = '0%';
                });
              })),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

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

  // Versión actualizada: acepta requiredField para hacer el campo opcional
  Widget _buildNumberInput(
    TextEditingController controller,
    String label,
    IconData icon, {
    required bool isDecimal,
    bool requiredField = true, // nuevo parámetro: por defecto obligatorio
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
          validator: (v) {
            if (!requiredField) return null; // no es obligatorio
            return (v == null || v.isEmpty) ? 'Requerido' : null;
          },
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
