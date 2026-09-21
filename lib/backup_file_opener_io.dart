import 'package:open_filex/open_filex.dart';

Future<void> openBackupFile(String path) async {
  await OpenFilex.open(path);
}
