/// Badges de etiqueta con contraste fijo (p. ej. «Nuevo» sobre mostaza).
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants.dart';

class BadgeNuevoLocales extends StatelessWidget {
  const BadgeNuevoLocales({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ColoresLocales.mostazaDestacado,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: ColoresLocales.textoSobreMostaza.withValues(alpha: 0.18),
        ),
      ),
      child: Text(
        'Nuevo',
        style: GoogleFonts.baloo2(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: ColoresLocales.textoSobreMostaza,
        ),
      ),
    );
  }
}
