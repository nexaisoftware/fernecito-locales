import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'barra_sistema_stub.dart'
    if (dart.library.js_interop) 'barra_sistema_web.dart' as barra_pwa;

/// Barra de estado / theme-color PWA: negro en oscuro, blanco en claro.
class BarraSistemaLocales {
  BarraSistemaLocales._();

  static const colorOscuro = '#000000';
  static const colorClaro = '#FFFFFF';

  static SystemUiOverlayStyle estilo(bool modoOscuro) {
    return modoOscuro
        ? const SystemUiOverlayStyle(
            statusBarColor: Color(0xFF000000),
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarColor: Color(0xFF000000),
            systemNavigationBarIconBrightness: Brightness.light,
          )
        : const SystemUiOverlayStyle(
            statusBarColor: Color(0xFFFFFFFF),
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
            systemNavigationBarColor: Color(0xFFFFFFFF),
            systemNavigationBarIconBrightness: Brightness.dark,
          );
  }

  /// Misma barra que durante el splash violeta (evita flash al arrancar).
  static const estiloSplash = SystemUiOverlayStyle(
    statusBarColor: Color(0xFF742ED1),
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0xFF742ED1),
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static void aplicar(bool modoOscuro) {
    if (kIsWeb) {
      barra_pwa.actualizarThemeColorPwa(modoOscuro);
    }
    SystemChrome.setSystemUIOverlayStyle(estilo(modoOscuro));
  }
}
