import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

Future<String> saveExcelBytes(List<int> bytes, String fileName) async {
  Directory? directory;
  try {
    directory = await getExternalStorageDirectory();
  } catch (_) {
    directory = null;
  }
  directory ??= await getApplicationDocumentsDirectory();

  final fullPath = '${directory.path}/$fileName';
  final file = File(fullPath);
  await file.writeAsBytes(bytes, flush: true);
  try {
    await OpenFilex.open(fullPath);
  } catch (_) {}
  return fullPath;
}