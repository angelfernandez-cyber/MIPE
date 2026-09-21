import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String> saveBackupBytes(List<int> bytes, String fileName) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}