library;

import 'programa_pioneros.dart';
import 'supabase_client.dart';

/// Lógica de planes (gratis / standard / plus / premium / pionero).
class SuscripcionLocales {
  SuscripcionLocales._();

  static const _meses = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];

  /// Intenta leer [plan_suscripcion] en [perfiles_locales].
  static Future<String?> leerTipoRawDesdePerfil(String uid) async {
    try {
      final r = await ServicioSupabase()
          .cliente
          .from('perfiles_locales')
          .select('plan_suscripcion')
          .eq('id', uid)
          .maybeSingle();
      final v = r?['plan_suscripcion'];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  /// Lee créditos reales desde Supabase.
  static Future<CuposSuscripcionMock> leerCuposDesdePerfil({
    required String uid,
    required String tipoPlan,
  }) async {
    try {
      final r = await ServicioSupabase()
          .cliente
          .from('perfiles_locales')
          .select('cupos_flyers_ia, cupos_recomendado, cupos_top_cartelera, cupos_top_ultra')
          .eq('id', uid)
          .maybeSingle();
      if (r == null) return cuposMaximosPorPlan(tipoPlan);
      return CuposSuscripcionMock(
        flyersIa: (r['cupos_flyers_ia'] as num?)?.toInt() ?? 0,
        recomendadosFernecito: (r['cupos_recomendado'] as num?)?.toInt() ?? 0,
        topCartelera: (r['cupos_top_cartelera'] as num?)?.toInt() ?? 0,
        topUltra: (r['cupos_top_ultra'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return cuposMaximosPorPlan(tipoPlan);
    }
  }

  /// Perfil + solicitudes de pago activas (fuente única para UI de suscripción).
  static Future<EstadoSuscripcionLocal?> cargarEstadoCompleto(String uid) async {
    try {
      final sb = ServicioSupabase().cliente;

      final perfil = await sb
          .from('perfiles_locales')
          .select(
            'local_verificado, plan_suscripcion, fecha_vencimiento_suscripcion, '
            'fecha_verificacion, cupos_flyers_ia, cupos_recomendado, '
            'cupos_top_cartelera, cupos_top_ultra, es_pionero, '
            'pionero_canjeado_en, pionero_beneficios_inicio, '
            'pionero_beneficios_fin, pionero_mes_beneficio, pionero_proximo_reset',
          )
          .eq('id', uid)
          .maybeSingle();
      if (perfil == null) return null;

      final raw = perfil['plan_suscripcion']?.toString().trim();
      final verificado = perfil['local_verificado'] == true;
      final esPionero = perfil['es_pionero'] == true;
      final vencRaw = perfil['fecha_vencimiento_suscripcion'];
      final vencimiento =
          vencRaw != null ? DateTime.tryParse(vencRaw.toString())?.toLocal() : null;
      final verifRaw = perfil['fecha_verificacion'];
      final fechaVerificacion =
          verifRaw != null ? DateTime.tryParse(verifRaw.toString())?.toLocal() : null;

      final pioneroCanjeRaw = perfil['pionero_canjeado_en'];
      final pioneroCanjeadoEn = pioneroCanjeRaw != null
          ? DateTime.tryParse(pioneroCanjeRaw.toString())?.toLocal()
          : null;
      final pioneroInicioRaw = perfil['pionero_beneficios_inicio'];
      final pioneroBeneficiosInicioDb = pioneroInicioRaw != null
          ? DateTime.tryParse(pioneroInicioRaw.toString())?.toLocal()
          : null;
      final pioneroFinRaw = perfil['pionero_beneficios_fin'];
      final pioneroBeneficiosFin = pioneroFinRaw != null
          ? DateTime.tryParse(pioneroFinRaw.toString())?.toLocal()
          : null;
      final pioneroBeneficiosInicio = ProgramaPioneros.resolverInicioBeneficios(
        beneficiosInicio: pioneroBeneficiosInicioDb,
        canjeadoEn: pioneroCanjeadoEn,
        beneficiosFin: pioneroBeneficiosFin,
      );
      final pioneroBeneficiosActivo = esPionero &&
          pioneroBeneficiosFin != null &&
          pioneroBeneficiosFin.isAfter(DateTime.now());
      final pioneroMes = (perfil['pionero_mes_beneficio'] as num?)?.toInt();
      final pioneroResetRaw = perfil['pionero_proximo_reset'];
      final pioneroProximoReset = pioneroResetRaw != null
          ? DateTime.tryParse(pioneroResetRaw.toString())?.toLocal()
          : null;

      final tipoPlan = tipoPlanEfectivo(
        rawDb: raw,
        localVerificado: verificado,
        esPionero: esPionero,
        pioneroBeneficiosActivo: pioneroBeneficiosActivo,
        pioneroMesBeneficio: pioneroMes,
        fechaVencimiento: vencimiento,
      );
      final cupos = CuposSuscripcionMock(
        flyersIa: (perfil['cupos_flyers_ia'] as num?)?.toInt() ?? 0,
        recomendadosFernecito: (perfil['cupos_recomendado'] as num?)?.toInt() ?? 0,
        topCartelera: (perfil['cupos_top_cartelera'] as num?)?.toInt() ?? 0,
        topUltra: (perfil['cupos_top_ultra'] as num?)?.toInt() ?? 0,
      );

      final solicitudes = await sb
          .from('pagos_pendientes')
          .select(
            'id, estado, tipo_solicitud, plan_solicitado, plan_anterior, '
            'creado_en, aplica_desde, revisado_en, notas',
          )
          .eq('perfil_id', uid)
          .inFilter('estado', ['pendiente', 'aprobado_pendiente', 'rechazado'])
          .order('creado_en', ascending: false)
          .limit(12);

      SolicitudPagoResumen? pendiente;
      SolicitudPagoResumen? agendada;
      SolicitudPagoResumen? ultimoRechazo;

      for (final row in (solicitudes as List).cast<Map<String, dynamic>>()) {
        final resumen = SolicitudPagoResumen.fromMap(row);
        if (resumen.estado == 'pendiente' && pendiente == null) {
          pendiente = resumen;
        }
        if (resumen.estado == 'aprobado_pendiente' &&
            (resumen.tipoSolicitud == 'renovacion' ||
                resumen.tipoSolicitud == 'downgrade') &&
            agendada == null) {
          agendada = resumen;
        }
        if (resumen.estado == 'rechazado' && ultimoRechazo == null) {
          ultimoRechazo = resumen;
        }
      }

      return EstadoSuscripcionLocal(
        localVerificado: verificado,
        esPionero: esPionero,
        pioneroBeneficiosActivo: pioneroBeneficiosActivo,
        pioneroBeneficiosInicio: pioneroBeneficiosInicio,
        pioneroCanjeadoEn: pioneroCanjeadoEn,
        pioneroBeneficiosFin: pioneroBeneficiosFin,
        pioneroMesBeneficio: (perfil['pionero_mes_beneficio'] as num?)?.toInt(),
        pioneroProximoReset: pioneroProximoReset,
        planRaw: raw,
        fechaVencimiento: vencimiento,
        fechaVerificacion: fechaVerificacion,
        cupos: cupos,
        pagoPendiente: pendiente,
        pagoAgendado: agendada,
        ultimoRechazo: ultimoRechazo,
        tipoPlan: tipoPlan,
        cuposMaximos: cuposMaximosPorPlan(tipoPlan),
      );
    } catch (_) {
      return null;
    }
  }

  /// Plan de créditos activo: Premium pagado > regalo Pionero > plan_suscripcion.
  static String tipoPlanEfectivo({
    required String? rawDb,
    required bool localVerificado,
    bool esPionero = false,
    bool pioneroBeneficiosActivo = false,
    int? pioneroMesBeneficio,
    DateTime? fechaVencimiento,
  }) {
    if (ProgramaPioneros.premiumPagoActivo(
      planRaw: rawDb,
      fechaVencimiento: fechaVencimiento,
    )) {
      return 'Premium';
    }
    if (esPionero &&
        pioneroBeneficiosActivo &&
        pioneroMesBeneficio != null &&
        pioneroMesBeneficio >= 1) {
      return ProgramaPioneros.planRegaloPorMes(pioneroMesBeneficio);
    }
    return tipoPlanPago(
      rawDb: rawDb,
      localVerificado: localVerificado || esPionero,
    );
  }

  static String tipoPlanPago({
    required String? rawDb,
    required bool localVerificado,
  }) {
    if (!localVerificado) return 'Gratuita';
    final raw = (rawDb ?? '').trim().toLowerCase();
    if (raw.isEmpty) return 'Standard';
    if (raw.contains('premium')) return 'Premium';
    if (raw.contains('plus')) return 'Plus';
    if (raw.contains('gratis') || raw.contains('gratuita')) return 'Gratuita';
    if (raw.contains('standard') ||
        raw.contains('stándar') ||
        raw.contains('estandar')) {
      return 'Standard';
    }
    return 'Standard';
  }

  static int rankPlan(String? plan) {
    final p = (plan ?? 'gratis').trim().toLowerCase();
    if (p.contains('premium')) return 3;
    if (p.contains('plus')) return 2;
    if (p.contains('standard') || p.contains('estandar')) return 1;
    return 0;
  }

  /// Texto corto para UI: si no está verificado, no es un plan de pago.
  static String etiquetaPlanUi({
    required String? rawDb,
    required bool localVerificado,
    bool esPionero = false,
    bool pioneroBeneficiosActivo = false,
    int? pioneroMesBeneficio,
    DateTime? fechaVencimiento,
  }) {
    if (!localVerificado && !esPionero) return 'Cuenta gratuita';
    final plan = tipoPlanEfectivo(
      rawDb: rawDb,
      localVerificado: localVerificado,
      esPionero: esPionero,
      pioneroBeneficiosActivo: pioneroBeneficiosActivo,
      pioneroMesBeneficio: pioneroMesBeneficio,
      fechaVencimiento: fechaVencimiento,
    );
    return plan == 'Gratuita' ? 'Gratis' : plan;
  }

  static String precioMesEtiqueta(String tipoPlan) {
    switch (tipoPlan) {
      case 'Premium':
        return '65 usd / mes';
      case 'Plus':
        return '35 usd / mes';
      case 'Gratuita':
        return '0 usd / mes';
      default:
        return '15 usd / mes';
    }
  }

  static String rawPlanParaNavegacion(String tipoPlan) {
    switch (tipoPlan) {
      case 'Premium':
        return 'Premium';
      case 'Plus':
        return 'Plus';
      case 'Standard':
        return 'Standard';
      default:
        return 'Standard';
    }
  }

  static String formatearFecha(DateTime fecha) {
    final d = fecha.day.toString().padLeft(2, '0');
    final m = _meses[fecha.month - 1];
    final y = fecha.year;
    return '$d $m $y';
  }

  static String formatearFechaCorta(DateTime fecha) {
    final d = fecha.day.toString().padLeft(2, '0');
    final m = fecha.month.toString().padLeft(2, '0');
    return '$d/$m/${fecha.year}';
  }

  static String etiquetaTipoSolicitud(String? tipo) {
    switch (tipo) {
      case 'plan_nuevo':
        return 'Plan nuevo';
      case 'upgrade':
        return 'Upgrade';
      case 'renovacion':
        return 'Renovación';
      case 'downgrade':
        return 'Downgrade';
      default:
        return 'Solicitud';
    }
  }

  /// Máximos mensuales por plan (para barras de progreso en UI).
  static CuposSuscripcionMock cuposMaximosPorPlan(String tipoPlan) {
    switch (tipoPlan) {
      case 'Premium':
        return const CuposSuscripcionMock(
          flyersIa: 40,
          recomendadosFernecito: 12,
          topCartelera: 5,
          topUltra: 2,
        );
      case 'Plus':
        return const CuposSuscripcionMock(
          flyersIa: 20,
          recomendadosFernecito: 8,
          topCartelera: 2,
          topUltra: 0,
        );
      case 'Standard':
        return const CuposSuscripcionMock(
          flyersIa: 3,
          recomendadosFernecito: 4,
          topCartelera: 0,
          topUltra: 0,
        );
      default:
        return const CuposSuscripcionMock(
          flyersIa: 0,
          recomendadosFernecito: 0,
          topCartelera: 0,
          topUltra: 0,
        );
    }
  }

  /// @deprecated Usar [cuposMaximosPorPlan]. Solo queda por compatibilidad.
  static CuposSuscripcionMock cuposRestantesMock(String tipoPlan) =>
      cuposMaximosPorPlan(tipoPlan);

  static bool esPremium(String tipoPlan) => tipoPlan == 'Premium';
}

class SolicitudPagoResumen {
  final String id;
  final String estado;
  final String? tipoSolicitud;
  final String? planSolicitado;
  final String? planAnterior;
  final DateTime? creadoEn;
  final DateTime? aplicaDesde;
  final DateTime? revisadoEn;
  final String? notas;

  const SolicitudPagoResumen({
    required this.id,
    required this.estado,
    this.tipoSolicitud,
    this.planSolicitado,
    this.planAnterior,
    this.creadoEn,
    this.aplicaDesde,
    this.revisadoEn,
    this.notas,
  });

  factory SolicitudPagoResumen.fromMap(Map<String, dynamic> m) {
    DateTime? parse(String? k) {
      final v = m[k];
      if (v == null) return null;
      return DateTime.tryParse(v.toString())?.toLocal();
    }

    return SolicitudPagoResumen(
      id: m['id']?.toString() ?? '',
      estado: m['estado']?.toString() ?? '',
      tipoSolicitud: m['tipo_solicitud']?.toString(),
      planSolicitado: m['plan_solicitado']?.toString(),
      planAnterior: m['plan_anterior']?.toString(),
      creadoEn: parse('creado_en'),
      aplicaDesde: parse('aplica_desde'),
      revisadoEn: parse('revisado_en'),
      notas: m['notas']?.toString(),
    );
  }
}

class EstadoSuscripcionLocal {
  final bool localVerificado;
  final bool esPionero;
  final bool pioneroBeneficiosActivo;
  final DateTime? pioneroBeneficiosInicio;
  final DateTime? pioneroCanjeadoEn;
  final DateTime? pioneroBeneficiosFin;
  final int? pioneroMesBeneficio;
  final DateTime? pioneroProximoReset;
  final String? planRaw;
  final DateTime? fechaVencimiento;
  final DateTime? fechaVerificacion;
  final CuposSuscripcionMock cupos;
  final CuposSuscripcionMock cuposMaximos;
  final String tipoPlan;
  final SolicitudPagoResumen? pagoPendiente;
  final SolicitudPagoResumen? pagoAgendado;
  final SolicitudPagoResumen? ultimoRechazo;

  const EstadoSuscripcionLocal({
    required this.localVerificado,
    required this.esPionero,
    required this.pioneroBeneficiosActivo,
    required this.pioneroBeneficiosInicio,
    required this.pioneroCanjeadoEn,
    required this.pioneroBeneficiosFin,
    required this.pioneroMesBeneficio,
    required this.pioneroProximoReset,
    required this.planRaw,
    required this.fechaVencimiento,
    required this.fechaVerificacion,
    required this.cupos,
    required this.cuposMaximos,
    required this.tipoPlan,
    this.pagoPendiente,
    this.pagoAgendado,
    this.ultimoRechazo,
  });

  bool get planActivo {
    final v = fechaVencimiento;
    if (v == null || !localVerificado) return false;
    final raw = (planRaw ?? 'gratis').toLowerCase();
    return v.isAfter(DateTime.now()) && raw != 'gratis' && raw.isNotEmpty;
  }

  int? get diasHastaVencimiento {
    final v = fechaVencimiento;
    if (v == null || !planActivo) return null;
    final diff = v.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return diff.inDays;
  }

  bool get proximoAVencer {
    final d = diasHastaVencimiento;
    return d != null && d <= 7;
  }

  bool get tienePagoPendiente => pagoPendiente != null;

  bool get tienePagoAgendado => pagoAgendado != null;

  String get planParaRenovar =>
      SuscripcionLocales.rawPlanParaNavegacion(
        planActivo ? tipoPlan : (pagoAgendado?.planSolicitado ?? 'Standard'),
      );

  bool get pioneroPremiumPagoActivo => ProgramaPioneros.premiumPagoActivo(
        planRaw: planRaw,
        fechaVencimiento: fechaVencimiento,
      );

  bool get pioneroPlusRegaloActivo =>
      esPionero &&
      pioneroBeneficiosActivo &&
      ProgramaPioneros.enFasePlusBeneficios(
        beneficiosActivos: pioneroBeneficiosActivo,
        mesBeneficio: pioneroMesBeneficio,
      );

  bool get pioneroPremiumConPlusRegalo =>
      pioneroPremiumPagoActivo && pioneroPlusRegaloActivo;

  PioneroReglasSuscripcion get reglasPionero => ProgramaPioneros.reglas(
        esPionero: esPionero,
        beneficiosActivos: pioneroBeneficiosActivo,
        mesBeneficio: pioneroMesBeneficio,
        planActual: tipoPlan,
        premiumPagoActivo: pioneroPremiumPagoActivo,
      );

  bool get pioneroBloqueaRenovacionManual =>
      reglasPionero.bloquearRenovacionManual;

  /// Fecha mostrada en cards Pionero (regalo o Premium pagado en fase Plus).
  ({DateTime? fecha, String etiqueta}) get vencimientoTarjetaPionero {
    if (pioneroPremiumConPlusRegalo && fechaVencimiento != null) {
      return (fecha: fechaVencimiento, etiqueta: 'Premium vence el:');
    }
    if (pioneroBeneficiosActivo) {
      return ProgramaPioneros.vencimientoUiBeneficios(
        mesBeneficio: pioneroMesBeneficio,
        beneficiosInicio: pioneroBeneficiosInicio,
        canjeadoEn: pioneroCanjeadoEn,
        beneficiosFin: pioneroBeneficiosFin,
      );
    }
    return (fecha: fechaVencimiento, etiqueta: 'Vence el:');
  }

  /// Días restantes del bloque gratis (4m Premium o 12m total), no del reset mensual de créditos.
  int? get diasHastaBeneficioGratisUi {
    if (!pioneroBeneficiosActivo) return null;
    return ProgramaPioneros.diasHastaFinBeneficioGratis(
      beneficiosActivos: pioneroBeneficiosActivo,
      mesBeneficio: pioneroMesBeneficio,
      beneficiosInicio: pioneroBeneficiosInicio,
      canjeadoEn: pioneroCanjeadoEn,
      beneficiosFin: pioneroBeneficiosFin,
    );
  }
}

class CuposSuscripcionMock {
  final int flyersIa;
  final int recomendadosFernecito;
  final int topCartelera;
  final int topUltra;

  const CuposSuscripcionMock({
    required this.flyersIa,
    required this.recomendadosFernecito,
    required this.topCartelera,
    required this.topUltra,
  });
}
