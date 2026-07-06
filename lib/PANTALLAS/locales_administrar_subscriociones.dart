library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants.dart';
import '../widgets/tema_locales_scope.dart';
import '../core/navegacion_locales.dart';
import '../core/suscripcion_locales.dart';
import '../core/supabase_client.dart';
import '../core/programa_pioneros.dart';
import '../widgets/programa_pioneros_ui.dart';
import '../widgets/beneficios_plan_comercial.dart';
import '../widgets/badge_plan_suscripcion.dart';

class LocalesAdministrarSubscriociones extends StatefulWidget {
  /// 0 = Subscripciones, 1 = Mi suscripción. Si es null, se elige según verificación.
  final int? pestanaInicial;

  const LocalesAdministrarSubscriociones({super.key, this.pestanaInicial});

  @override
  State<LocalesAdministrarSubscriociones> createState() =>
      _LocalesAdministrarSubscriocionesState();
}

class _LocalesAdministrarSubscriocionesState
    extends State<LocalesAdministrarSubscriociones> {
  late int _pestana;
  bool _cargando = true;
  EstadoSuscripcionLocal? _estado;
  final GlobalKey _plusPlanKey = GlobalKey();

  bool get _localVerificado => _estado?.localVerificado ?? false;
  bool get _esPionero => _estado?.esPionero ?? false;

  @override
  void initState() {
    super.initState();
    _pestana = widget.pestanaInicial?.clamp(0, 1) ?? 0;
    _cargarPerfil();
  }

  Future<void> _cargarPerfil() async {
    final uid = ServicioSupabase().usuarioActual?.id;
    if (uid == null) {
      if (mounted) setState(() => _cargando = false);
      return;
    }
    setState(() => _cargando = true);
    try {
      final estado = await SuscripcionLocales.cargarEstadoCompleto(uid);
      if (!mounted) return;
      setState(() {
        _estado = estado;
        if (widget.pestanaInicial != null) {
          _pestana = widget.pestanaInicial!.clamp(0, 1);
        } else {
          _pestana = (estado?.localVerificado ?? false) ? 1 : 0;
        }
        _cargando = false;
      });
      if (!(estado?.localVerificado ?? false)) _programarCentradoPlus();
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _irAPagar(String plan) {
    NavegacionLocales.irAComprasPagos(plan).then((_) {
      if (mounted) _cargarPerfil();
    });
  }

  void _irAPlanSiPermitido(String plan) {
    final estado = _estado;
    if (estado != null && estado.esPionero && estado.pioneroBeneficiosActivo) {
      final motivo = estado.reglasPionero.motivoBloqueoPlan(plan);
      if (motivo != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(motivo, style: GoogleFonts.baloo2(fontWeight: FontWeight.w600)),
            backgroundColor: ProgramaPioneros.doradoOscuro,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }
    _irAPagar(plan);
  }

  void _programarCentradoPlus() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ctx = _plusPlanKey.currentContext;
      if (ctx == null || !mounted) return;
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
    });
  }

  bool _planBloqueadoPionero(String plan) {
    final estado = _estado;
    if (estado == null || !estado.esPionero || !estado.pioneroBeneficiosActivo) {
      return false;
    }
    return !estado.reglasPionero.planPermitido(plan);
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final mostaza = ColoresLocales.mostazaDestacado;

    return Scaffold(
      backgroundColor: ColoresLocales.superficie,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: ColoresLocales.superficie,
        centerTitle: true,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => NavegacionLocales.volver(context),
          child: Icon(CupertinoIcons.chevron_back, color: ColoresLocales.acentoVioleta),
        ),
        title: Text(
          'Subscripciones',
          style: GoogleFonts.baloo2(
            color: ColoresLocales.acentoVioleta,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: _SelectorPestanas(
                indice: _pestana,
                onCambio: (i) {
                  setState(() => _pestana = i);
                  if (i == 0) _programarCentradoPlus();
                },
              ),
            ),
            Expanded(
              child: _pestana == 0
                  ? RefreshIndicator(
                      color: ColoresLocales.acentoVioleta,
                      onRefresh: _cargarPerfil,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(16, 4, 16, 20),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: 760),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_esPionero &&
                                    (_estado?.pioneroBeneficiosActivo ?? false)) ...[
                                  BannerInfoPioneroSuscripcion(
                                    reglas: _estado!.reglasPionero,
                                  ),
                                ],
                                _SeccionTitulo(
                                  titulo: 'Subscripciones',
                                  subtitulo: _esPionero &&
                                          (_estado?.pioneroBeneficiosActivo ?? false)
                                      ? 'Durante tus beneficios regalo, los cambios de suscripción son limitados'
                                      : 'Elegí la suscripción que mejor se adapte a tu local',
                                ),
                                SizedBox(height: 12),
                                _PlanHeroComercial(
                                  titulo: 'Standard',
                                  precio: '15 usd / mes',
                                  colorPlan: ColoresLocales.acentoVioleta,
                                  creditos: _creditosComerciales('Standard'),
                                  habilitado: !_planBloqueadoPionero('Standard'),
                                  onTap: () => _irAPlanSiPermitido('Standard'),
                                ),
                                SizedBox(height: 14),
                                _PlanHeroComercial(
                                  cardKey: _plusPlanKey,
                                  titulo: 'Plus',
                                  precio: '35 usd / mes',
                                  colorPlan: const Color(0xFF0891B2),
                                  destacado: true,
                                  creditos: _creditosComerciales('Plus'),
                                  habilitado: !_planBloqueadoPionero('Plus'),
                                  onTap: () => _irAPlanSiPermitido('Plus'),
                                ),
                                SizedBox(height: 14),
                                _PlanHeroComercial(
                                  titulo: 'Premium',
                                  precio: '65 usd / mes',
                                  colorPlan: mostaza,
                                  esPremium: true,
                                  creditos: _creditosComerciales('Premium'),
                                  habilitado: !_planBloqueadoPionero('Premium'),
                                  onTap: () => _irAPlanSiPermitido('Premium'),
                                ),
                                if (!_esPionero) ...[
                                  SizedBox(height: 14),
                                  CardInvitacionProgramaPioneros(onCanjeado: _cargarPerfil),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: RefreshIndicator(
                            color: ColoresLocales.acentoVioleta,
                            onRefresh: _cargarPerfil,
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 760),
                                  child: _cargando
                                      ? Padding(
                                          padding: EdgeInsets.only(top: 40),
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              color: ColoresLocales.acentoVioleta,
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        )
                                      : _estado == null
                                          ? _ErrorCargaSuscripcion(onReintentar: _cargarPerfil)
                                          : !_localVerificado
                                              ? Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.stretch,
                                                  children: [
                                                    _PanelAlertasSuscripcion(
                                                      estado: _estado!,
                                                      onVerPago: () => _irAPagar(
                                                        _estado!.pagoPendiente?.planSolicitado ??
                                                            'Standard',
                                                      ),
                                                    ),
                                                    _TarjetaCuentaGratuita(),
                                                    SizedBox(height: 14),
                                                    Padding(
                                                      padding:
                                                          EdgeInsets.symmetric(
                                                              horizontal: 4),
                                                      child: Text(
                                                        'Compará suscripciones',
                                                        style: GoogleFonts.baloo2(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w900,
                                                          color: ColoresLocales
                                                              .acentoVioleta,
                                                        ),
                                                      ),
                                                    ),
                                                    SizedBox(height: 10),
                                                    ConstrainedBox(
                                                      constraints:
                                                          const BoxConstraints(
                                                              maxWidth: 920),
                                                      child: _TablaComparativaPlanes(),
                                                    ),
                                                    SizedBox(height: 16),
                                                    SizedBox(
                                                      width: double.infinity,
                                                      child: ElevatedButton.icon(
                                                        onPressed: _estado!.tienePagoPendiente
                                                            ? null
                                                            : () {
                                                                setState(() => _pestana = 0);
                                                                _programarCentradoPlus();
                                                              },
                                                        icon: Icon(
                                                          CupertinoIcons.checkmark_seal_fill,
                                                          color: ColoresLocales.chipInactivo,
                                                        ),
                                                        label: Text(
                                                          _estado!.tienePagoPendiente
                                                              ? 'Pago en revisión'
                                                              : '¡Obtener plan verificado!',
                                                          style: GoogleFonts.baloo2(
                                                            fontWeight: FontWeight.w900,
                                                            fontSize: 15.5,
                                                          ),
                                                        ),
                                                        style: ElevatedButton.styleFrom(
                                                          elevation: 0,
                                                          backgroundColor:
                                                              ColoresLocales.acentoVioleta,
                                                          foregroundColor:
                                                              ColoresLocales.textoEnBoton,
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                  vertical: 14,
                                                                  horizontal: 16),
                                                          shape: RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(50),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              : _PanelMiSuscripcion(
                                                  estado: _estado!,
                                                  onRenovar: () => _irAPlanSiPermitido(
                                                    _estado!.planParaRenovar,
                                                  ),
                                                  onMejorar: () {
                                                    setState(() => _pestana = 0);
                                                    _programarCentradoPlus();
                                                  },
                                                  onVerPlanes: () {
                                                    setState(() => _pestana = 0);
                                                  },
                                                  onUpgradePremium: () =>
                                                      _irAPlanSiPermitido('Premium'),
                                                  onVerPago: () => _irAPagar(
                                                    _estado!.pagoPendiente?.planSolicitado ??
                                                        _estado!.planParaRenovar,
                                                  ),
                                                ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectorPestanas extends StatelessWidget {
  final int indice;
  final ValueChanged<int> onCambio;

  const _SelectorPestanas({required this.indice, required this.onCambio});

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: ColoresLocales.cardLavanda,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        children: [
          Expanded(
            child: _PestanaSuscripcion(
              label: 'Subscripciones',
              activa: indice == 0,
              onTap: () => onCambio(0),
            ),
          ),
          Expanded(
            child: _PestanaSuscripcion(
              label: 'Mi suscripción',
              activa: indice == 1,
              onTap: () => onCambio(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _PestanaSuscripcion extends StatelessWidget {
  final String label;
  final bool activa;
  final VoidCallback onTap;

  const _PestanaSuscripcion({
    required this.label,
    required this.activa,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        margin: EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: activa ? ColoresLocales.acentoVioleta : Colors.transparent,
          borderRadius: BorderRadius.circular(50),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.baloo2(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: activa
                ? ColoresLocales.chipInactivo
                : ColoresLocales.textoSecundarioOnFondoClaro,
          ),
        ),
      ),
    );
  }
}

class _PanelMiSuscripcion extends StatelessWidget {
  final EstadoSuscripcionLocal estado;
  final VoidCallback onRenovar;
  final VoidCallback onMejorar;
  final VoidCallback onVerPlanes;
  final VoidCallback onUpgradePremium;
  final VoidCallback onVerPago;

  const _PanelMiSuscripcion({
    required this.estado,
    required this.onRenovar,
    required this.onMejorar,
    required this.onVerPlanes,
    required this.onUpgradePremium,
    required this.onVerPago,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final tipoPlan = estado.tipoPlan;
    final precio = SuscripcionLocales.precioMesEtiqueta(tipoPlan);
    final reglas = estado.reglasPionero;
    final beneficiosActivos = estado.esPionero && estado.pioneroBeneficiosActivo;
    final bloquearRenov = estado.pioneroBloqueaRenovacionManual;
    final mostrarMejorarGenerico =
        !SuscripcionLocales.esPremium(tipoPlan) &&
        !beneficiosActivos &&
        tipoPlan != 'Gratuita';
    final mostrarUpgradePremium =
        reglas.permiteUpgradePremium &&
        !estado.tienePagoPendiente &&
        !estado.pioneroPremiumPagoActivo;
    final bloqueado = estado.tienePagoPendiente;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelAlertasSuscripcion(
          estado: estado,
          onVerPago: onVerPago,
        ),
        if (beneficiosActivos)
          BannerInfoPioneroSuscripcion(reglas: reglas),
        if (estado.esPionero &&
            !estado.pioneroBeneficiosActivo &&
            estado.pioneroBeneficiosFin != null)
          BannerInfoPioneroSuscripcion(
            reglas: reglas,
            beneficiosTerminados: true,
          ),
        _HeroPlanCard(
          estado: estado,
          onVerPlanes: tipoPlan == 'Gratuita' ? onVerPlanes : null,
        ),
        SizedBox(height: 16),
        _SeccionTitulo(
          titulo: 'Beneficios incluidos',
          subtitulo: 'Créditos disponibles este mes',
        ),
        SizedBox(height: 10),
        _CreditoBarra(
          icono: IconosFeaturesLocales.flyersIa,
          color: ColoresFeaturesLocales.flyersIa,
          etiqueta: 'Flyers IA',
          restantes: estado.cupos.flyersIa,
          maximo: estado.cuposMaximos.flyersIa,
        ),
        _CreditoBarra(
          icono: IconosFeaturesLocales.recomendadoFernecito,
          color: ColoresFeaturesLocales.recomendadoFernecito,
          etiqueta: 'Recomendado Fernecito',
          restantes: estado.cupos.recomendadosFernecito,
          maximo: estado.cuposMaximos.recomendadosFernecito,
        ),
        _CreditoBarra(
          icono: IconosFeaturesLocales.topCartelera,
          color: ColoresFeaturesLocales.topCartelera,
          etiqueta: 'Top cartelera',
          restantes: estado.cupos.topCartelera,
          maximo: estado.cuposMaximos.topCartelera,
        ),
        _CreditoBarra(
          icono: IconosFeaturesLocales.topUltra,
          color: ColoresFeaturesLocales.topUltra,
          etiqueta: 'Top ultra',
          restantes: estado.cupos.topUltra,
          maximo: estado.cuposMaximos.topUltra,
        ),
        SizedBox(height: 18),
        _SeccionTitulo(
          titulo: 'Detalle de cuenta',
          subtitulo: null,
        ),
        SizedBox(height: 8),
        _DetalleFila(
          icono: CupertinoIcons.checkmark_seal_fill,
          etiqueta: 'Estado verificado',
          valor: (estado.localVerificado || estado.esPionero) ? 'Activo' : 'No verificado',
          colorValor: estado.esPionero
              ? ProgramaPioneros.dorado
              : (estado.localVerificado ? const Color(0xFF059669) : null),
        ),
        if (estado.fechaVerificacion != null)
          _DetalleFila(
            icono: CupertinoIcons.calendar,
            etiqueta: 'Verificado desde',
            valor: SuscripcionLocales.formatearFecha(estado.fechaVerificacion!),
          ),
        _DetalleFila(
          icono: CupertinoIcons.creditcard,
          etiqueta: 'Precio de la suscripción',
          valor: precio,
        ),
        if (estado.pagoAgendado != null) ...[
          _DetalleFila(
            icono: CupertinoIcons.clock_fill,
            etiqueta: 'Próximo cambio',
            valor: _textoAgendado(estado.pagoAgendado!),
          ),
        ],
        SizedBox(height: 20),
        if (!bloquearRenov &&
            estado.planActivo &&
            estado.fechaVencimiento != null) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: bloqueado ? null : onRenovar,
              icon: Icon(
                CupertinoIcons.arrow_2_circlepath,
                color: bloqueado
                    ? ColoresLocales.textoSecundarioOnFondoClaro
                    : (estado.proximoAVencer
                        ? ColoresLocales.textoSobreMostaza
                        : ColoresLocales.botonVioletaTexto),
              ),
              label: Text(
                bloqueado
                    ? 'Renovación en revisión'
                    : estado.pioneroPremiumPagoActivo
                        ? 'Renovar Premium antes del ${SuscripcionLocales.formatearFechaCorta(estado.fechaVencimiento!)}'
                        : 'Renovar antes del ${SuscripcionLocales.formatearFechaCorta(estado.fechaVencimiento!)}',
                style: GoogleFonts.baloo2(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: estado.proximoAVencer
                    ? ColoresLocales.mostazaDestacado
                    : ColoresLocales.botonVioletaFondo,
                foregroundColor: estado.proximoAVencer
                    ? ColoresLocales.textoSobreMostaza
                    : ColoresLocales.botonVioletaTexto,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50),
                ),
              ),
            ),
          ),
          SizedBox(height: 10),
        ],
        if (mostrarUpgradePremium) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: bloqueado ? null : onUpgradePremium,
              icon: Icon(
                Icons.rocket_launch_rounded,
                color: ColoresLocales.acentoVioletaMarca,
                size: 20,
              ),
              label: Text(
                'Upgrade a Premium',
                style: GoogleFonts.baloo2(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: ColoresLocales.mostazaDestacado,
                foregroundColor: ColoresLocales.acentoVioletaMarca,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (mostrarMejorarGenerico)
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: onMejorar,
              icon: Icon(Icons.rocket_launch_rounded, color: ColoresLocales.acentoVioleta, size: 20),
              label: Text(
                'Mejorar suscripción',
                style: GoogleFonts.baloo2(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: ColoresLocales.acentoVioleta,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: ColoresLocales.acentoVioleta,
                backgroundColor: ColoresLocales.acentoVioleta.withValues(alpha: 0.1),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
              ),
            ),
          ),
        if (bloqueado) ...[
          SizedBox(height: 12),
          TextButton.icon(
            onPressed: onVerPago,
            icon: Icon(CupertinoIcons.doc_text, color: ColoresLocales.acentoVioleta, size: 18),
            label: Text(
              'Ver estado del pago enviado',
              style: GoogleFonts.baloo2(
                fontWeight: FontWeight.w800,
                color: ColoresLocales.acentoVioleta,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _textoAgendado(SolicitudPagoResumen pago) {
    final plan = pago.planSolicitado ?? '—';
    final tipo = SuscripcionLocales.etiquetaTipoSolicitud(pago.tipoSolicitud);
    if (pago.aplicaDesde != null) {
      return '$tipo a $plan · ${SuscripcionLocales.formatearFecha(pago.aplicaDesde!)}';
    }
    return '$tipo a $plan';
  }
}

class _PanelAlertasSuscripcion extends StatelessWidget {
  final EstadoSuscripcionLocal estado;
  final VoidCallback onVerPago;

  const _PanelAlertasSuscripcion({
    required this.estado,
    required this.onVerPago,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final alertas = <Widget>[];

    final pendiente = estado.pagoPendiente;
    if (pendiente != null) {
      alertas.add(
        _AlertaSuscripcion(
          color: const Color(0xFFD97706),
          icono: CupertinoIcons.hourglass,
          titulo: 'Pago en revisión',
          mensaje:
              'Tu comprobante del plan ${pendiente.planSolicitado ?? ''} (${SuscripcionLocales.etiquetaTipoSolicitud(pendiente.tipoSolicitud)}) está pendiente de aprobación.',
          accion: 'Ver detalle',
          onAccion: onVerPago,
        ),
      );
    }

    final agendado = estado.pagoAgendado;
    if (agendado != null) {
      final fecha = agendado.aplicaDesde != null
          ? SuscripcionLocales.formatearFecha(agendado.aplicaDesde!)
          : 'al vencer tu plan actual';
      final esDowngrade = agendado.tipoSolicitud == 'downgrade';
      alertas.add(
        _AlertaSuscripcion(
          color: esDowngrade ? const Color(0xFF0891B2) : const Color(0xFF059669),
          icono: CupertinoIcons.checkmark_seal_fill,
          titulo: esDowngrade ? 'Downgrade aprobado' : 'Renovación aprobada',
          mensaje:
              'Tu suscripción ${agendado.planSolicitado ?? ''} se activará $fecha. Hasta entonces seguís con tu suscripción actual.',
        ),
      );
    }

    if (estado.planActivo &&
        estado.proximoAVencer &&
        !estado.tienePagoAgendado &&
        !estado.pioneroBloqueaRenovacionManual) {
      final dias = estado.diasHastaVencimiento ?? 0;
      alertas.add(
        _AlertaSuscripcion(
          color: ColoresLocales.mostazaDestacado,
          icono: CupertinoIcons.exclamationmark_triangle_fill,
          titulo: 'Tu suscripción vence pronto',
          mensaje: dias <= 1
              ? 'Vence ${dias == 0 ? 'hoy' : 'mañana'}. Renová antes para no perder beneficios.'
              : 'Quedan $dias días. Podés renovar ahora y el cambio se agenda para el vencimiento.',
        ),
      );
    }

    if (!estado.planActivo &&
        estado.localVerificado &&
        estado.fechaVencimiento != null &&
        !estado.tienePagoPendiente &&
        !estado.tienePagoAgendado &&
        !estado.pioneroBloqueaRenovacionManual) {
      alertas.add(
        _AlertaSuscripcion(
          color: const Color(0xFFDC2626),
          icono: CupertinoIcons.xmark_circle_fill,
          titulo: 'Plan vencido',
          mensaje:
              'Tu suscripción venció el ${SuscripcionLocales.formatearFecha(estado.fechaVencimiento!)}. Renová para recuperar créditos y verificación.',
        ),
      );
    }

    final rechazo = estado.ultimoRechazo;
    if (rechazo != null &&
        !estado.tienePagoPendiente &&
        rechazo.revisadoEn != null &&
        DateTime.now().difference(rechazo.revisadoEn!).inDays <= 14) {
      alertas.add(
        _AlertaSuscripcion(
          color: const Color(0xFFDC2626),
          icono: CupertinoIcons.clear_circled_solid,
          titulo: 'Último pago rechazado',
          mensaje: rechazo.notas?.trim().isNotEmpty == true
              ? rechazo.notas!.trim()
              : 'Tu solicitud de ${rechazo.planSolicitado ?? 'plan'} fue rechazada. Podés enviar un nuevo comprobante.',
          accion: 'Reintentar',
          onAccion: onVerPago,
        ),
      );
    }

    if (alertas.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < alertas.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            alertas[i],
          ],
        ],
      ),
    );
  }
}

class _AlertaSuscripcion extends StatelessWidget {
  final Color color;
  final IconData icono;
  final String titulo;
  final String mensaje;
  final String? accion;
  final VoidCallback? onAccion;

  const _AlertaSuscripcion({
    required this.color,
    required this.icono,
    required this.titulo,
    required this.mensaje,
    this.accion,
    this.onAccion,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: GoogleFonts.baloo2(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: ColoresLocales.textoOnFondoClaro,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  mensaje,
                  style: GoogleFonts.baloo2(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color: ColoresLocales.textoSecundarioOnFondoClaro,
                  ),
                ),
                if (accion != null && onAccion != null) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: onAccion,
                    child: Text(
                      accion!,
                      style: GoogleFonts.baloo2(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: color,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPlanCard extends StatelessWidget {
  final EstadoSuscripcionLocal estado;
  final VoidCallback? onVerPlanes;

  const _HeroPlanCard({required this.estado, this.onVerPlanes});

  Color _colorPlan(String tipoPlan) => colorPlanSuscripcionUi(tipoPlan);

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final tipoPlan = estado.tipoPlan;
    final color = _colorPlan(tipoPlan);
    final precioMes = SuscripcionLocales.precioMesEtiqueta(tipoPlan);
    final verificado = (estado.localVerificado || estado.esPionero) && tipoPlan != 'Gratuita';
    final planActivo = estado.planActivo;
    final fechaVencimiento = estado.fechaVencimiento;
    final esPioneroBeneficios = estado.esPionero && estado.pioneroBeneficiosActivo;
    final diasRestantes = esPioneroBeneficios
        ? null // ya va en CabeceraResumenPionero
        : estado.diasHastaVencimiento;
    final mostrarChipDias = !esPioneroBeneficios &&
        diasRestantes != null &&
        planActivo;

    if (estado.esPionero) {
      return Container(
        decoration: ColoresLocales.decoracionCard(radius: 24, sinBorde: true).copyWith(
          color: null,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              ProgramaPioneros.dorado.withValues(alpha: 0.18),
              ColoresLocales.superficie,
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CabeceraResumenPionero(estado: estado),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ChipEstadoPlan(
                  icono: CupertinoIcons.checkmark_seal_fill,
                  texto: 'Verificado',
                  color: ProgramaPioneros.dorado,
                ),
                _ChipEstadoPlan(
                  icono: estado.pioneroPremiumPagoActivo
                      ? CupertinoIcons.creditcard
                      : esPioneroBeneficios
                          ? CupertinoIcons.gift_fill
                          : CupertinoIcons.creditcard,
                  texto: estado.pioneroPremiumPagoActivo
                      ? 'Premium pagado'
                      : esPioneroBeneficios
                          ? '${ProgramaPioneros.etiquetaPlanSuscripcion(tipoPlan)} GRATIS'
                          : ProgramaPioneros.etiquetaPlanSuscripcion(tipoPlan),
                  color: _colorPlan(tipoPlan),
                ),
                if (estado.pioneroPremiumPagoActivo && estado.diasHastaVencimiento != null)
                  _ChipEstadoPlan(
                    icono: CupertinoIcons.timer,
                    texto: estado.diasHastaVencimiento! <= 1
                        ? (estado.diasHastaVencimiento == 0 ? 'Premium vence hoy' : 'Premium vence mañana')
                        : 'Premium: ${estado.diasHastaVencimiento} días',
                    color: (estado.diasHastaVencimiento ?? 999) <= 7
                        ? ColoresLocales.mostazaDestacado
                        : ColoresLocales.acentoVioleta,
                  ),
                if (mostrarChipDias && diasRestantes != null)
                  _ChipEstadoPlan(
                    icono: CupertinoIcons.timer,
                    texto: diasRestantes <= 1
                        ? (diasRestantes == 0 ? 'Vence hoy' : 'Vence mañana')
                        : '$diasRestantes días restantes',
                    color: diasRestantes <= 7
                        ? ColoresLocales.mostazaDestacado
                        : ColoresLocales.acentoVioleta,
                  ),
              ],
            ),
            if (onVerPlanes != null) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onVerPlanes,
                  icon: Icon(CupertinoIcons.square_list, color: ColoresLocales.textoEnBoton),
                  label: Text(
                    'Ver planes',
                    style: GoogleFonts.baloo2(fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: ColoresLocales.botonVioletaFondo,
                    foregroundColor: ColoresLocales.botonVioletaTexto,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      decoration: ColoresLocales.decoracionCard(radius: 24, sinBorde: true).copyWith(
        color: null,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.22),
            ColoresLocales.superficie,
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tu suscripción',
                      style: GoogleFonts.baloo2(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: ColoresLocales.textoSecundarioOnFondoClaro,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      etiquetaSuscripcionCorta(tipoPlan),
                      style: GoogleFonts.baloo2(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        height: 1,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  precioMes,
                  style: GoogleFonts.baloo2(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (verificado)
                _ChipEstadoPlan(
                  icono: CupertinoIcons.checkmark_seal_fill,
                  texto: 'Verificado',
                  color: const Color(0xFF059669),
                ),
              _ChipEstadoPlan(
                icono: planActivo
                    ? CupertinoIcons.bolt_fill
                    : CupertinoIcons.pause_fill,
                texto: planActivo ? 'Suscripción activa' : 'Sin suscripción de pago activa',
                color: planActivo ? ColoresLocales.acentoVioleta : ColoresLocales.textoSecundarioOnFondoClaro,
              ),
              if (diasRestantes != null && planActivo)
                _ChipEstadoPlan(
                  icono: CupertinoIcons.timer,
                  texto: diasRestantes! <= 1
                      ? (diasRestantes == 0 ? 'Vence hoy' : 'Vence mañana')
                      : '$diasRestantes días restantes',
                  color: diasRestantes! <= 7
                      ? ColoresLocales.mostazaDestacado
                      : ColoresLocales.acentoVioleta,
                ),
            ],
          ),
          if (fechaVencimiento != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: ColoresLocales.superficieElevada,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.calendar_badge_minus,
                    size: 18,
                    color: ColoresLocales.acentoVioleta,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      planActivo
                          ? 'Vence el ${SuscripcionLocales.formatearFecha(fechaVencimiento!)}'
                          : 'Último vencimiento: ${SuscripcionLocales.formatearFecha(fechaVencimiento!)}',
                      style: GoogleFonts.baloo2(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: ColoresLocales.textoOnFondoClaro,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (onVerPlanes != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onVerPlanes,
                icon: Icon(CupertinoIcons.square_list, color: ColoresLocales.textoEnBoton),
                label: Text(
                  'Ver planes',
                  style: GoogleFonts.baloo2(fontWeight: FontWeight.w900, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: ColoresLocales.botonVioletaFondo,
                  foregroundColor: ColoresLocales.botonVioletaTexto,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChipEstadoPlan extends StatelessWidget {
  final IconData icono;
  final String texto;
  final Color color;

  const _ChipEstadoPlan({
    required this.icono,
    required this.texto,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            texto,
            style: GoogleFonts.baloo2(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SeccionTitulo extends StatelessWidget {
  final String titulo;
  final String? subtitulo;

  const _SeccionTitulo({required this.titulo, this.subtitulo});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: GoogleFonts.baloo2(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: ColoresLocales.acentoVioleta,
          ),
        ),
        if (subtitulo != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitulo!,
            style: GoogleFonts.baloo2(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ColoresLocales.textoSecundarioOnFondoClaro,
            ),
          ),
        ],
      ],
    );
  }
}

class _CreditoBarra extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String etiqueta;
  final int restantes;
  final int maximo;

  const _CreditoBarra({
    required this.icono,
    required this.color,
    required this.etiqueta,
    required this.restantes,
    required this.maximo,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final ratio = maximo <= 0 ? 0.0 : (restantes / maximo).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, size: 20, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    etiqueta,
                    style: GoogleFonts.baloo2(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: ColoresLocales.textoOnFondoClaro,
                    ),
                  ),
                ),
                Text(
                  maximo <= 0 ? 'No incluido' : '$restantes / $maximo',
                  style: GoogleFonts.baloo2(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: maximo <= 0
                        ? ColoresLocales.textoSecundarioOnFondoClaro
                        : color,
                  ),
                ),
              ],
            ),
            if (maximo > 0) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 6,
                  backgroundColor: color.withValues(alpha: 0.12),
                  color: color,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetalleFila extends StatelessWidget {
  final IconData icono;
  final String etiqueta;
  final String valor;
  final Color? colorValor;

  const _DetalleFila({
    required this.icono,
    required this.etiqueta,
    required this.valor,
    this.colorValor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icono, size: 17, color: ColoresLocales.textoSecundarioOnFondoClaro),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              etiqueta,
              style: GoogleFonts.baloo2(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: ColoresLocales.textoSecundarioOnFondoClaro,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: GoogleFonts.baloo2(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: colorValor ?? ColoresLocales.textoOnFondoClaro,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCargaSuscripcion extends StatelessWidget {
  final VoidCallback onReintentar;

  const _ErrorCargaSuscripcion({required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        children: [
          Icon(CupertinoIcons.wifi_exclamationmark, size: 40, color: ColoresLocales.acentoVioleta),
          const SizedBox(height: 12),
          Text(
            'No pudimos cargar tu suscripción',
            textAlign: TextAlign.center,
            style: GoogleFonts.baloo2(
              fontWeight: FontWeight.w900,
              color: ColoresLocales.acentoVioleta,
            ),
          ),
          TextButton(onPressed: onReintentar, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}

class _PlanCreditoMini {
  const _PlanCreditoMini(this.icono, this.color, this.texto, {this.incluido = true});
  final IconData icono;
  final Color color;
  final String texto;
  final bool incluido;
}

List<_PlanCreditoMini> _creditosComerciales(String plan) {
  return beneficiosComercialesPlan(plan)
      .map(
        (b) => _PlanCreditoMini(
          b.icono,
          b.color,
          b.texto,
          incluido: b.incluido,
        ),
      )
      .toList();
}

class _PlanHeroComercial extends StatelessWidget {
  final Key? cardKey;
  final String titulo;
  final String precio;
  final Color colorPlan;
  final List<_PlanCreditoMini> creditos;
  final VoidCallback onTap;
  final bool esPremium;
  final bool destacado;
  final bool habilitado;

  const _PlanHeroComercial({
    this.cardKey,
    required this.titulo,
    required this.precio,
    required this.colorPlan,
    required this.creditos,
    required this.onTap,
    this.esPremium = false,
    this.destacado = false,
    this.habilitado = true,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return Opacity(
      opacity: habilitado ? 1 : 0.55,
      child: Container(
      key: cardKey,
      decoration: ColoresLocales.decoracionCard(radius: 24, sinBorde: true).copyWith(
        color: null,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorPlan.withValues(alpha: destacado ? 0.32 : 0.2),
            ColoresLocales.superficie,
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: GoogleFonts.baloo2(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        height: 1,
                        color: ColoresLocales.textoOnFondoClaro,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colorPlan.withValues(alpha: destacado ? 0.24 : 0.18),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  precio,
                  style: GoogleFonts.baloo2(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: colorPlan,
                  ),
                ),
              ),
            ],
          ),
          if (esPremium) ...[
            const SizedBox(height: 8),
            _ChipEstadoPlan(
              icono: CupertinoIcons.star_fill,
              texto: 'Máximo alcance',
              color: colorPlan,
            ),
          ],
          const SizedBox(height: 12),
          ...creditos.map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    c.icono,
                    size: 18,
                    color: c.incluido ? c.color : c.color.withValues(alpha: 0.35),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      c.texto,
                      style: GoogleFonts.baloo2(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: c.incluido
                            ? ColoresLocales.textoOnFondoClaro
                            : ColoresLocales.textoSecundarioOnFondoClaro,
                        decoration: c.incluido ? null : TextDecoration.lineThrough,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: habilitado ? onTap : onTap,
              icon: Icon(
                habilitado
                    ? CupertinoIcons.checkmark_seal_fill
                    : CupertinoIcons.lock_fill,
                color: esPremium
                    ? ColoresLocales.acentoVioletaMarca
                    : ColoresLocales.textoEnBoton,
                size: 18,
              ),
              label: Text(
                habilitado ? 'Elegir $titulo' : 'No disponible ahora',
                style: GoogleFonts.baloo2(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: esPremium ? colorPlan : ColoresLocales.acentoVioleta,
                foregroundColor:
                    esPremium ? ColoresLocales.acentoVioletaMarca : ColoresLocales.textoEnBoton,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class _TarjetaCuentaGratuita extends StatelessWidget {
  const _TarjetaCuentaGratuita();

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return Container(
      decoration: ColoresLocales.decoracionCard(radius: 24, sinBorde: true),
      padding: EdgeInsets.fromLTRB(18, 18, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Mi suscripción',
            style: GoogleFonts.baloo2(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: ColoresLocales.acentoVioleta,
            ),
          ),
          SizedBox(height: 8),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: ColoresLocales.cardLavanda,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Cuenta gratuita',
              style: GoogleFonts.baloo2(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: ColoresLocales.acentoVioleta,
              ),
            ),
          ),
          SizedBox(height: 14),
          Text(
            'Llená tu local y hacé despegar tus eventos.',
            style: GoogleFonts.baloo2(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              height: 1.35,
              color: ColoresLocales.acentoVioleta,
            ),
          ),
          const SizedBox(height: 16),
          _TipBeneficio(
            emoji: '✅',
            titulo: 'Verificá tu local',
            subtitulo: 'Activá tu perfil verificado y destacate frente a la competencia.',
          ),
          const SizedBox(height: 10),
          _TipBeneficio(
            emoji: '🚀',
            titulo: 'Accedé a posicionamiento premium',
            subtitulo: 'Recomendado Fernecito, Top cartelera y Top ultra para máxima visibilidad.',
          ),
          const SizedBox(height: 10),
          _TipBeneficio(
            emoji: '🤖',
            titulo: 'Creá flyers profesionales con IA',
            subtitulo: 'En minutos, listos para publicar y atraer más gente.',
          ),
        ],
      ),
    );
  }
}

class _TipBeneficio extends StatelessWidget {
  final String emoji;
  final String titulo;
  final String subtitulo;

  const _TipBeneficio({
    required this.emoji,
    required this.titulo,
    required this.subtitulo,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ColoresLocales.acentoVioleta.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            emoji,
            style: TextStyle(fontSize: 26),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: GoogleFonts.baloo2(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: ColoresLocales.acentoVioleta,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  subtitulo,
                  style: GoogleFonts.baloo2(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ColoresLocales.textoOnFondoClaro.withOpacity(0.82),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TablaComparativaPlanes extends StatelessWidget {
  const _TablaComparativaPlanes();

  static final _header = <String>['', 'Gratis', 'Standard', 'Plus', 'Premium'];

  bool _esNumeroONumeroConDolar(String s) {
    final t = s.trim().replaceAll('\$', '');
    if (t.isEmpty) return false;
    return int.tryParse(t) != null;
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final violet = ColoresLocales.acentoVioleta;

    TableRow row(String feature, List<String> v) {
      Text cell(
        String s, {
        bool header = false,
        bool numero = false,
      }) {
        final baseColor = header
            ? violet
            : (numero ? violet : ColoresLocales.textoOnFondoClaro);
        return Text(
          s,
          textAlign: TextAlign.center,
          style: GoogleFonts.baloo2(
            fontSize: header ? 12.5 : (numero ? 13.8 : 12.5),
            fontWeight: header ? FontWeight.w900 : FontWeight.w800,
            color: baseColor.withOpacity(header ? 0.98 : 0.86),
            height: 1.15,
          ),
        );
      }

      Text left(String s) {
        return Text(
          s,
          style: GoogleFonts.baloo2(
            fontSize: 12.5,
            fontWeight: FontWeight.w900,
            color: ColoresLocales.textoOnFondoClaro.withOpacity(0.86),
            height: 1.15,
          ),
        );
      }

      return TableRow(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: left(feature),
          ),
          for (var i = 0; i < v.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: cell(
                v[i],
                numero: _esNumeroONumeroConDolar(v[i]),
              ),
            ),
        ],
      );
    }

    return Container(
      decoration: ColoresLocales.decoracionCard(radius: 16, sinBorde: true),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: const {
            0: FlexColumnWidth(1.6),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1),
            3: FlexColumnWidth(1),
            4: FlexColumnWidth(1),
          },
          children: [
            TableRow(
              decoration: BoxDecoration(color: ColoresLocales.cardLavanda),
              children: [
                const SizedBox(height: 44),
                for (final h in _header.skip(1))
                  Center(
                    child: Text(
                      h,
                      style: GoogleFonts.baloo2(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: violet,
                      ),
                    ),
                  ),
              ],
            ),
            row('Verificado', ['-', '✅', '✅', '✅']),
            row('Flyers IA / mes', ['-', '3', '20', '40']),
            row('Recomendados / mes', ['-', '4', '8', '12']),
            row('Top cartelera / mes', ['-', '-', '2', '5']),
            row('Top ultra / mes', ['-', '-', '-', '2']),
            row('Precio / mes', ['\$0', '\$15', '\$35', '\$65']),
          ],
        ),
      ),
    );
  }
}
