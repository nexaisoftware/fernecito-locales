/// Badge de suscripción con colores por tier (Gratis, Standard, Plus, Premium).
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants.dart';

class EstiloBadgePlanSuscripcion {
  final Color color;
  final Color fondo;
  final Color borde;
  final String etiqueta;
  final bool mostrarIconoVerificado;

  const EstiloBadgePlanSuscripcion({
    required this.color,
    required this.fondo,
    required this.borde,
    required this.etiqueta,
    required this.mostrarIconoVerificado,
  });
}

Color colorPlanSuscripcionUi(String tipoPlan) {
  switch (tipoPlan) {
    case 'Premium':
      return ColoresLocales.mostazaDestacado;
    case 'Plus':
      return const Color(0xFF0891B2);
    case 'Standard':
      return ColoresLocales.acentoVioleta;
    default:
      return ColoresLocales.textoSecundarioOnFondoClaro;
  }
}

String etiquetaSuscripcionCorta(String tipoPlan) {
  switch (tipoPlan) {
    case 'Premium':
      return 'Premium';
    case 'Plus':
      return 'Plus';
    case 'Standard':
      return 'Standard';
    default:
      return 'Gratis';
  }
}

String etiquetaSuscripcionLarga(String tipoPlan) {
  if (tipoPlan == 'Gratuita') return 'Cuenta gratuita';
  return etiquetaSuscripcionCorta(tipoPlan);
}

EstiloBadgePlanSuscripcion estiloBadgePlanSuscripcion(
  String tipoPlan, {
  bool etiquetaLarga = false,
}) {
  final color = colorPlanSuscripcionUi(tipoPlan);
  final esGratis = tipoPlan == 'Gratuita';
  final etiqueta = etiquetaLarga
      ? etiquetaSuscripcionLarga(tipoPlan)
      : etiquetaSuscripcionCorta(tipoPlan);

  if (esGratis) {
    return EstiloBadgePlanSuscripcion(
      color: color,
      fondo: color.withValues(alpha: 0.14),
      borde: color.withValues(alpha: 0.35),
      etiqueta: etiqueta,
      mostrarIconoVerificado: false,
    );
  }

  return EstiloBadgePlanSuscripcion(
    color: color,
    fondo: color.withValues(alpha: 0.16),
    borde: color.withValues(alpha: 0.42),
    etiqueta: etiqueta,
    mostrarIconoVerificado: true,
  );
}

class BadgePlanSuscripcion extends StatelessWidget {
  final String tipoPlan;
  final bool etiquetaLarga;
  final VoidCallback? onTap;

  const BadgePlanSuscripcion({
    super.key,
    required this.tipoPlan,
    this.etiquetaLarga = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final estilo = estiloBadgePlanSuscripcion(tipoPlan, etiquetaLarga: etiquetaLarga);

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: estilo.fondo,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: estilo.borde),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (estilo.mostrarIconoVerificado) ...[
            Icon(
              CupertinoIcons.checkmark_seal_fill,
              size: 13,
              color: estilo.color,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            estilo.etiqueta,
            style: GoogleFonts.baloo2(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: estilo.color,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return badge;

    return GestureDetector(onTap: onTap, child: badge);
  }
}
