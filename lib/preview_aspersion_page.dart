import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class PreviewAspersionPage extends StatelessWidget {
  final String bloque;
  final List<dynamic> registros;

  const PreviewAspersionPage({
    super.key,
    required this.bloque,
    required this.registros,
  });

  static const Color brandBlue = Color(0xFF008DC5);
  static const Color darkBlue = Color(0xFF005F86);

  DateTime? _fechaRegistro(dynamic registro) {
    return DateTime.tryParse(registro['fecha_registro']?.toString() ?? '')
        ?.toLocal();
  }

  DateTime _inicioDeSemana(DateTime fecha) {
    final dia = DateTime(fecha.year, fecha.month, fecha.day);
    return dia.subtract(Duration(days: dia.weekday - 1));
  }

  int _numeroSemanaISO(DateTime fecha) {
    final jueves = DateTime(
      fecha.year,
      fecha.month,
      fecha.day,
    ).add(Duration(days: 4 - fecha.weekday));
    final inicioPrimeraSemana = _inicioDeSemana(DateTime(jueves.year, 1, 4));
    return (jueves.difference(inicioPrimeraSemana).inDays ~/ 7) + 1;
  }

  List<dynamic> _registrosDeLaSemana() {
    if (registros.isEmpty) return [];

    final fechaReferencia = _fechaRegistro(registros.first);
    if (fechaReferencia == null) {
      final semana = registros.first['semana']?.toString().trim();
      if (semana == null || semana.isEmpty) return [registros.first];
      return registros
          .where((registro) =>
              registro['semana']?.toString().trim() == semana)
          .toList();
    }

    return registros
        .where((registro) {
          final fecha = _fechaRegistro(registro);
          return fecha != null &&
              _inicioDeSemana(fecha) == _inicioDeSemana(fechaReferencia);
        })
        .toList();
  }

  List<Map<String, dynamic>> _productos(dynamic value) {
    if (value == null) return [];
    try {
      if (value is String) {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
        }
      }
      if (value is List) {
        return value
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  List<String> _lista(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.map((item) => item.toString()).toList();
    return value
        .toString()
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String _texto(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '-' : text;
  }

  String _fecha(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return parsed == null ? _texto(value) : DateFormat('dd/MM/yyyy').format(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final semanaRegistros = _registrosDeLaSemana();
    final fechaReferencia = semanaRegistros.isNotEmpty
      ? _fechaRegistro(semanaRegistros.first)
      : null;
    final semana = fechaReferencia == null
      ? '-'
      : _numeroSemanaISO(fechaReferencia).toString();
    final inicioSemana = fechaReferencia == null
      ? null
      : _inicioDeSemana(fechaReferencia);
    final finSemana = inicioSemana?.add(const Duration(days: 6));

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F8),
      appBar: AppBar(
        backgroundColor: darkBlue,
        foregroundColor: Colors.white,
        title: Text('PLANTILLA · BLOQUE $bloque'),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Text(
                'SEM. $semana',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: semanaRegistros.isEmpty
          ? const Center(child: Text('No hay registros para mostrar.'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 28),
              children: [
                _encabezado(
                  semanaRegistros.first,
                  semana,
                  inicioSemana,
                  finSemana,
                  semanaRegistros.length,
                ),
                const SizedBox(height: 12),
                ...semanaRegistros.asMap().entries.map(
                  (entry) => _registro(entry.value, entry.key + 1),
                ),
              ],
            ),
    );
  }

  Widget _encabezado(
    Map<String, dynamic> registro,
    String semana,
    DateTime? inicioSemana,
    DateTime? finSemana,
    int cantidadRegistros,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [brandBlue, darkBlue]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CONTROL DE ASPERSIONES',
            style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Text(
            'Bloque $bloque  ·  Semana $semana',
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
          ),
          if (inicioSemana != null && finSemana != null) ...[
            const SizedBox(height: 4),
            Text(
              '${DateFormat('dd/MM').format(inicioSemana)} - ${DateFormat('dd/MM/yyyy').format(finSemana)}  ·  $cantidadRegistros registros',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _datoClaro('Jefe MIPE', registro['jefe_mipe']),
              _datoClaro('Bombero', registro['bombero']),
            ],
          ),
        ],
      ),
    );
  }

  Widget _datoClaro(String label, dynamic value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(color: Colors.white60, fontSize: 9)),
        Text(_texto(value), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _registro(dynamic raw, int numero) {
    final registro = Map<String, dynamic>.from(raw as Map);
    final fechaRegistro = _fechaRegistro(registro);
    final semanaCalendario = fechaRegistro == null
      ? '-'
      : _numeroSemanaISO(fechaRegistro).toString();
    final productos = _productos(registro['producto']);
    final dosis = _lista(registro['dosis']);
    final cat = _lista(registro['cat_toxic']);
    final blancos = _lista(registro['blanco_biologico']);
    final fumigadores = _lista(registro['grupo_fumigadores']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: brandBlue.withOpacity(.18)),
        boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: brandBlue,
                child: Text('$numero', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Text(_fecha(registro['fecha_registro']), style: const TextStyle(fontWeight: FontWeight.w800, color: darkBlue)),
              const SizedBox(width: 8),
              Text(
                'SEM. $semanaCalendario',
                style: const TextStyle(color: brandBlue, fontSize: 10, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              Text(_texto(registro['dias']), style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w600)),
            ],
          ),
          const Divider(height: 22),
          _filaDatos([
            ['Temperatura', registro['temperatura']],
            ['Humedad', registro['humedad_relativa']],
            ['Tipo', registro['tipo_aplicacion']],
            ['Dirección', registro['direccion']],
          ]),
          const SizedBox(height: 12),
          if (productos.isNotEmpty)
            ...productos.asMap().entries.map((entry) {
              final index = entry.key;
              final producto = entry.value;
              return _producto(
                producto,
                index < dosis.length ? dosis[index] : null,
                index < cat.length ? cat[index] : null,
                index < blancos.length ? blancos[index] : null,
              );
            })
          else
            _campo('Producto', registro['producto']),
          const SizedBox(height: 8),
          _filaDatos([
            ['Vol. cama', registro['volumen_cama']],
            ['No. camas', registro['num_camas']],
            ['Equipo', registro['equipo']],
            ['I.R.E.', registro['ire_horas']],
          ]),
          if (fumigadores.isNotEmpty) ...[
            const SizedBox(height: 10),
            _campo('Grupos fumigadores', fumigadores.join('  ·  ')),
          ],
          const SizedBox(height: 10),
          _filaDatos([
            ['Facilitador MIPE', registro['facilitador_mipe']],
            ['Facilitador bloque', registro['facilitador_bloque']],
          ]),
        ],
      ),
    );
  }

  Widget _producto(Map<String, dynamic> producto, dynamic dosis, dynamic cat, dynamic blanco) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFEAF6FB), borderRadius: BorderRadius.circular(10)),
      child: _filaDatos([
        ['Producto', producto['producto']],
        ['Dosis', dosis ?? producto['dosis']],
        ['Cat. tóxico', cat ?? producto['cat_toxic']],
        ['Blanco biológico', blanco ?? producto['blanco_biologico']],
      ]),
    );
  }

  Widget _filaDatos(List<List<dynamic>> datos) {
    return Wrap(
      spacing: 18,
      runSpacing: 12,
      children: datos.map((dato) => _campo(dato[0].toString(), dato[1])).toList(),
    );
  }

  Widget _campo(String label, dynamic value) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 125, maxWidth: 260),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: TextStyle(color: Colors.grey[600], fontSize: 9, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(_texto(value), style: const TextStyle(color: Color(0xFF263238), fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
