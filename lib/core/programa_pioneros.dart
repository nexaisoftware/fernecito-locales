library;

import 'package:flutter/material.dart';

/// Constantes visuales y copy del Programa Pioneros.
class ProgramaPioneros {
  ProgramaPioneros._();

  static const dorado = Color(0xFFE0B800);
  static const doradoOscuro = Color(0xFFB8860B);
  static const verdeInvitacion = Color(0xFF16A34A);

  static const beneficios = <String>[
    'Verificado dorado de por vida',
    'Badge Best Choice en tu ciudad',
    '4 meses Premium gratis + 8 meses Plus',
    'Soporte preferencial',
  ];

  static const tituloInvitacion = '¿Te invitaron al Programa Pioneros?';
  static const subtituloInvitacion =
      'Introducí tu código Pioneros para activar tu cuenta.';

  static String mensajeCompartir({
    required String codigo,
    String? nombreLocal,
  }) {
    final saludo = nombreLocal != null && nombreLocal.trim().isNotEmpty
        ? '¡$nombreLocal, fuiste seleccionado'
        : '¡Fuiste seleccionado';
    return '$saludo para el Programa Pioneros de Fernecito!\n\n'
        'Canjeá tu código en la app Locales → Administrar suscripciones → '
        '“Programa Pioneros”.\n\n'
        'Tu código: $codigo\n\n'
        'https://applocales.fernecitoapp.com';
  }

  static String badgeBestChoice(String? ciudad) {
    final c = (ciudad ?? '').trim();
    if (c.isEmpty) return 'Best Choice';
    return 'Best Choice · $c';
  }

  static const mesesPremiumRegalo = 4;
  static const mesesPlusRegalo = 8;

  static bool enFasePremiumBeneficios({
    required bool beneficiosActivos,
    required int? mesBeneficio,
  }) =>
      beneficiosActivos &&
      mesBeneficio != null &&
      mesBeneficio >= 1 &&
      mesBeneficio <= mesesPremiumRegalo;

  static bool enFasePlusBeneficios({
    required bool beneficiosActivos,
    required int? mesBeneficio,
  }) =>
      beneficiosActivos &&
      mesBeneficio != null &&
      mesBeneficio > mesesPremiumRegalo &&
      mesBeneficio <= mesesPremiumRegalo + mesesPlusRegalo;

  /// Etiqueta de plan de suscripción (independiente del estado Pionero).
  static String etiquetaPlanSuscripcion(String tipoPlan) {
    if (tipoPlan == 'Gratuita') return 'Gratis';
    return tipoPlan;
  }

  /// Plan de créditos regalado según el mes del programa (1–12).
  static String planRegaloPorMes(int mes) {
    if (mes >= 1 && mes <= mesesPremiumRegalo) return 'Premium';
    if (mes > mesesPremiumRegalo && mes <= mesesPremiumRegalo + mesesPlusRegalo) {
      return 'Plus';
    }
    return 'Standard';
  }

  /// Contadores restantes/total que bajan mes a mes (4/4 → 0/4, 8/8 → 0/8).
  static ({int premiumRestantes, int plusRestantes}) contadoresBeneficios({
    required int? mesBeneficio,
    required bool beneficiosActivos,
  }) {
    if (!beneficiosActivos || mesBeneficio == null || mesBeneficio < 1) {
      return (premiumRestantes: 0, plusRestantes: 0);
    }
    final mes = mesBeneficio.clamp(1, mesesPremiumRegalo + mesesPlusRegalo);
    final premiumRestantes =
        mes <= mesesPremiumRegalo ? mesesPremiumRegalo - (mes - 1) : 0;
    final plusRestantes = mes <= mesesPremiumRegalo
        ? mesesPlusRegalo
        : (mes <= mesesPremiumRegalo + mesesPlusRegalo
            ? mesesPlusRegalo - (mes - mesesPremiumRegalo - 1)
            : 0);
    return (premiumRestantes: premiumRestantes, plusRestantes: plusRestantes);
  }

  static DateTime sumarMeses(DateTime fecha, int meses) {
    final targetMonth = fecha.month + meses;
    final yearOffset = (targetMonth - 1) ~/ 12;
    final month = ((targetMonth - 1) % 12) + 1;
    final year = fecha.year + yearOffset;
    final ultimoDia = DateTime(year, month + 1, 0).day;
    final dia = fecha.day > ultimoDia ? ultimoDia : fecha.day;
    return DateTime(
      year,
      month,
      dia,
      fecha.hour,
      fecha.minute,
      fecha.second,
      fecha.millisecond,
      fecha.microsecond,
    );
  }

  /// Fin del tramo Premium regalo (4 meses desde el canje).
  static DateTime? finPremiumRegaloDesdeInicio(DateTime? beneficiosInicio) {
    if (beneficiosInicio == null) return null;
    return sumarMeses(beneficiosInicio, mesesPremiumRegalo);
  }

  /// Fin del programa regalo (12 meses desde el canje).
  static DateTime? finProgramaRegaloDesdeInicio(DateTime? beneficiosInicio) {
    if (beneficiosInicio == null) return null;
    return sumarMeses(beneficiosInicio, mesesPremiumRegalo + mesesPlusRegalo);
  }

