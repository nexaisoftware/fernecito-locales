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
  });

  final String idPlan;
  final PlanLocalItem? inicial;

  @override
  State<LocalesPlanDashboard> createState() => _LocalesPlanDashboardState();
}

class _LocalesPlanDashboardState extends State<LocalesPlanDashboard> {
  final _srv = ServicioPlanesLocales.instancia;
  PlanLocalDetalle? _detalle;
  bool _cargando = true;
  bool _accionando = false;
  String? _error;

  PlanLocalItem get _plan =>
      _detalle?.plan ?? widget.inicial ?? _planFallback;

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
      titulo: 'Proponer beneficio',
      hint: 'Ej: 2x1 en birra hasta las 00',
    );
    if (texto == null || texto.length < 3 || !mounted) return;
    await _ejecutar(
      () => _srv.pedidoResponder(
        idPlan: widget.idPlan,
        accion: 'proponer',
        contraoferta: texto,
      ),
      okMsg: '¡Se puso la 10! Ya está en el chat del plan.',
    );
  }

  Future<void> _aceptar() async {
    final pedido = _plan.textoPedidoActivo ?? 'el pedido';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ColoresLocales.superficie,
        title: Text(
          '¿Aceptar propuesta?',
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
              'Aceptar',
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
      okMsg: '¡Se puso la 10! El grupo ya fue notificado.',
    );
  }

  Future<void> _cambiar() async {
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
      okMsg: 'Propuesta enviada al chat del plan.',
    );
  }

  Future<void> _rechazarPlan() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ColoresLocales.superficie,
        title: Text(
          '¿Rechazar plan?',
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
              'Rechazar',
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
      okMsg: 'Plan rechazado.',
      popOnOk: true,
    );
  }

  Future<void> _ejecutar(
    Future<bool> Function() fn, {
    required String okMsg,
    bool popOnOk = false,
  }) async {
    if (_accionando) return;
    setState(() => _accionando = true);
    HapticFeedback.mediumImpact();
    final ok = await fn();
    if (!mounted) return;
    setState(() => _accionando = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo completar la acción.',
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

  void _abrirChat() {
    final miembros = _detalle?.miembros
            .where((m) => m.estado == 'aceptado')
            .toList() ??
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
                        onPressed: plan.estaAbierto && !_accionando
                            ? _abrirChat
                            : null,
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
                    if (plan.estaAbierto) ...[
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          onPressed: _accionando ? null : _rechazarPlan,
                          child: Text(
                            'Rechazar plan',
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
        Text(
          'Las personas de "$_nombreGrupo" te pidieron:',
          style: _body,
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
                      'Aceptar propuesta',
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
              onPressed: _accionando ? null : _cambiar,
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
        Text('Ya les confirmaste este beneficio:', style: _body),
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
        if (plan.estaAbierto) ...[
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _accionando ? null : _proponer,
              child: Text(
                'Cambiar beneficio',
                style: GoogleFonts.baloo2(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: ColoresLocales.acentoVioletaMarca,
                ),
              ),
            ),
          ),
        ],
      ];
    }

    return [
      Text('Todavía no te pidieron nada', style: _body),
      const SizedBox(height: 6),
      Text(
        'Cuando el grupo arme un pedido aparece acá. También podés ofrecerles algo vos.',
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
                color: ColoresLocales.acentoVioletaMarca.withValues(alpha: 0.55),
                width: 1.6,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              'Proponer un beneficio',
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
