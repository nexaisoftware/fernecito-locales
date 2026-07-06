import 'dart:html' as html;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Resultado al intentar guardar una imagen en el dispositivo.
class GuardarImagenResultado {
  const GuardarImagenResultado._({
    required this.ok,
    this.mensaje,
  });

  final bool ok;
  final String? mensaje;

  factory GuardarImagenResultado.exito([String? mensaje]) =>
      GuardarImagenResultado._(ok: true, mensaje: mensaje);

  factory GuardarImagenResultado.error(String mensaje) =>
      GuardarImagenResultado._(ok: false, mensaje: mensaje);
}

class GuardarImagenDispositivo {
  GuardarImagenDispositivo._();

  static Future<Uint8List?> _obtenerBytes({
    required String localPath,
    required String remoteUrl,
  }) async {
    if (remoteUrl.isEmpty) return null;
    final resp = await http
        .get(Uri.parse(remoteUrl))
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) return null;
    return resp.bodyBytes;
  }

  static String _slug(String titulo) {
    final s = titulo
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return s.isEmpty ? 'flyer_fernecito' : s;
  }

  /// En web/PWA dispara una descarga real del archivo JPEG.
  static Future<GuardarImagenResultado> guardar({
    required String localPath,
    required String remoteUrl,
    required String titulo,
    String? etiquetaPieza,
  }) async {
    try {
      final bytes = await _obtenerBytes(
        localPath: localPath,
        remoteUrl: remoteUrl,
      );
      if (bytes == null) {
        return GuardarImagenResultado.error('Imagen no disponible');
      }

      final slug = _slug(titulo);
      final pieza = (etiquetaPieza ?? 'flyer')
          .toLowerCase()
          .replaceAll(' ', '_');
      final blob = html.Blob([bytes], 'image/jpeg');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', '${slug}_$pieza.jpg')
        ..click();
      html.Url.revokeObjectUrl(url);

      return GuardarImagenResultado.exito('Descarga iniciada');
    } catch (_) {
      return GuardarImagenResultado.error('Error al descargar la imagen');
    }
  }
}
