import 'dart:js_interop';

@JS('fernecitoActualizarThemeColor')
external void _fernecitoActualizarThemeColor(JSBoolean oscuro);

void actualizarThemeColorPwa(bool modoOscuro) {
  _fernecitoActualizarThemeColor(modoOscuro.toJS);
}
