/// Guarda imágenes de flyer en galería (nativo) o descarga (web).
library;

export 'guardar_imagen_dispositivo_impl.dart'
    if (dart.library.html) 'guardar_imagen_dispositivo_web.dart';
