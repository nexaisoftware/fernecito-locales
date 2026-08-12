library;

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants.dart';
import '../core/servicio_planes_locales.dart';
import '../widgets/tema_locales_scope.dart';
import 'locales_crear_plan.dart';
import 'locales_plan_dashboard.dart';

class LocalesPlanes extends StatefulWidget {
  const LocalesPlanes({super.key});

  @override
  State<LocalesPlanes> createState() => _LocalesPlanesState();
}

class _LocalesPlanesState extends State<LocalesPlanes> {
  final _srv = ServicioPlanesLocales.instancia;
  List<PlanLocalItem> _items = const [];
  bool _cargando = true;
  bool _cargandoMas = false;
  bool _hayMas = false;
  String _query = '';
  Timer? _busquedaDebounce;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busquedaDebounce?.cancel();
    super.dispose();
  }

  Future<void> _cargar({bool silent = false, String? query}) async {
    final q = query ?? _query;
    if (!silent) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    final res = await _srv.hub(q: q);
    if (!mounted) return;
    setState(() {
      _items = res.items;
      _hayMas = res.hayMas;
      _error = res.error;
      _cargando = false;
    });
  }

  Future<void> _cargarMas() async {
    if (_cargandoMas || !_hayMas) return;
    setState(() => _cargandoMas = true);
    final res = await _srv.hub(offset: _items.length, q: _query);
    if (!mounted) return;
    setState(() {
      _items = [..._items, ...res.items];
      _hayMas = res.hayMas;
      _cargandoMas = false;
    });
  }

  Future<void> _abrir(PlanLocalItem plan) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: '/planes/detalle', arguments: plan.id),
        builder: (_) => LocalesPlanDashboard(idPlan: plan.id, inicial: plan),
      ),
    );
    if (mounted) _cargar(silent: true);
  }

  Future<void> _crearPlan() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        settings: const RouteSettings(name: '/planes/crear'),
        builder: (_) => const LocalesCrearPlan(),
      ),
    );
    if (mounted && ok == true) _cargar(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
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
          'Planes',
          style: GoogleFonts.baloo2(
            fontWeight: FontWeight.w800,
            color: ColoresLocales.tituloAcento,
            fontSize: 22,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              onChanged: (value) {
                setState(() => _query = value);
                _busquedaDebounce?.cancel();
                _busquedaDebounce = Timer(
                  const Duration(milliseconds: 350),
                  () {
                    if (mounted) _cargar();
                  },
                );
              },
              onSubmitted: (_) => _cargar(),
              style: GoogleFonts.baloo2(
                color: ColoresLocales.textoOnFondoClaro,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'Buscar planes',
                prefixIcon: Icon(
                  CupertinoIcons.search,
                  color: ColoresLocales.textoSecundarioOnFondoClaro,
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          setState(() => _query = '');
                          _busquedaDebounce?.cancel();
                          _cargar();
                        },
                        icon: const Icon(CupertinoIcons.xmark_circle_fill),
                      ),
                filled: true,
                fillColor: ColoresLocales.superficieElevada,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _crearPlan,
        backgroundColor: ColoresLocales.acentoVioletaMarca,
        foregroundColor: Colors.white,
        icon: const Icon(CupertinoIcons.add),
        label: Text(
          'Crear plan',
          style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
        ),
      ),
      body: RefreshIndicator(
        color: ColoresLocales.acentoVioleta,
        onRefresh: _cargar,
        child: _cargando
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null && _items.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 80),
                  Icon(
                    CupertinoIcons.exclamationmark_triangle,
                    size: 42,
                    color: ColoresLocales.textoSecundarioOnFondoClaro,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No se pudieron cargar los planes.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.baloo2(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: ColoresLocales.textoOnFondoClaro,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: _cargar,
                      child: Text(
                        'Reintentar',
                        style: GoogleFonts.baloo2(
                          fontWeight: FontWeight.w800,
                          color: ColoresLocales.acentoVioleta,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : _items.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(28),
                children: [
                  const SizedBox(height: 72),
                  Icon(
                    CupertinoIcons.calendar,
                    size: 48,
                    color: ColoresLocales.acentoVioleta,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Todavía no hay planes en tu local',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.baloo2(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: ColoresLocales.textoOnFondoClaro,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Cuando un grupo arme uno, o creá el tuyo.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.baloo2(
                      fontSize: 14,
                      height: 1.25,
                      fontWeight: FontWeight.w500,
                      color: ColoresLocales.textoSecundarioOnFondoClaro,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: FilledButton(
                      onPressed: _crearPlan,
                      style: FilledButton.styleFrom(
                        backgroundColor: ColoresLocales.acentoVioletaMarca,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                        'Crear plan',
                        style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: _items.length + (_hayMas ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i >= _items.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: _cargandoMas
                            ? const CircularProgressIndicator()
                            : TextButton(
                                onPressed: _cargarMas,
                                child: Text(
                                  'Ver más',
                                  style: GoogleFonts.baloo2(
                                    fontWeight: FontWeight.w800,
                                    color: ColoresLocales.acentoVioleta,
                                  ),
                                ),
                              ),
                      ),
                    );
                  }
                  final plan = _items[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _CardPlanLocal(
                      plan: plan,
                      onTap: plan.estaFinalizado ? null : () => _abrir(plan),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _CardPlanLocal extends StatelessWidget {
  const _CardPlanLocal({required this.plan, required this.onTap});
  final PlanLocalItem plan;
  final VoidCallback? onTap;

  Color get _color {
    final hex = plan.colorHex.replaceAll('#', '');
    if (hex.length == 6) {
      final v = int.tryParse(hex, radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
    return const Color(0xFFC084FC);
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final color = _color;
    final portada = plan.portadaUrl;
    final desactivada = plan.estaFinalizado;

    return Opacity(
      opacity: desactivada ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(26),
          child: Ink(
            height: 196,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.18),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (portada != null && portada.isNotEmpty)
                    Image.network(
                      portada,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ColoredBox(color: color),
                    )
                  else
                    ColoredBox(color: color),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.34),
                          Colors.black.withValues(alpha: 0.78),
                          Colors.black.withValues(alpha: 0.92),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                plan.nombreOrganizador,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.baloo2(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white.withValues(alpha: 0.9),
                                ),
                              ),
                            ),
                            _Pill(
                              plan.hayPedidoPendiente
                                  ? 'Pedido pendiente'
                                  : plan.beneficioAceptado
                                  ? 'Beneficio OK'
                                  : plan.estaAbierto
                                  ? 'Abierto'
                                  : plan.estado == 'cancelado'
                                  ? 'Cancelado'
                                  : 'Finalizado',
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          plan.titulo,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.baloo2(
                            fontSize: 21,
                            height: 1,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        if (plan.descripcion.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            plan.descripcion.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.baloo2(
                              fontSize: 12,
                              height: 1.15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.86),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _Pill('${plan.personasAceptadas} personas'),
                            _Pill('inicio ${_fmt(plan.fechaInicio)}'),
                            if (plan.fechaFin != null)
                              _Pill('fin ${_fmt(plan.fechaFin!)}'),
                            _Pill(
                              plan.modoLista == 'manual'
                                  ? 'con aprobación'
                                  : 'entrada libre',
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.28),
                              ),
                            ),
                            child: Text(
                              desactivada ? 'No disponible' : 'Abrir panel',
                              style: GoogleFonts.baloo2(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
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
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        texto,
        style: GoogleFonts.baloo2(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}