  /// Resuelve inicio del programa (canje). Prioriza columnas reales de la DB.
  static DateTime? resolverInicioBeneficios({
    DateTime? beneficiosInicio,
    DateTime? canjeadoEn,
    DateTime? beneficiosFin,
  }) {
    if (beneficiosInicio != null) return beneficiosInicio;
    if (canjeadoEn != null) return canjeadoEn;
    if (beneficiosFin != null) {
      return sumarMeses(beneficiosFin, -(mesesPremiumRegalo + mesesPlusRegalo));
    }
    return null;
  }

  /// Fecha y etiqueta para cards: tramo Premium (4 meses) o programa completo (1 año).
  static ({DateTime? fecha, String etiqueta}) vencimientoUiBeneficios({
    required int? mesBeneficio,
    DateTime? beneficiosInicio,
    DateTime? canjeadoEn,
    DateTime? beneficiosFin,
  }) {
    final inicio = resolverInicioBeneficios(
      beneficiosInicio: beneficiosInicio,
      canjeadoEn: canjeadoEn,
      beneficiosFin: beneficiosFin,
    );
    if (inicio == null) {
      return (fecha: beneficiosFin, etiqueta: 'Plus GRATIS hasta:');
    }

    final finPremium = finPremiumRegaloDesdeInicio(inicio)!;
    final finPrograma =
        finProgramaRegaloDesdeInicio(inicio) ?? beneficiosFin;
    final mes = mesBeneficio ?? 1;

    if (mes >= 1 && mes <= mesesPremiumRegalo) {
      return (fecha: finPremium, etiqueta: 'Premium GRATIS hasta:');
    }
    return (fecha: finPrograma, etiqueta: 'Plus GRATIS hasta:');
  }

  /// Días hasta el fin del tramo gratis visible (Premium 4m o Plus 12m), no el ciclo mensual.
  static int? diasHastaFinBeneficioGratis({
    required bool beneficiosActivos,
    required int? mesBeneficio,
    DateTime? beneficiosInicio,
    DateTime? canjeadoEn,
    DateTime? beneficiosFin,
  }) {
    if (!beneficiosActivos) return null;
    final fin = vencimientoUiBeneficios(
      mesBeneficio: mesBeneficio,
      beneficiosInicio: beneficiosInicio,
      canjeadoEn: canjeadoEn,
      beneficiosFin: beneficiosFin,
    ).fecha;
    if (fin == null) return null;
    final diff = fin.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return diff.inDays;
  }

  static ({int meses, int dias}) _mesesYDiasHasta(DateTime fin) {
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final finDia = DateTime(fin.year, fin.month, fin.day);
    if (!finDia.isAfter(hoy)) return (meses: 0, dias: 0);

    var meses = (finDia.year - hoy.year) * 12 + (finDia.month - hoy.month);
    var dias = finDia.day - hoy.day;
    if (dias < 0) {
      meses--;
      dias += DateTime(finDia.year, finDia.month, 0).day;
    }
    return (meses: meses, dias: dias);
  }

  static String _plural(int n, String singular, String plural) =>
      n == 1 ? singular : plural;

  /// Texto del chip: "3 meses y 12 días restantes".
  static String etiquetaTiempoRestanteBeneficio(DateTime? fin) {
    if (fin == null) return '';
    final partes = _mesesYDiasHasta(fin);
    if (partes.meses == 0 && partes.dias == 0) return 'Vence hoy';
    if (partes.meses == 0 && partes.dias == 1) return 'Vence mañana';
    if (partes.meses == 0) {
      return '${partes.dias} ${_plural(partes.dias, 'día', 'días')} restantes';
    }
    if (partes.dias == 0) {
      return '${partes.meses} ${_plural(partes.meses, 'mes', 'meses')} restantes';
    }
    return '${partes.meses} ${_plural(partes.meses, 'mes', 'meses')} y '
        '${partes.dias} ${_plural(partes.dias, 'día', 'días')} restantes';
  }

  static int _rankPlan(String plan) {
    final p = plan.trim().toLowerCase();
    if (p.contains('premium')) return 3;
    if (p.contains('plus')) return 2;
    if (p.contains('standard') || p.contains('estandar')) return 1;
    return 0;
  }

  /// Premium pagado vigente (upgrade manual durante regalo Pionero).
  static bool premiumPagoActivo({
    required String? planRaw,
    required DateTime? fechaVencimiento,
    DateTime? ahora,
  }) {
    final raw = (planRaw ?? '').trim().toLowerCase();
    if (!raw.contains('premium')) return false;
    final venc = fechaVencimiento;
    if (venc == null) return false;
    return venc.isAfter(ahora ?? DateTime.now());
  }

  /// Chip fase Plus regalo: meses del programa que faltan (no el ciclo de 30 días).
  static String etiquetaMesesPlusRegaloRestantes(int plusRestantes) {
    if (plusRestantes <= 0) return 'Plus regalo por terminar';
    if (plusRestantes == 1) return '1 mes restante';
    return '$plusRestantes meses restantes';
  }

