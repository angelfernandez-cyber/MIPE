import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<List<String>> listLocalBackups() async {
  final directory = await getApplicationDocumentsDirectory();
  final files = directory
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'))
      .toList();
  files.sort(
    (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
  );
  return files.map((file) => file.path).toList();
}

Future<List<int>> readLocalBackup(String path) async {
  return File(path).readAsBytes();
}
