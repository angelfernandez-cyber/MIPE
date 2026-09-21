import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:async';
import 'package:file_picker/file_picker.dart';

import 'backup_file_reader.dart';
import 'backup_file_opener.dart';
import 'data_cleanup_service.dart';
import 'login_controller.dart';

class BackupCleanupPage extends StatefulWidget {
  const BackupCleanupPage({super.key});

  @override
  State<BackupCleanupPage> createState() => _BackupCleanupPageState();
}

class _BackupCleanupPageState extends State<BackupCleanupPage> {
  final LoginController loginController = Get.find<LoginController>();
  final TextEditingController confirmationController = TextEditingController();
  bool _working = false;
  String _status = 'El respaldo se crea antes de cualquier eliminación.';
  StorageUsage? _storageUsage;
  String? _storageError;
  bool _storageAlertShown = false;
  Timer? _storageTimer;

  @override
  void dispose() {
    confirmationController.dispose();
    _storageTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadStorageUsage();
    _storageTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadStorageUsage();
    });
  }

  Future<void> _loadStorageUsage() async {
    try {
      final usage = await DataCleanupService.fetchStorageUsage(
        supabaseUrl: loginController.supabaseUrl,
        apiKey: loginController.apiKey,
      );
      if (mounted) {
        setState(() { _storageUsage = usage; _storageError = null; });
        final ratio = usage.ratio;
        if (ratio >= .8 && !_storageAlertShown) {
          _storageAlertShown = true;
          Get.snackbar(
            ratio >= .9 ? 'Almacenamiento casi lleno' : 'Almacenamiento elevado',
            ratio >= .9
                ? 'Supabase está usando más del 90% del límite configurado.'
                : 'Supabase está usando más del 80% del límite configurado.',
            backgroundColor: ratio >= .9 ? const Color(0xFFB42334) : const Color(0xFFB26A00),
            colorText: Colors.white,
            snackPosition: SnackPosition.BOTTOM,
          );
        }
        if (ratio < .8) _storageAlertShown = false;
      }
    } catch (error) {
      if (mounted) setState(() => _storageError = error.toString());
    }
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _backupAndDelete() async {
    if (confirmationController.text.trim().toUpperCase() != 'BORRAR TODO') {
      Get.snackbar('Confirmación incompleta', 'Escribe BORRAR TODO para continuar');
      return;
    }

    setState(() => _working = true);
    try {
      setState(() => _status = 'Creando respaldo de las dos tablas...');
      final backupPath = await DataCleanupService.createBackupAndSave(
        supabaseUrl: loginController.supabaseUrl,
        apiKey: loginController.apiKey,
        onTable: (table) {
          if (mounted) setState(() => _status = 'Respaldando $table...');
        },
      );

      if (!mounted) return;
      final confirmed = await _confirmBackup(backupPath);
      if (confirmed != true) {
        setState(() {
          _working = false;
          _status = 'Respaldo creado. Eliminación cancelada.';
        });
        return;
      }

      setState(() => _status = 'Eliminando información...');
      final count = await DataCleanupService.deleteAll(
        supabaseUrl: loginController.supabaseUrl,
        apiKey: loginController.apiKey,
        onTable: (table) {
          if (mounted) setState(() => _status = 'Eliminando $table...');
        },
      );
      await DataCleanupService.clearLocalCopies();
      if (mounted) {
        setState(() {
          _working = false;
          _status = 'Proceso terminado. Respaldo: $backupPath';
          confirmationController.clear();
        });
        Get.snackbar(
          'Proceso completado',
          'Se limpiaron $count tablas autorizadas: aspersiones y aseguramiento_plaguicidas.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _working = false;
          _status = 'No se eliminó nada: el respaldo o la operación falló.';
        });
        Get.snackbar('Operación detenida', error.toString());
      }
    }
  }

  Future<bool?> _confirmBackup(String backupPath) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Respaldo creado'),
        content: Text(
          'El respaldo está listo en:\n$backupPath\n\n'
          'Solo se eliminarán los registros de estas dos tablas:\n'
          '• aspersiones\n'
          '• aseguramiento_plaguicidas\n\n'
          '¿Deseas continuar?',
        ),
        actions: [
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            runSpacing: 2,
            children: [
              if (!backupPath.startsWith('Descarga iniciada:'))
                TextButton(
                  onPressed: () async {
                    await openBackupFile(backupPath);
                  },
                  child: const Text('Abrir respaldo'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continuar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _restoreBackup() async {
    if (_working) return;

    String? fileName;
    List<int>? bytes;
    final localBackups = await listLocalBackups();

    if (localBackups.isNotEmpty) {
      final selectedPath = await _selectLocalBackup(localBackups);
      if (selectedPath == null) return;
      bytes = await readLocalBackup(selectedPath);
      fileName = _backupFileName(selectedPath);
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null) return;

      final file = result.files.single;
      bytes = file.bytes;
      fileName = file.name;
      if (bytes == null) {
        Get.snackbar(
          'Archivo no disponible',
          'No se pudo leer el respaldo seleccionado.',
        );
        return;
      }
    }

    final confirmed = await _confirmRestore(fileName);
    if (confirmed != true || !mounted) return;

    setState(() {
      _working = true;
      _status = 'Restaurando $fileName...';
    });
    try {
      final restored = await DataCleanupService.restoreBackup(
        bytes: bytes,
        supabaseUrl: loginController.supabaseUrl,
        apiKey: loginController.apiKey,
        onTable: (table) {
          if (mounted) setState(() => _status = 'Restaurando $table...');
        },
      );
      await DataCleanupService.clearLocalCopies();
      if (mounted) {
        setState(() {
          _working = false;
          _status = 'Restauración completada desde $fileName.';
        });
        Get.snackbar('Restauración completada', '$restored registros cargados en Supabase.');
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _working = false;
          _status = 'La restauración no se completó. Revisa el respaldo y Supabase.';
        });
        Get.snackbar('Restauración detenida', error.toString());
      }
    }
  }

  String _backupFileName(String path) {
    return path.split(RegExp(r'[\\/]')).last;
  }

  Future<String?> _selectLocalBackup(List<String> paths) {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Respaldos guardados'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: paths.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final path = paths[index];
              return ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(
                  _backupFileName(path),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: const Text('Guardado en este dispositivo'),
                onTap: () => Navigator.pop(context, path),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmRestore(String fileName) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Restaurar respaldo'),
        content: Text(
          'Archivo: $fileName\n\n'
          'Se reemplazarán los datos actuales de aspersiones y '
          'aseguramiento_plaguicidas por los datos del respaldo.\n\n'
          '¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        title: const Text('Respaldo y limpieza'),
        backgroundColor: const Color(0xFF8B1E2D),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFF2B8C0)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Respaldo',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF7A1725),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildStorageCard(),
          const SizedBox(height: 20),
          TextField(
            controller: confirmationController,
            enabled: !_working,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Escribe BORRAR TODO',
              prefixIcon: Icon(Icons.password_rounded),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _working ? null : _backupAndDelete,
            icon: _working ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.backup_rounded),
            label: Text(
              _working ? 'Procesando...' : 'Respaldar y limpiar 2 tablas',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8B1E2D),
              minimumSize: const Size.fromHeight(48),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'RESTAURACIÓN DE EMERGENCIA',
            style: TextStyle(
              color: Color(0xFF005F86),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Carga un respaldo JSON para recuperar las dos tablas autorizadas.',
            style: TextStyle(color: Colors.blueGrey.shade700, height: 1.3),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _working ? null : _restoreBackup,
            icon: const Icon(Icons.restore_rounded),
            label: const Text('Restaurar información'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              foregroundColor: const Color(0xFF005F86),
              side: const BorderSide(color: Color(0xFF005F86)),
            ),
          ),
          const SizedBox(height: 18),
          Text(_status, style: TextStyle(color: Colors.blueGrey.shade700, height: 1.4)),
        ],
      ),
    );
  }

  Widget _buildStorageCard() {
    final usage = _storageUsage;
    final ratio = usage?.ratio ?? 0;
    final critical = ratio >= .9;
    final warning = ratio >= .8;
    final color = critical ? const Color(0xFFB42334) : warning ? const Color(0xFFB26A00) : const Color(0xFF168B59);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(.22)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: usage == null
          ? Row(children: [Icon(Icons.storage_rounded, color: color), const SizedBox(width: 10), Expanded(child: Text(_storageError == null ? 'Consultando almacenamiento...' : 'No se pudo consultar. Ejecuta storage_usage.sql en Supabase y pulsa actualizar.', style: TextStyle(color: _storageError == null ? null : const Color(0xFFB42334))))])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Icon(critical ? Icons.error_rounded : Icons.storage_rounded, color: color), const SizedBox(width: 10), const Expanded(child: Text('Almacenamiento de Supabase', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))), IconButton(onPressed: _loadStorageUsage, icon: const Icon(Icons.refresh_rounded), tooltip: 'Actualizar')]),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: ratio.clamp(0, 1), minHeight: 9, borderRadius: BorderRadius.circular(8), color: color, backgroundColor: color.withOpacity(.12)),
              const SizedBox(height: 10),
              Text('${_formatBytes(usage.usedBytes)} usados de ${_formatBytes(usage.quotaBytes)}', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Disponible: ${_formatBytes(usage.remainingBytes)}', style: TextStyle(color: Colors.blueGrey.shade700)),
              if (warning) ...[const SizedBox(height: 10), Text(critical ? 'Alerta crítica: el almacenamiento está casi lleno.' : 'Advertencia: el almacenamiento está llegando al límite.', style: TextStyle(color: Color(0xFFB42334), fontWeight: FontWeight.w700))],
            ]),
    );
  }
}