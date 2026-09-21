Future<List<String>> listLocalBackups() async => <String>[];

Future<List<int>> readLocalBackup(String path) async {
  throw UnsupportedError('La lectura local no está disponible en web.');
}
