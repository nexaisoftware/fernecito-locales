library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants.dart';
import '../widgets/tema_locales_scope.dart';
import '../core/servicio_notificaciones_locales.dart';
import '../core/servicio_planes_locales.dart';
import '../core/servicio_push.dart';
import '../core/navegacion_locales.dart';
import '../models/notificacion.dart';

// ─── Pantalla principal ───────────────────────────────────────────────────────

class LocalesNotificaciones extends StatefulWidget {
  const LocalesNotificaciones({super.key});

  @override
  State<LocalesNotificaciones> createState() => _LocalesNotificacionesState();
}

class _LocalesNotificacionesState extends State<LocalesNotificaciones> {
  final _servicio = ServicioNotificacionesLocales();
  List<Notificacion> _notifs = const [];
  bool _cargando = true;
  String? _error;
  bool _pushRevisado = false;
  bool _pushPermitido = false;
  bool _pushActivando = false;

  @override
  void initState() {
    super.initState();
    _revisarPush();
    _cargar();
  }

  Future<void> _revisarPush() async {
    final permitido = await ServicioPush.instancia.tienePermiso();
    if (!mounted) return;
    setState(() {
      _pushPermitido = permitido;
      _pushRevisado = true;
    });
  }

  Future<void> _activarPush() async {
    if (_pushActivando) return;
    HapticFeedback.lightImpact();
    setState(() => _pushActivando = true);
    final ok = await ServicioPush.instancia.registrarParaUsuario();
    if (!mounted) return;
    setState(() {
      _pushPermitido = ok;
      _pushRevisado = true;
      _pushActivando = false;
    });
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final lista = await _servicio.listar();
      await _servicio.refrescarContador();
      if (!mounted) return;
      setState(() {
        _notifs = lista;
        _cargando = false;
      });
      _servicio.sincronizarDesdeLista(lista);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar las notificaciones.';
        _cargando = false;
      });
    }
  }

  Future<void> _recargar() async {
    await _cargar();
  }

  Future<void> _marcarLeida(Notificacion n) async {
    if (n.leida) return;
    // Optimista: actualizamos UI primero
    setState(() {
      final idx = _notifs.indexWhere((x) => x.id == n.id);
      if (idx >= 0) {
        _notifs[idx] = n.copyWith(
          leida: true,
          fechaLectura: DateTime.now().toUtc(),
        );
      }
    });
    _servicio.sincronizarDesdeLista(_notifs);
    final ok = await _servicio.marcarLeida(n.id);
    if (!ok && mounted) {
      // Revertir si falló
      setState(() {
        final idx = _notifs.indexWhere((x) => x.id == n.id);
        if (idx >= 0) _notifs[idx] = n;
      });
      _servicio.sincronizarDesdeLista(_notifs);
    }
  }

  Future<void> _marcarTodas() async {
    if (_notifs.every((n) => n.leida)) return;
    HapticFeedback.lightImpact();
    setState(() {
      _notifs = _notifs.map((n) => n.copyWith(leida: true)).toList();
    });
    _servicio.contadorNoLeidas.value = 0;
    await _servicio.marcarTodasLeidas();
  }

  Future<void> _navegar(Notificacion n) async {
    _marcarLeida(n);
    var destino = _destinoNotificacion(n);
    if (destino.ruta.isEmpty) return;
    if (destino.ruta == '/planes/detalle') {
      final idPlan = _idPlanDesdeArgumentos(destino.argumentos);
      if (idPlan.isNotEmpty) {
        final detalle = await ServicioPlanesLocales.instancia.detalle(idPlan);
        if (!mounted) return;
        if (detalle != null && !detalle.plan.estaAbierto) {
          destino = (ruta: '/planes', pestana: null, argumentos: null);
        }
      }
    }
    try {
      NavegacionLocales.pushNamed(
        destino.ruta,
        arguments: destino.argumentos ?? destino.pestana,
      );
    } catch (e) {
      debugPrint('⚠️ pushNamed ${destino.ruta}: $e');
    }
  }

  String _idPlanDesdeArgumentos(Object? argumentos) {
    if (argumentos is String) return argumentos.trim();
    if (argumentos is Map && argumentos['id_plan'] != null) {
      return argumentos['id_plan'].toString().trim();
    }
    return '';
  }

  /// Resuelve CTA de notificaciones legacy (/mi_cuenta, rutas typo) y pagos.
  ({String ruta, int? pestana, Object? argumentos}) _destinoNotificacion(
    Notificacion n,
  ) {
    const rutaSubs = '/administrar_subscripciones';

    int? pestanaPorTipo(String tipo) => switch (tipo) {
      'pago_aprobado' || 'pago_agendado' || 'plan_renovado' => 1,
      'plan_vencido' => 0,
      _ => null,
    };

    final idPlan = (n.ctaIdRef ?? n.payload?['id_plan']?.toString() ?? '')
        .trim();
    final accion = (n.payload?['accion'] ?? n.payload?['cta'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (n.tipo == 'ranking_local_primero') {
      return (ruta: '/home', pestana: null, argumentos: null);
    }
    if (n.tipo == 'plan_mencion' && accion == 'chat') {
      if (idPlan.isNotEmpty) {
        return (
          ruta: '/planes/detalle',
          pestana: null,
          argumentos: <String, dynamic>{'id_plan': idPlan, 'accion': 'chat'},
        );
      }
      return (ruta: '/planes', pestana: null, argumentos: null);
    }
    if (n.tipo == 'plan_solicitud' || accion == 'solicitudes') {
      if (idPlan.isNotEmpty) {
        return (
          ruta: '/planes/detalle',
          pestana: null,
          argumentos: <String, dynamic>{
            'id_plan': idPlan,
            'accion': 'solicitudes',
          },
        );
      }
      return (ruta: '/planes', pestana: null, argumentos: null);
    }
    if (n.tipo == 'plan_pedido_local' ||
        n.tipo == 'plan_pedido_respuesta' ||
        n.tipo == 'plan_mencion' ||
        (n.ctaRuta ?? '').contains('planes')) {
      if (idPlan.isNotEmpty) {
        return (ruta: '/planes/detalle', pestana: null, argumentos: idPlan);
      }
      return (ruta: '/planes', pestana: null, argumentos: null);
    }

    final pestanaTipo = pestanaPorTipo(n.tipo);
    if (pestanaTipo != null) {
      return (ruta: rutaSubs, pestana: pestanaTipo, argumentos: pestanaTipo);
    }

    final ruta = (n.ctaRuta ?? '').trim();
    if (ruta.isEmpty) return (ruta: '', pestana: null, argumentos: null);

    if (ruta == rutaSubs ||
        ruta == '/administrar_suscripciones' ||
        ruta == '/mi_cuenta') {
      return (
        ruta: rutaSubs,
        pestana: pestanaTipo ?? 1,
        argumentos: pestanaTipo ?? 1,
      );
    }

    return (ruta: ruta, pestana: null, argumentos: null);
  }

  int get _sinLeer => _notifs.where((n) => !n.leida).length;

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    TemaLocalesScope.of(context);
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: ColoresLocales.acentoVioleta,
        onRefresh: _recargar,
        child: CustomScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            if (_cargando)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(
                    color: ColoresLocales.acentoVioleta,
                  ),
                ),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildErrorState(),
              )
            else if (_notifs.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _CardNotif(
                        notif: _notifs[i],
                        onTap: () => _navegar(_notifs[i]),
                        onBoton: () => _navegar(_notifs[i]),
                      ),
                    ),
                    childCount: _notifs.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 24, 20, 10),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(width: 44),
              Expanded(
                child: Center(
                  child: Text(
                    'Notificaciones',
                    style: GoogleFonts.baloo2(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: ColoresLocales.acentoVioleta,
                    ),
                  ),
                ),
              ),
              // Acción "marcar todas" (visible si hay >0 sin leer)
              SizedBox(
                width: 44,
                child: _sinLeer > 0
                    ? CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: Size(36, 36),
                        onPressed: _marcarTodas,
                        child: Icon(
                          CupertinoIcons.checkmark_alt_circle,
                          color: ColoresLocales.acentoVioleta,
                          size: 22,
                        ),
                      )
                    : SizedBox.shrink(),
              ),
            ],
          ),
          if (_sinLeer > 0) ...[
            SizedBox(height: 6),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: ColoresLocales.acentoVioleta.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Text(
                '$_sinLeer sin leer',
                style: GoogleFonts.baloo2(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ColoresLocales.acentoVioleta,
                ),
              ),
            ),
          ],
          if (_pushRevisado &&
              !_pushPermitido &&
              ServicioPush.instancia.soportado) ...[
            const SizedBox(height: 12),
            _buildBannerActivarPush(),
          ],
        ],
      ),
    );
  }

  Widget _buildBannerActivarPush() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _pushActivando ? null : _activarPush,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: ColoresLocales.cardLavanda,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: ColoresLocales.acentoVioleta.withValues(alpha: 0.22),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.bell_fill,
                  size: 22,
                  color: ColoresLocales.acentoVioleta,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Activá las notificaciones push',
                        style: GoogleFonts.baloo2(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: ColoresLocales.textoOnFondoClaro,
                        ),
                      ),
                      Text(
                        'Recibí alertas aunque no tengas la app abierta.',
                        style: GoogleFonts.baloo2(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: ColoresLocales.textoSecundarioOnFondoClaro,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_pushActivando)
                  const CupertinoActivityIndicator(radius: 9)
                else
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 18,
                    color: ColoresLocales.acentoVioleta.withValues(alpha: 0.6),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.bell,
              size: 56,
              color: ColoresLocales.acentoVioleta.withValues(alpha: 0.35),
            ),
            SizedBox(height: 14),
            Text(
              'No tenés notificaciones',
              textAlign: TextAlign.center,
              style: GoogleFonts.baloo2(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: ColoresLocales.textoOnFondoClaro,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Acá vas a ver alertas sobre tus eventos, listas, pagos y reseñas.',
              textAlign: TextAlign.center,
              style: GoogleFonts.baloo2(
                fontSize: 13,
                color: ColoresLocales.textoSecundarioOnFondoClaro,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_circle,
              size: 56,
              color: Colors.red.shade300,
            ),
            SizedBox(height: 14),
            Text(
              _error ?? 'Error al cargar',
              textAlign: TextAlign.center,
              style: GoogleFonts.baloo2(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: ColoresLocales.textoOnFondoClaro,
              ),
            ),
            SizedBox(height: 14),
            CupertinoButton(
              color: ColoresLocales.acentoVioleta,
              borderRadius: BorderRadius.circular(50),
              onPressed: _cargar,
              child: Text(
                'Reintentar',
                style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Card de notificación ─────────────────────────────────────────────────────

class _CardNotif extends StatelessWidget {
  final Notificacion notif;
  final VoidCallback onTap;
  final VoidCallback onBoton;

  const _CardNotif({
    required this.notif,
    required this.onTap,
    required this.onBoton,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final leida = notif.leida;
    final colorAccent = notif.colorAcento(leida: leida);
    final colorBotonTexto = notif.colorTextoBoton(leida: leida);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 300),
        decoration: ColoresLocales.decoracionCard(sinBorde: true),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                  notif.icono,
                  color: leida
                      ? ColoresLocales.textoSecundarioOnFondoClaro
                      : colorAccent,
                  size: 22,
                ),
              ),
              SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            notif.titulo,
                            style: GoogleFonts.baloo2(
                              fontSize: 14,
                              fontWeight: leida
                                  ? FontWeight.w600
                                  : FontWeight.w900,
                              color: leida
                                  ? ColoresLocales.textoSecundarioOnFondoClaro
                                  : ColoresLocales.textoOnFondoClaro,
                              height: 1.3,
                            ),
                          ),
                        ),
                        if (!leida) ...[
                          SizedBox(width: 6),
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(top: 5),
                            decoration: BoxDecoration(
                              color: colorAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 4),

                    Text(
                      notif.descripcion,
                      style: GoogleFonts.baloo2(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: ColoresLocales.textoSecundarioOnFondoClaro,
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: 8),

                    Row(
                      children: [
                        Text(
                          notif.fechaRelativa,
                          style: GoogleFonts.baloo2(
                            fontSize: 11,
                            color: ColoresLocales.textoSecundarioOnFondoClaro
                                .withValues(alpha: 0.6),
                          ),
                        ),
                        Spacer(),
                        if (notif.ctaTexto != null &&
                            notif.ctaTexto!.isNotEmpty)
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: onBoton,
                            minimumSize: Size(0, 0),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: leida
                                    ? colorAccent.withValues(alpha: 0.1)
                                    : colorAccent,
                                borderRadius: BorderRadius.circular(50),
                              ),
                              child: Text(
                                notif.ctaTexto!,
                                style: GoogleFonts.baloo2(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: leida
                                      ? ColoresLocales
                                            .textoSecundarioOnFondoClaro
                                      : colorBotonTexto,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
