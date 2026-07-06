/// Estado vacío de error reutilizable (icono + mensaje + reintentar).
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants.dart';

class EstadoErrorLocales extends StatelessWidget {
  const EstadoErrorLocales({
    super.key,
    required this.mensaje,
    required this.onReintentar,
    this.titulo = 'No se pudo cargar',
  });

  final String titulo;
  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_circle,
              size: 56,
              color: const Color(0xFFEF4444).withValues(alpha: 0.85),
            ),
            const SizedBox(height: 14),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: GoogleFonts.baloo2(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: ColoresLocales.textoOnFondoClaro,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: GoogleFonts.baloo2(
                fontSize: 13,
                color: ColoresLocales.textoSecundarioOnFondoClaro,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            CupertinoButton(
              color: ColoresLocales.botonVioletaFondo,
              borderRadius: BorderRadius.circular(50),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              onPressed: onReintentar,
              child: Text(
                'Reintentar',
                style: GoogleFonts.baloo2(
                  fontWeight: FontWeight.w800,
                  color: ColoresLocales.botonVioletaTexto,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
