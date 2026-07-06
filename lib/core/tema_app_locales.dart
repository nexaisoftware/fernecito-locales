library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'barra_sistema_locales.dart';

/// Servicio de tema claro/oscuro — mismo patrón que [TemaFernecito] en usuarios.
class TemaAppLocales {
  TemaAppLocales._();
  static final TemaAppLocales instancia = TemaAppLocales._();

  static const _prefsKey = 'modo_oscuro_locales';

  final ValueNotifier<bool> modoOscuro = ValueNotifier<bool>(false);

  bool get esOscuro => modoOscuro.value;

  Future<void> cargar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      modoOscuro.value = prefs.getBool(_prefsKey) ?? false;
      BarraSistemaLocales.aplicar(modoOscuro.value);
    } catch (e) {
      debugPrint('⚠️ TemaAppLocales.cargar: $e');
    }
  }

  /// Cambio instantáneo en UI; persistencia en background.
  void establecerModoOscuro(bool value) {
    if (modoOscuro.value == value) return;
    modoOscuro.value = value;
    BarraSistemaLocales.aplicar(value);
    unawaited(_persistir(value));
  }

  void toggle() => establecerModoOscuro(!modoOscuro.value);

  Future<void> _persistir(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (e) {
      debugPrint('⚠️ TemaAppLocales._persistir: $e');
    }
  }
}
