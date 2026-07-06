/// Snackbars flotantes con margen seguro (bottom nav / safe area).
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants.dart';

class FeedbackLocales {
  FeedbackLocales._();

  static double _margenInferior(BuildContext context, {required bool conNavBar}) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return conNavBar ? bottom + 88 : bottom + 16;
  }

  static void mostrarExito(
    BuildContext context,
    String mensaje, {
    bool conNavBar = true,
  }) {
    _mostrar(
      context,
      mensaje,
      background: const Color(0xFF16A34A),
      colorTexto: ColoresLocales.textoEnBoton,
      conNavBar: conNavBar,
    );
  }

  static void mostrarAdvertencia(
    BuildContext context,
    String mensaje, {
    bool conNavBar = true,
  }) {
    _mostrar(
      context,
      mensaje,
      background: ColoresLocales.mostazaDestacado,
      colorTexto: ColoresLocales.textoSobreMostaza,
      conNavBar: conNavBar,
    );
  }

  static void mostrarError(
    BuildContext context,
    String mensaje, {
    bool conNavBar = true,
  }) {
    _mostrar(
      context,
      mensaje,
      background: const Color(0xFFDC2626),
      colorTexto: ColoresLocales.textoEnBoton,
      conNavBar: conNavBar,
    );
  }

  static void _mostrar(
    BuildContext context,
    String mensaje, {
    required Color background,
    required Color colorTexto,
    required bool conNavBar,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          mensaje,
          style: GoogleFonts.baloo2(
            color: colorTexto,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          _margenInferior(context, conNavBar: conNavBar),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
