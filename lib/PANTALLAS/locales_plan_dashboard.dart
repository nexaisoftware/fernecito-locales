library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants.dart';
import '../core/servicio_planes_locales.dart';
import '../widgets/tema_locales_scope.dart';
import 'locales_chat_plan.dart';

class LocalesPlanDashboard extends StatefulWidget {
  const LocalesPlanDashboard({
    super.key,
    required this.idPlan,
    this.inicial,
    this.abrirChat = false,
    this.abrirSolicitudes = false,
  });

  final String idPlan;
  final PlanLocalItem? inicial;
  final bool abrirChat;
  final bool abrirSolicitudes;

  @override
  State<LocalesPlanDashboard> createState() => _LocalesPlanDashboardState();
}

class _LocalesPlanDashboardState extends State<LocalesPlanDashboard> {
  final _srv = ServicioPlanesLocales.instancia;
  PlanLocalDetalle? _detalle;
  bool _cargando = true;
  bool _accionando = false;
  bool _abrioChatAutomatico = false;
  bool _abrioSolicitudesAutomatico = false;
  String? _error;

  PlanLocalItem get _plan => _detalle?.plan ?? widget.inicial ?? _planFallback;

  PlanLocalItem get _planFallback => PlanLocalItem(
    id: widget.idPlan,
    titulo: 'Plan',
    descripcion: '',
    ciudad: '',
    fechaInicio: DateTime.now(),
    modoLista: 'auto',
    cupoUsados: 0,
    nombreOrganizador: '',
    tipoOrganizador: 'usuario',
  );

  String get _nombreGrupo =>
      _plan.nombreSquad ??
      (_plan.nombreOrganizador.trim().isEmpty
          ? null
          : _plan.nombreOrganizador) ??
      'este grupo';

