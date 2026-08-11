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
          '¿Aceptar pedido?',
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
      titulo: 'Cambiar propuesta',
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

  Future<void> _ejecutar(
    Future<bool> Function() fn, {
    required String okMsg,
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
    await _cargar();
  }

  void _abrirChat() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalesChatPlan(plan: _plan),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final plan = _plan;
    final miembros = _detalle?.miembros
            .where((m) => m.estado == 'aceptado')
            .toList() ??
        const <PlanLocalMiembro>[];

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
          'Panel del plan',
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
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
                  children: [
                    _Seccion(
                      titulo: plan.titulo,
                      hijo: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (plan.descripcion.trim().isNotEmpty)
                            Text(
                              plan.descripcion.trim(),
                              style: GoogleFonts.baloo2(
                                fontSize: 14,
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                                color:
                                    ColoresLocales.textoSecundarioOnFondoClaro,
                              ),
                            ),
                          const SizedBox(height: 12),
                          _InfoRow(
                            icon: CupertinoIcons.person_fill,
                            label: 'Organiza',
                            value: plan.nombreOrganizador,
                          ),
                          _InfoRow(
                            icon: CupertinoIcons.calendar,
                            label: 'Inicio',
                            value: _fmtFecha(plan.fechaInicio),
                          ),
                          if (plan.fechaFin != null)
                            _InfoRow(
                              icon: CupertinoIcons.clock,
                              label: 'Fin',
                              value: _fmtFecha(plan.fechaFin!),
                            ),
                          _InfoRow(
                            icon: CupertinoIcons.location_solid,
                            label: 'Ciudad',
                            value: [
                              plan.ciudad,
                              if (plan.provincia != null &&
                                  plan.provincia!.trim().isNotEmpty)
                                plan.provincia!,
                            ].join(', '),
                          ),
                          _InfoRow(
                            icon: CupertinoIcons.person_2_fill,
                            label: 'Personas',
                            value: plan.cupoMax != null
                                ? '${plan.personasAceptadas}/${plan.cupoMax}'
                                : '${plan.personasAceptadas}',
                          ),
                          _InfoRow(
                            icon: CupertinoIcons.lock_fill,
                            label: 'Ingreso',
                            value: plan.modoLista == 'manual'
                                ? 'Con aprobación'
                                : 'Entrada libre',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _Seccion(
                      titulo: 'Beneficio / pedido',
                      hijo: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _EstadoBeneficio(plan: plan),
                          const SizedBox(height: 12),
                          if (plan.textoPedidoActivo != null) ...[
                            Text(
                              plan.textoPedidoActivo!,
                              style: GoogleFonts.baloo2(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: ColoresLocales.textoOnFondoClaro,
                              ),
                            ),
                            if (plan.pedidoVotos > 0) ...[
                              const SizedBox(height: 6),
                              Text(
                                '${plan.pedidoVotos} del grupo lo pidieron',
                                style: GoogleFonts.baloo2(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: ColoresLocales
                                      .textoSecundarioOnFondoClaro,
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                          ],
                          if (plan.estaAbierto) ...[
                            if (plan.sinPedido)
                              _BotonAccion(
                                texto: 'Proponer algo',
                                icon: CupertinoIcons.gift_fill,
                                color: ColoresLocales.acentoVioletaMarca,
                                cargando: _accionando,
                                onTap: _proponer,
                              )
                            else if (plan.hayPedidoPendiente) ...[
                              _BotonAccion(
                                texto: 'Aceptar pedido',
                                icon: CupertinoIcons.checkmark_circle_fill,
                                color: ColoresLocales.verdeFernet,
                                cargando: _accionando,
                                onTap: _aceptar,
                              ),
                              const SizedBox(height: 10),
                              _BotonAccion(
                                texto: 'Cambiar propuesta',
                                icon: CupertinoIcons.pencil_circle_fill,
                                color: ColoresLocales.acentoVioletaMarca,
                                outlined: true,
                                cargando: _accionando,
                                onTap: _cambiar,
                              ),
                            ] else if (plan.beneficioAceptado) ...[
                              _BotonAccion(
                                texto: 'Cambiar beneficio',
                                icon: CupertinoIcons.pencil_circle_fill,
                                color: ColoresLocales.acentoVioletaMarca,
                                outlined: true,
                                cargando: _accionando,
                                onTap: _proponer,
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _BotonAccion(
                      texto: 'Abrir chat del plan',
                      icon: CupertinoIcons.chat_bubble_2_fill,
                      color: ColoresLocales.acentoVioletaMarca,
                      grande: true,
                      onTap: plan.estaAbierto ? _abrirChat : null,
                    ),
                    if (!plan.estaAbierto) ...[
                      const SizedBox(height: 8),
                      Text(
                        'El plan ya no está abierto; el chat queda solo lectura desde la app de usuarios.',
                        style: GoogleFonts.baloo2(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: ColoresLocales.textoSecundarioOnFondoClaro,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _Seccion(
                      titulo: 'Quién está adentro (${miembros.length})',
                      hijo: miembros.isEmpty
                          ? Text(
                              'Todavía no hay personas aceptadas.',
                              style: GoogleFonts.baloo2(
                                fontWeight: FontWeight.w600,
                                color:
                                    ColoresLocales.textoSecundarioOnFondoClaro,
                              ),
                            )
                          : Column(
                              children: [
                                for (final m in miembros.take(24))
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundColor:
                                              ColoresLocales.superficieElevada,
                                          backgroundImage: m.fotoUrl != null
                                              ? NetworkImage(m.fotoUrl!)
                                              : null,
                                          child: m.fotoUrl == null
                                              ? Icon(
                                                  CupertinoIcons.person_fill,
                                                  size: 18,
                                                  color: ColoresLocales
                                                      .textoSecundarioOnFondoClaro,
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                m.nombre,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.baloo2(
                                                  fontWeight: FontWeight.w800,
                                                  color: ColoresLocales
                                                      .textoOnFondoClaro,
                                                ),
                                              ),
                                              if (m.rol == 'organizador' ||
                                                  (m.nombreSquad ?? '')
                                                      .isNotEmpty)
                                                Text(
                                                  m.rol == 'organizador'
                                                      ? 'Organizador'
                                                      : m.nombreSquad!,
                                                  style: GoogleFonts.baloo2(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: ColoresLocales
                                                        .textoSecundarioOnFondoClaro,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    if (plan.contactoAnfitrion != null &&
                        plan.contactoAnfitrion!.trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _Seccion(
                        titulo: plan.contactoModo == 'colaborar'
                            ? 'Contacto para colaborar'
                            : 'Contacto del anfitrión',
                        hijo: Text(
                          plan.contactoAnfitrion!,
                          style: GoogleFonts.baloo2(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: ColoresLocales.textoOnFondoClaro,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo, required this.hijo});
  final String titulo;
  final Widget hijo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: ColoresLocales.decoracionCard(sinBorde: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: GoogleFonts.baloo2(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: ColoresLocales.tituloAcento,
            ),
          ),
          const SizedBox(height: 10),
          hijo,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: ColoresLocales.acentoVioleta),
          const SizedBox(width: 8),
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: GoogleFonts.baloo2(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: ColoresLocales.textoSecundarioOnFondoClaro,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.baloo2(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: ColoresLocales.textoOnFondoClaro,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EstadoBeneficio extends StatelessWidget {
  const _EstadoBeneficio({required this.plan});
  final PlanLocalItem plan;

  @override
  Widget build(BuildContext context) {
    final (texto, color) = switch (plan.beneficioEstado) {
      'pedido' => ('El grupo te pidió algo', ColoresLocales.acentoVioletaMarca),
      'contraoferta' => (
          'Hay una contraoferta tuya',
          const Color(0xFFD97706),
        ),
      'aceptado' => ('Beneficio confirmado', ColoresLocales.verdeFernet),
      'rechazado' => (
          'Sin beneficio activo',
          ColoresLocales.textoSecundarioOnFondoClaro,
        ),
      _ => (
          'Todavía no hay pedido',
          ColoresLocales.textoSecundarioOnFondoClaro,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        texto,
        style: GoogleFonts.baloo2(
          fontSize: 13.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _BotonAccion extends StatelessWidget {
  const _BotonAccion({
    required this.texto,
    required this.icon,
    required this.color,
    this.onTap,
    this.cargando = false,
    this.outlined = false,
    this.grande = false,
  });

  final String texto;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool cargando;
  final bool outlined;
  final bool grande;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !cargando;
    return SizedBox(
      width: double.infinity,
      height: grande ? 58 : 50,
      child: Material(
        color: outlined ? Colors.transparent : color.withValues(alpha: enabled ? 1 : 0.45),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: outlined
                  ? Border.all(color: color.withValues(alpha: 0.55), width: 1.6)
                  : null,
              color: outlined ? color.withValues(alpha: 0.08) : null,
            ),
            child: Center(
              child: cargando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icon,
                          color: outlined ? color : Colors.white,
                          size: grande ? 22 : 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          texto,
                          style: GoogleFonts.baloo2(
                            fontSize: grande ? 17 : 15,
                            fontWeight: FontWeight.w800,
                            color: outlined ? color : Colors.white,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
