import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

Future<String> saveExcelBytes(List<int> bytes, String fileName) async {
  final blob = html.Blob(<dynamic>[Uint8List.fromList(bytes)],
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..style.display = 'none';

  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  unawaited(Future<void>.delayed(const Duration(seconds: 1), () {
    html.Url.revokeObjectUrl(url);
  }));
  return 'Descarga iniciada: $fileName';
}