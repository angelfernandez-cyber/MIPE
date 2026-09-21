import 'dart:html' as html;
import 'dart:typed_data';

Future<String> saveBackupBytes(List<int> bytes, String fileName) async {
  final blob = html.Blob(<dynamic>[Uint8List.fromList(bytes)], 'application/json');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
  return 'Descarga iniciada: $fileName\nRevisa la carpeta Descargas del navegador.';
}