library;

import 'package:flutter/material.dart';

import 'constants.dart';
import 'modo_app_locales.dart';
import 'tema_app_locales.dart';

/// Paleta staff — alineada con dark mode de locales (negro OLED + cards grises).
class ColoresStaff {
  static bool get ahorroEnergia =>
      ModoAppLocales.instancia.esStaff && TemaAppLocales.instancia.esOscuro;

  static bool get usarDegradado =>
      !TemaAppLocales.instancia.esOscuro && !ahorroEnergia;

  static Color get fondo => ColoresLocales.fondoClaro;

  static Color get fondoFormulario => ColoresLocales.fondoFormulario;

  static Color get card => ColoresLocales.superficie;

  static Color get cardElevada => ColoresLocales.superficieElevada;

  static Color get cardLavanda => ColoresLocales.cardLavanda;

  static Color get rellenoInput => ColoresLocales.rellenoInput;

  static Color get separador => ColoresLocales.separador;

  static Color get bordeSuave => ColoresLocales.bordeSuave;

  static Color get sombraCard => ColoresLocales.sombraCard;

  static Color get textoPrincipal => ColoresLocales.textoOnFondoClaro;

  static Color get textoSecundario =>
      ColoresLocales.textoSecundarioOnFondoClaro;

  static Color get chipInactivo => ColoresLocales.chipInactivo;

  static Color get progressTrack =>
      TemaAppLocales.instancia.esOscuro
          ? const Color(0xFF1A1A1A)
          : const Color(0xFFE9E0FF);

  static Color get acento => ColoresLocales.acentoVioleta;
}
