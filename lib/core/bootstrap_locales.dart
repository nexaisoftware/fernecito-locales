/// Señal de que el home terminó su primera carga (para no mostrar navbar
/// encima del splash).
library;

import 'package:flutter/foundation.dart';

import 'barra_sistema_locales.dart';
import 'tema_app_locales.dart';

class BootstrapLocales {
  BootstrapLocales._();

  static final ValueNotifier<bool> lista = ValueNotifier<bool>(false);

  static void marcarLista() {
    if (lista.value) return;
    lista.value = true;
    BarraSistemaLocales.aplicar(TemaAppLocales.instancia.esOscuro);
  }

  static void reset() {
    lista.value = false;
  }
}