  /// Contexto para bloqueos de pago / renovación manual en cuentas Pionero.
  static PioneroReglasSuscripcion reglas({
    required bool esPionero,
    required bool beneficiosActivos,
    required int? mesBeneficio,
    required String planActual,
    bool premiumPagoActivo = false,
  }) {
    return PioneroReglasSuscripcion(
      esPionero: esPionero,
      beneficiosActivos: beneficiosActivos,
      mesBeneficio: mesBeneficio,
      planActual: planActual,
      premiumPagoActivo: premiumPagoActivo,
    );
  }
}

/// Qué puede hacer un Pionero con pagos manuales según la fase del programa.
class PioneroReglasSuscripcion {
  const PioneroReglasSuscripcion({
    required this.esPionero,
    required this.beneficiosActivos,
    required this.mesBeneficio,
    required this.planActual,
    this.premiumPagoActivo = false,
  });

  final bool esPionero;
  final bool beneficiosActivos;
  final int? mesBeneficio;
  final String planActual;
  final bool premiumPagoActivo;

  bool get aplica => esPionero && beneficiosActivos;

  bool get fasePremium =>
      aplica && mesBeneficio != null && mesBeneficio! >= 1 && mesBeneficio! <= ProgramaPioneros.mesesPremiumRegalo;

  bool get fasePlus =>
      aplica &&
      mesBeneficio != null &&
      mesBeneficio! > ProgramaPioneros.mesesPremiumRegalo &&
      mesBeneficio! <= ProgramaPioneros.mesesPremiumRegalo + ProgramaPioneros.mesesPlusRegalo;

  ({int premiumRestantes, int plusRestantes}) get contadores =>
      ProgramaPioneros.contadoresBeneficios(
        mesBeneficio: mesBeneficio,
        beneficiosActivos: beneficiosActivos,
      );

  /// Sin pagos manuales de renovación del regalo Plus; Premium pagado se renueva normal.
  bool get bloquearRenovacionManual {
    if (!aplica) return false;
    if (fasePremium) return contadores.premiumRestantes >= 1;
    if (fasePlus) return !premiumPagoActivo;
    return false;
  }

  bool get bloquearDowngrade => aplica;

  /// En fase Plus regalo se permite upgrade/renovación a Premium pagado.
  bool get permiteUpgradePremium => fasePlus;

  bool planPermitido(String planRaw) {
    if (!aplica) return true;
    final destino = planRaw.trim().toLowerCase();

    if (fasePremium) return false;
    if (fasePlus) {
      if (destino.contains('premium')) return true;
      return false;
    }
    return true;
  }

  String? motivoBloqueoPlan(String planRaw) {
    if (!aplica) return null;
    if (planPermitido(planRaw)) return null;

    if (fasePremium) {
      if (contadores.premiumRestantes > 1) {
        return 'Tenés ${contadores.premiumRestantes} meses Premium regalo por delante. '
            'Se renuevan solos; no hace falta pagar todavía.';
      }
      return 'Estás en tu mes Premium regalo. Pasá a Plus regalo automáticamente el próximo ciclo.';
    }
    if (fasePlus) {
      final destino = planRaw.trim().toLowerCase();
      if (destino.contains('plus')) {
        return 'Tu plan Plus regalo se renueva solo cada mes. No hace falta pagar la renovación.';
      }
      if (destino.contains('standard')) {
        return 'Durante el programa Pionero no podés pasar a Standard mientras tengas beneficios activos.';
      }
      if (!destino.contains('premium')) {
        return 'Durante los meses Plus regalo solo podés contratar Premium.';
      }
    }
    return 'Este plan no está disponible mientras tengas beneficios Pionero activos.';
  }

  String get mensajeRenovacionBloqueada {
    if (!aplica) return '';
    if (fasePremium) {
      if (contadores.premiumRestantes > 1) {
        return 'Beneficio Premium regalo (${contadores.premiumRestantes}/${ProgramaPioneros.mesesPremiumRegalo} meses restantes). '
            'Se renueva solo; no necesitás pagar aún.';
      }
      return 'Último mes Premium regalo. El próximo ciclo pasás a Plus regalo automáticamente.';
    }
    if (fasePlus) {
      if (premiumPagoActivo) {
        return 'Tenés Premium pagado activo y ${contadores.plusRestantes}/${ProgramaPioneros.mesesPlusRegalo} meses Plus regalo por delante. '
            'Al vencer tu Premium, volvés a Plus regalo automáticamente.';
      }
      if (permiteUpgradePremium) {
        return 'Beneficio Plus regalo (${contadores.plusRestantes}/${ProgramaPioneros.mesesPlusRegalo} meses restantes). '
            'Se renueva solo. Si querés, podés hacer upgrade a Premium.';
      }
    }
    return 'Tus beneficios regalo se renuevan automáticamente.';
  }

  String get mensajePostBeneficios =>
      'Finalizaron tus beneficios regalo. Seguís siendo Pionero de por vida mientras cumplas las políticas del programa. '
      'Desde acá podés contratar Standard, Plus o Premium con normalidad.';
}