  String get _adminPlan {
    final miembros = _detalle?.miembros ?? const <PlanLocalMiembro>[];
    for (final m in miembros) {
      final rol = m.rol.toLowerCase();
      if (rol == 'organizador' || rol == 'admin') {
        return m.nombre;
      }
    }
    final n = _plan.nombreOrganizador.trim();
    return n.isEmpty ? '—' : n;
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    final det = await _srv.detalle(widget.idPlan);
    if (!mounted) return;
    setState(() {
      _detalle = det;
      _cargando = false;
      _error = det == null ? 'No se pudo cargar el plan.' : null;
    });
    if (det != null &&
        det.plan.estaAbierto &&
        widget.abrirChat &&
        !_abrioChatAutomatico) {
      _abrioChatAutomatico = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _abrirChat();
      });
    } else if (det != null &&
        det.plan.estaAbierto &&
        widget.abrirSolicitudes &&
        !_abrioSolicitudesAutomatico) {
      _abrioSolicitudesAutomatico = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _abrirSolicitudes();
      });
    }
  }

  String _fmtFecha(DateTime d) {
    const dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    final dia = dias[(d.weekday - 1).clamp(0, 6)];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$dia ${d.day}/${d.month} · $hh:$mm';
  }

  Future<String?> _pedirTexto({
    required String titulo,
    required String hint,
    String? inicial,
  }) async {
    final ctrl = TextEditingController(text: inicial ?? '');
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ColoresLocales.superficie,
        title: Text(
          titulo,
          style: GoogleFonts.baloo2(
            fontWeight: FontWeight.w800,
            color: ColoresLocales.textoOnFondoClaro,
          ),
        ),
        content: TextField(
          controller: ctrl,
          maxLength: 120,
          maxLines: 3,
          autofocus: true,
          style: GoogleFonts.baloo2(
            color: ColoresLocales.textoOnFondoClaro,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.baloo2(
              color: ColoresLocales.textoSecundarioOnFondoClaro,
            ),
            filled: true,
            fillColor: ColoresLocales.superficieElevada,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancelar',
              style: GoogleFonts.baloo2(
                fontWeight: FontWeight.w700,
                color: ColoresLocales.textoSecundarioOnFondoClaro,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(
              'Confirmar',
              style: GoogleFonts.baloo2(
                fontWeight: FontWeight.w800,
                color: ColoresLocales.acentoVioleta,
              ),
            ),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return res;
  }

  Future<void> _proponer() async {
    final texto = await _pedirTexto(
      titulo: 'Publicar promo si te unís',
      hint: 'Ej: 2x1 en birra hasta las 00',
    );
    if (texto == null || texto.length < 3 || !mounted) return;
    await _ejecutar(
      () => _srv.pedidoResponder(
        idPlan: widget.idPlan,
        accion: 'proponer',
        contraoferta: texto,
      ),
      okMsg: 'Promo publicada. Ya aparece como beneficio confirmado.',
      accion: 'publicar la promo',
    );
  }

  Future<void> _aceptar() async {
    final pedido = _plan.textoPedidoActivo ?? 'el pedido';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ColoresLocales.superficie,
        title: Text(
          '¿Aceptar beneficio?',
          style: GoogleFonts.baloo2(
            fontWeight: FontWeight.w800,
            color: ColoresLocales.textoOnFondoClaro,
          ),
        ),
        content: Text(
          'Vas a confirmar: "$pedido"',
          style: GoogleFonts.baloo2(
            fontWeight: FontWeight.w600,
            color: ColoresLocales.textoSecundarioOnFondoClaro,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.baloo2(
                fontWeight: FontWeight.w700,
                color: ColoresLocales.textoSecundarioOnFondoClaro,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Aceptar beneficio',
              style: GoogleFonts.baloo2(
                fontWeight: FontWeight.w800,
                color: ColoresLocales.verdeFernet,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _ejecutar(
      () => _srv.pedidoResponder(idPlan: widget.idPlan, accion: 'aceptar'),
      okMsg: 'Pedido aceptado. El grupo ya fue notificado.',
      accion: 'aceptar el pedido',
    );
  }

  Future<void> _ofrecerOtraCosa() async {
    final texto = await _pedirTexto(
      titulo: 'Proponer otro beneficio',
      hint: 'Qué ofrecés en su lugar',
      inicial: _plan.beneficioContraoferta ?? _plan.pedidoBeneficio,
    );
    if (texto == null || texto.length < 3 || !mounted) return;
    await _ejecutar(
      () => _srv.pedidoResponder(
        idPlan: widget.idPlan,
        accion: 'contraoferta',
        contraoferta: texto,
      ),
      okMsg: 'Beneficio alternativo confirmado. El grupo ya fue notificado.',
      accion: 'ofrecer otro beneficio',
    );
  }

  Future<void> _cancelarPlan() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ColoresLocales.superficie,
        title: Text(
          '¿Cancelar este plan?',
          style: GoogleFonts.baloo2(
            fontWeight: FontWeight.w800,
            color: ColoresLocales.textoOnFondoClaro,
          ),
        ),
        content: Text(
          'Se cancela el plan y deja de aparecer como abierto. Esta acción no se puede deshacer.',
          style: GoogleFonts.baloo2(
            fontWeight: FontWeight.w600,
            color: ColoresLocales.textoSecundarioOnFondoClaro,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Volver',
              style: GoogleFonts.baloo2(
                fontWeight: FontWeight.w700,
                color: ColoresLocales.textoSecundarioOnFondoClaro,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Cancelar este plan',
              style: GoogleFonts.baloo2(
                fontWeight: FontWeight.w800,
                color: Colors.red.shade600,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _ejecutar(
      () => _srv.cancelar(widget.idPlan),
      okMsg: 'Plan cancelado. Dejó de estar disponible.',
      accion: 'cancelar este plan',
      popOnOk: true,
    );
  }

  Future<void> _ejecutar(
    Future<bool> Function() fn, {
    required String okMsg,
    String accion = 'completar la acción',
    bool popOnOk = false,
  }) async {
    if (_accionando) return;
    setState(() => _accionando = true);
    HapticFeedback.mediumImpact();
    bool ok = false;
    Object? error;
    try {
      ok = await fn();
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    setState(() => _accionando = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _srv.mensajeError(
              error ?? StateError('respuesta_invalida'),
              accion: accion,
            ),
            style: GoogleFonts.baloo2(fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          okMsg,
          style: GoogleFonts.baloo2(fontWeight: FontWeight.w700),
        ),
      ),
    );
    if (popOnOk) {
      Navigator.of(context).maybePop(true);
      return;
    }
    await _cargar();
  }

  Future<void> _abrirSolicitudes() async {
    if (!_plan.estaAbierto) return;
    String? procesandoId;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ColoresLocales.superficie,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final pendientes = (_detalle?.miembros ?? const <PlanLocalMiembro>[])
              .where((m) => m.estado.toLowerCase() == 'pendiente')
              .toList();

          Future<void> gestionar(
            PlanLocalMiembro miembro,
            String accion,
          ) async {
            if (procesandoId != null) return;
            procesandoId = miembro.idUsuario;
            setSheetState(() {});
            try {
              await _srv.gestionarMiembro(
                idPlan: widget.idPlan,
                idUsuario: miembro.idUsuario,
                accion: accion,
              );
              await _cargar();
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _srv.mensajeError(
                        e,
                        accion: accion == 'aceptar'
                            ? 'aceptar la solicitud'
                            : 'rechazar la solicitud',
                      ),
                      style: GoogleFonts.baloo2(fontWeight: FontWeight.w700),
                    ),
                  ),
                );
              }
            } finally {
              procesandoId = null;
              if (mounted) setSheetState(() {});
            }
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: ColoresLocales.textoSecundarioOnFondoClaro
                            .withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Aceptar solicitudes del plan',
                    style: GoogleFonts.baloo2(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      color: ColoresLocales.textoOnFondoClaro,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Acá ves quién pidió sumarse. Aceptá para meterlos al grupo '
                    'o rechazá si preferís dejarlos afuera.',
                    style: _muted,
                  ),
                  const SizedBox(height: 16),
                  if (pendientes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 20, 8, 24),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              CupertinoIcons.person_2,
                              size: 42,
                              color: ColoresLocales.acentoVioleta,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'No hay solicitudes pendientes',
                              textAlign: TextAlign.center,
                              style: _body,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Cuando alguien pida entrar, vas a poder decidirlo desde acá.',
                              textAlign: TextAlign.center,
                              style: _muted,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...pendientes.map(
                      (miembro) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 2,
                          ),
                          tileColor: ColoresLocales.superficieElevada,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: ColoresLocales.cardLavanda,
                            child: Icon(
                              CupertinoIcons.person_fill,
                              color: ColoresLocales.acentoVioleta,
                            ),
                          ),
                          title: Text(
                            miembro.nombre,
                            style: GoogleFonts.baloo2(
                              fontWeight: FontWeight.w800,
                              color: ColoresLocales.textoOnFondoClaro,
                            ),
                          ),
                          subtitle: Text(
                            miembro.username == null
                                ? 'Quiere sumarse al plan'
                                : '@${miembro.username}',
                            style: _muted,
                          ),
                          trailing: procesandoId == miembro.idUsuario
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Wrap(
                                  spacing: 2,
                                  children: [
                                    IconButton(
                                      tooltip: 'Rechazar',
                                      onPressed: () =>
                                          gestionar(miembro, 'rechazar'),
                                      icon: Icon(
                                        CupertinoIcons.xmark,
                                        color: Colors.red.shade600,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Aceptar',
                                      onPressed: () =>
                                          gestionar(miembro, 'aceptar'),
                                      icon: Icon(
                                        CupertinoIcons.check_mark,
                                        color: ColoresLocales.verdeFernet,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _abrirChat() {
    if (!_plan.estaAbierto) return;
    final miembros =
        _detalle?.miembros.where((m) => m.estado == 'aceptado').toList() ??
        const <PlanLocalMiembro>[];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalesChatPlan(plan: _plan, miembros: miembros),
      ),
    );
  }

  TextStyle get _body => GoogleFonts.baloo2(
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: ColoresLocales.textoOnFondoClaro,
  );

  TextStyle get _muted => GoogleFonts.baloo2(
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: ColoresLocales.textoSecundarioOnFondoClaro,
  );

  Widget _bloqueArchivado(PlanLocalItem plan) {
    final estado = plan.estado == 'cancelado'
        ? 'cancelado'
        : plan.estado == 'eliminado'
        ? 'eliminado'
        : 'finalizado';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ColoresLocales.superficie.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ColoresLocales.textoSecundarioOnFondoClaro.withValues(
            alpha: 0.18,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.archivebox,
                color: ColoresLocales.textoSecundarioOnFondoClaro,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Plan archivado',
                  style: GoogleFonts.baloo2(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: ColoresLocales.textoOnFondoClaro,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Este plan está $estado. El chat, las solicitudes y las acciones del beneficio quedan cerradas.',
            style: _muted,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(
                context,
              ).pushNamedAndRemoveUntil('/planes', (route) => route.isFirst),
              icon: const Icon(CupertinoIcons.square_grid_2x2),
              label: Text(
                'Volver al hub',
                style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: ColoresLocales.acentoVioletaMarca,
                side: BorderSide(
                  color: ColoresLocales.acentoVioletaMarca.withValues(
                    alpha: 0.45,
                  ),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final plan = _plan;
    final eyebrow = plan.tipoOrganizador == 'local'
        ? 'Publicaste un plan en tu local'
        : 'Crearon un plan en tu local';
    final nPersonas = plan.personasAceptadas;
    final fechas = plan.fechaFin == null
        ? 'Inicio ${_fmtFecha(plan.fechaInicio)}'
        : '${_fmtFecha(plan.fechaInicio)} → ${_fmtFecha(plan.fechaFin!)}';

    return Scaffold(
      backgroundColor: ColoresLocales.fondoClaro,
      appBar: AppBar(
        backgroundColor: ColoresLocales.superficie,
        elevation: 0,
        leading: IconButton(
          icon: Icon(CupertinoIcons.back, color: ColoresLocales.acentoVioleta),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Plan',
          style: GoogleFonts.baloo2(
            fontWeight: FontWeight.w800,
            color: ColoresLocales.tituloAcento,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _cargando ? null : _cargar,
            icon: Icon(
              CupertinoIcons.refresh,
              color: ColoresLocales.acentoVioleta,
            ),
          ),
        ],
      ),
      body: _cargando && _detalle == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _detalle == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.baloo2(
                        fontWeight: FontWeight.w700,
                        color: ColoresLocales.textoOnFondoClaro,
                      ),
                    ),
                    TextButton(
                      onPressed: _cargar,
                      child: Text(
                        'Reintentar',
                        style: GoogleFonts.baloo2(
                          fontWeight: FontWeight.w800,
                          color: ColoresLocales.acentoVioleta,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 40),
              children: [
                Text(
                  eyebrow,
                  style: GoogleFonts.baloo2(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ColoresLocales.acentoVioletaMarca,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  plan.titulo,
                  style: GoogleFonts.baloo2(
                    fontSize: 28,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    color: ColoresLocales.textoOnFondoClaro,
                  ),
                ),
                if (plan.descripcion.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(plan.descripcion.trim(), style: _muted),
                ],
                const SizedBox(height: 16),
                Text(
                  nPersonas == 1
                      ? '1 persona sumada'
                      : '$nPersonas personas sumadas',
                  style: _body,
                ),
                const SizedBox(height: 6),
                Text('Admin del plan: $_adminPlan', style: _body),
                const SizedBox(height: 6),
                Text(fechas, style: _muted),
                if (!plan.estaAbierto) ...[
                  const SizedBox(height: 18),
                  _bloqueArchivado(plan),
                ] else ...[
                  if (plan.modoLista == 'manual') ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _abrirSolicitudes,
                        icon: const Icon(CupertinoIcons.person_2),
                        label: Text(
                          'Aceptar solicitudes del plan',
                          style: GoogleFonts.baloo2(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ColoresLocales.acentoVioletaMarca,
                          side: BorderSide(
                            color: ColoresLocales.acentoVioletaMarca.withValues(
                              alpha: 0.55,
                            ),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: ColoresLocales.textoSecundarioOnFondoClaro
                        .withValues(alpha: 0.22),
                  ),
                  const SizedBox(height: 18),
                  ..._bloquePedido(plan),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed: !_accionando ? _abrirChat : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: ColoresLocales.acentoVioletaMarca,
                        disabledBackgroundColor: ColoresLocales
                            .acentoVioletaMarca
                            .withValues(alpha: 0.35),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        'Chat del plan',
                        style: GoogleFonts.baloo2(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: _accionando ? null : _cancelarPlan,
                      child: Text(
                        'Cancelar este plan',
                        style: GoogleFonts.baloo2(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.red.shade600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  List<Widget> _bloquePedido(PlanLocalItem plan) {
    if (plan.hayPedidoPendiente) {
      final texto = plan.textoPedidoActivo ?? '';
      return [
        Text('Pedido pendiente de "$_nombreGrupo"', style: _body),
        const SizedBox(height: 10),
        Text(
          'Todavía no está aceptado. Podés aceptar lo que piden, ofrecer otra '
          'cosa una sola vez, o simplemente ignorarlo (queda sin beneficio).',
          style: _muted,
        ),
        const SizedBox(height: 10),
        Text(
          texto.isEmpty ? '—' : texto,
          style: GoogleFonts.baloo2(
            fontSize: 22,
            height: 1.15,
            fontWeight: FontWeight.w900,
            color: ColoresLocales.acentoVioletaMarca,
          ),
        ),
        if (plan.pedidoVotos > 0) ...[
          const SizedBox(height: 8),
          Text(
            plan.pedidoVotos == 1
                ? '1 persona del plan apoya el pedido'
                : '${plan.pedidoVotos} personas del plan apoyan el pedido',
            style: _muted,
          ),
        ],
        if (plan.estaAbierto) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: _accionando ? null : _aceptar,
              style: FilledButton.styleFrom(
                backgroundColor: ColoresLocales.verdeFernet,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _accionando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Aceptar beneficio',
                      style: GoogleFonts.baloo2(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              onPressed: _accionando ? null : _ofrecerOtraCosa,
              style: OutlinedButton.styleFrom(
                foregroundColor: ColoresLocales.acentoVioletaMarca,
                side: BorderSide(
                  color: ColoresLocales.acentoVioletaMarca.withValues(
                    alpha: 0.55,
                  ),
                  width: 1.6,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'Proponer otro beneficio',
                style: GoogleFonts.baloo2(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ];
    }

    if (plan.beneficioAceptado) {
      final texto = plan.textoPedidoActivo ?? plan.beneficioLocal ?? '—';
      return [
        Text('Beneficio confirmado para el grupo:', style: _body),
        const SizedBox(height: 10),
        Text(
          texto,
          style: GoogleFonts.baloo2(
            fontSize: 20,
            height: 1.15,
            fontWeight: FontWeight.w900,
            color: ColoresLocales.verdeFernet,
          ),
        ),
      ];
    }

    return [
      Text('Todavía no hay un pedido de beneficio', style: _body),
      const SizedBox(height: 6),
      Text(
        'Podés publicar una promo si te unís. Se confirma una sola vez y queda visible para el grupo.',
        style: _muted,
      ),
      if (plan.estaAbierto) ...[
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: _accionando ? null : _proponer,
            style: OutlinedButton.styleFrom(
              foregroundColor: ColoresLocales.acentoVioletaMarca,
              side: BorderSide(
                color: ColoresLocales.acentoVioletaMarca.withValues(
                  alpha: 0.55,
                ),
                width: 1.6,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              'Publicar promo si te unís',
              style: GoogleFonts.baloo2(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    ];
  }
}
