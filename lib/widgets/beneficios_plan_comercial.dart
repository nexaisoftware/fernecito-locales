/// Listado unificado de beneficios para cards comerciales de suscripción.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/constants.dart';

class BeneficioPlanComercial {
  const BeneficioPlanComercial({
    required this.icono,
    required this.color,
    required this.texto,
    this.incluido = true,
  });

  final IconData icono;
  final Color color;
  final String texto;
  final bool incluido;
}

List<BeneficioPlanComercial> beneficiosComercialesPlan(String plan) {
  final incluyeTopCartelera = plan == 'Plus' || plan == 'Premium';
  final incluyeTopUltra = plan == 'Premium';

  String flyers;
  String recomendados;
  switch (plan) {
    case 'Premium':
      flyers = '40 flyers IA';
      recomendados = '12 recomendados';
      break;
    case 'Plus':
      flyers = '20 flyers IA';
      recomendados = '8 recomendados';
      break;
    default:
      flyers = '3 flyers IA';
      recomendados = '4 recomendados';
  }

  return [
    BeneficioPlanComercial(
      icono: CupertinoIcons.checkmark_seal_fill,
      color: ColoresLocales.acentoVioleta,
      texto: 'Insignia verificado de local',
    ),
    BeneficioPlanComercial(
      icono: IconosFeaturesLocales.flyersIa,
      color: ColoresFeaturesLocales.flyersIa,
      texto: flyers,
    ),
    BeneficioPlanComercial(
      icono: IconosFeaturesLocales.recomendadoFernecito,
      color: ColoresFeaturesLocales.recomendadoFernecito,
      texto: recomendados,
    ),
    BeneficioPlanComercial(
      icono: IconosFeaturesLocales.topCartelera,
      color: ColoresFeaturesLocales.topCartelera,
      texto: '2 top cartelera',
      incluido: incluyeTopCartelera,
    ),
    BeneficioPlanComercial(
      icono: IconosFeaturesLocales.topUltra,
      color: ColoresFeaturesLocales.topUltra,
      texto: '2 top ultra',
      incluido: incluyeTopUltra,
    ),
  ];
}
