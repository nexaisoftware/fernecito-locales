import 'dart:io';
import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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
    if (localPath.isNotEmpty) {
      final file = File(localPath);
      if (await file.exists()) {
        return file.readAsBytes();
      }
    }
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

  /// Guarda la imagen en la galería del dispositivo (Android / iOS).
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

      final dir = await getTemporaryDirectory();
      final slug = _slug(titulo);
      final pieza = (etiquetaPieza ?? 'flyer')
          .toLowerCase()
          .replaceAll(' ', '_');
      final tmp = File('${dir.path}/${slug}_$pieza.jpg');
      await tmp.writeAsBytes(bytes);

      await Gal.putImage(tmp.path, album: 'Fernecito');
      return GuardarImagenResultado.exito('Guardado en tu galería');
    } on GalException catch (e) {
      final msg = e.type.message;
      return GuardarImagenResultado.error(
        msg.isNotEmpty ? msg : 'No se pudo guardar en la galería',
      );
    } catch (_) {
      return GuardarImagenResultado.error('Error al guardar la imagen');
    }
  }
}
