library;

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants.dart';
import '../widgets/tema_locales_scope.dart';
import '../core/formato_metricas.dart';
import '../core/servicio_metricas_locales.dart';
import '../models/actividad_metrica.dart';
import '../models/datos_impresiones.dart';

enum _PestanaMetricas { actividad, alcance, rendimientos }

class LocalesMetricas extends StatefulWidget {
  const LocalesMetricas({super.key});

  @override
  State<LocalesMetricas> createState() => _LocalesMetricasState();
}

class _LocalesMetricasState extends State<LocalesMetricas> {
  final _servicio = ServicioMetricasLocales();

  _PestanaMetricas _pestana = _PestanaMetricas.alcance;
  final Set<CategoriaActividadMetrica> _categoriasFiltro = {};
  String? _actorFiltroId;
  List<ActorMetricaOpcion> _actores = const [ActorMetricaOpcion.todos];
  int _rangoDias = 30;
  int _rangoAlcanceDias = 7;
  AlcanceFiltroMetricas _filtroAlcance = const AlcanceFiltroMetricas();

  List<ActividadMetricaItem> _actividad = const [];
  DatosRendimientoMetricas _rendimiento = DatosRendimientoMetricas.vacio;
  DatosImpresionesMetricas _alcance = DatosImpresionesMetricas.vacio;
  List<EventoImpresionResumen> _catalogoEventosAlcance = const [];

  bool _cargandoActividad = true;
  bool _cargandoRendimiento = true;
  bool _cargandoAlcance = true;
  String? _errorActividad;
  String? _errorRendimiento;
  String? _errorAlcance;
  int _visibleActividad = 30;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  Future<void> _cargarTodo() async {
    await Future.wait([
      _cargarActividad(resetVisible: true),
      _cargarRendimiento(),
      _cargarAlcance(),
    ]);
  }

  Future<void> _cargarActividad({bool resetVisible = false}) async {
    setState(() {
      _cargandoActividad = true;
      _errorActividad = null;
      if (resetVisible) _visibleActividad = 30;
    });
    try {
      final results = await Future.wait([
        _servicio.cargarActividad(),
        _servicio.cargarActoresFiltro(),
      ]);
      if (!mounted) return;
      setState(() {
        _actividad = results[0] as List<ActividadMetricaItem>;
        _actores = results[1] as List<ActorMetricaOpcion>;
        _cargandoActividad = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorActividad = 'No se pudo cargar la actividad.';
        _cargandoActividad = false;
      });
    }
  }

  Future<void> _cargarAlcance() async {
    setState(() {
      _cargandoAlcance = true;
      _errorAlcance = null;
    });
    try {
      final datos = await _servicio.cargarImpresiones(
        dias: _rangoAlcanceDias,
        filtro: _filtroAlcance,
      );
      if (!mounted) return;
      setState(() {
        _alcance = datos;
        if (_filtroAlcance.tipo == AlcanceFiltroTipo.todas) {
          _catalogoEventosAlcance = datos.eventos;
        }
        _cargandoAlcance = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorAlcance = 'No se pudieron cargar las impresiones.';
        _cargandoAlcance = false;
      });
    }
  }

  Future<void> _abrirFiltroAlcance() async {
    if (_catalogoEventosAlcance.isEmpty &&
        _filtroAlcance.tipo != AlcanceFiltroTipo.todas) {
      try {
        final todas = await _servicio.cargarImpresiones(
          dias: _rangoAlcanceDias,
        );
        _catalogoEventosAlcance = todas.eventos;
      } catch (_) {}
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: ColoresLocales.superficie,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text(
                  'Filtrar impresiones',
                  style: GoogleFonts.baloo2(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: ColoresLocales.acentoVioleta,
                  ),
                ),
              ),
              ListTile(
                title: Text(
                  'Todas',
                  style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
                ),
                trailing: _filtroAlcance.tipo == AlcanceFiltroTipo.todas
                    ? Icon(
                        CupertinoIcons.checkmark,
                        color: ColoresLocales.acentoVioleta,
                      )
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(
                    () => _filtroAlcance = const AlcanceFiltroMetricas(),
                  );
                  _cargarAlcance();
                },
              ),
              ListTile(
                title: Text(
                  'Visitas a mi perfil',
                  style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
                ),
                trailing: _filtroAlcance.tipo == AlcanceFiltroTipo.perfil
                    ? Icon(
                        CupertinoIcons.checkmark,
                        color: ColoresLocales.acentoVioleta,
                      )
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(
                    () => _filtroAlcance = const AlcanceFiltroMetricas(
                      tipo: AlcanceFiltroTipo.perfil,
                    ),
                  );
                  _cargarAlcance();
                },
              ),
              if (_catalogoEventosAlcance.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Por evento',
                      style: GoogleFonts.baloo2(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: ColoresLocales.textoSecundarioOnFondoClaro,
                      ),
                    ),
                  ),
                ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _catalogoEventosAlcance.length,
                  itemBuilder: (ctx, i) {
                    final ev = _catalogoEventosAlcance[i];
                    final sel =
                        _filtroAlcance.tipo == AlcanceFiltroTipo.evento &&
                        _filtroAlcance.idEvento == ev.idEvento;
                    return ListTile(
                      title: Text(
                        ev.titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.baloo2(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${formatoMetricaCompacto(ev.conteo)} impresiones',
                        style: GoogleFonts.baloo2(
                          fontSize: 12,
                          color: ColoresLocales.textoSecundarioOnFondoClaro,
                        ),
                      ),
                      trailing: sel
                          ? Icon(
                              CupertinoIcons.checkmark,
                              color: ColoresLocales.acentoVioleta,
                            )
                          : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(
                          () => _filtroAlcance = AlcanceFiltroMetricas(
                            tipo: AlcanceFiltroTipo.evento,
                            idEvento: ev.idEvento,
                            etiquetaEvento: ev.titulo,
                          ),
                        );
                        _cargarAlcance();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _cargarRendimiento() async {
    setState(() {
      _cargandoRendimiento = true;
      _errorRendimiento = null;
    });
    try {
      final datos = await _servicio.cargarRendimiento(dias: _rangoDias);
      if (!mounted) return;
      setState(() {
        _rendimiento = datos;
        _cargandoRendimiento = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorRendimiento = 'No se pudieron cargar los rendimientos.';
        _cargandoRendimiento = false;
      });
    }
  }

  List<ActividadMetricaItem> get _actividadFiltrada {
    return _actividad.where((a) {
      if (_categoriasFiltro.isNotEmpty &&
          !_categoriasFiltro.contains(a.categoria)) {
        return false;
      }
      if (_actorFiltroId != null && a.idActor != _actorFiltroId) {
        return false;
      }
      return true;
    }).toList();
  }

  static const _chipsCategoria = [
    CategoriaActividadMetrica.listaAceptada,
    CategoriaActividadMetrica.listaRechazada,
    CategoriaActividadMetrica.invitacionQr,
    CategoriaActividadMetrica.qrPase,
    CategoriaActividadMetrica.qrPromo,
    CategoriaActividadMetrica.eventoPublicado,
    CategoriaActividadMetrica.eventoFinalizado,
    CategoriaActividadMetrica.eventoCancelado,
  ];

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return Scaffold(
      backgroundColor: ColoresLocales.fondoClaro,
      appBar: AppBar(
        backgroundColor: ColoresLocales.fondoClaro,
        elevation: 0,
        surfaceTintColor: ColoresLocales.fondoClaro,
        centerTitle: true,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: Icon(
            CupertinoIcons.chevron_back,
            color: ColoresLocales.acentoVioleta,
          ),
        ),
        title: Text(
          'Métricas',
          style: GoogleFonts.baloo2(
            fontWeight: FontWeight.w900,
            color: ColoresLocales.acentoVioleta,
            fontSize: 18,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: _buildSwitchPestanas(),
          ),
          Expanded(
            child: RefreshIndicator(
              color: ColoresLocales.acentoVioleta,
              onRefresh: _cargarTodo,
              child: switch (_pestana) {
                _PestanaMetricas.actividad => _buildPestanaActividad(),
                _PestanaMetricas.alcance => _buildPestanaAlcance(),
                _PestanaMetricas.rendimientos => _buildPestanaRendimientos(),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchPestanas() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: ColoresLocales.superficie,
        borderRadius: BorderRadius.circular(50),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final idx = _pestana.index;
          final tabW = w / 3;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: 4 + idx * tabW,
                top: 4,
                bottom: 4,
                width: tabW - 6,
                child: Container(
                  decoration: BoxDecoration(
                    color: ColoresLocales.acentoVioleta,
                    borderRadius: BorderRadius.circular(50),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _opcionPestana(
                      'Actividad',
                      CupertinoIcons.list_bullet,
                      _pestana == _PestanaMetricas.actividad,
                      () =>
                          setState(() => _pestana = _PestanaMetricas.actividad),
                    ),
                  ),
                  Expanded(
                    child: _opcionPestana(
                      'Alcance',
                      CupertinoIcons.eye_fill,
                      _pestana == _PestanaMetricas.alcance,
                      () => setState(() => _pestana = _PestanaMetricas.alcance),
                    ),
                  ),
                  Expanded(
                    child: _opcionPestana(
                      'Rendim.',
                      CupertinoIcons.chart_bar_alt_fill,
                      _pestana == _PestanaMetricas.rendimientos,
                      () => setState(
                        () => _pestana = _PestanaMetricas.rendimientos,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _opcionPestana(
    String label,
    IconData icon,
    bool activo,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: activo ? Colors.white : ColoresLocales.acentoVioleta,
            ),
            SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.baloo2(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: activo ? Colors.white : ColoresLocales.acentoVioleta,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPestanaActividad() {
    if (_cargandoActividad) {
      return CustomScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            child: Center(
              child: CircularProgressIndicator(
                color: ColoresLocales.acentoVioleta,
              ),
            ),
          ),
        ],
      );
    }

    if (_errorActividad != null) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            child: _buildError(_errorActividad!, _cargarActividad),
          ),
        ],
      );
    }

    final filtrada = _actividadFiltrada;
    final visibles = filtrada.take(_visibleActividad).toList();
    final hayMas = filtrada.length > _visibleActividad;

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildFiltrosActividad()),
        if (filtrada.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '${filtrada.length} movimiento${filtrada.length == 1 ? '' : 's'}',
                style: GoogleFonts.baloo2(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ColoresLocales.textoSecundarioOnFondoClaro,
                ),
              ),
            ),
          ),
        if (filtrada.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildVacioActividad(),
          )
        else ...[
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: _TileActividad(item: visibles[i]),
                ),
                childCount: visibles.length,
              ),
            ),
          ),
          if (hayMas)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 24),
                child: CupertinoButton(
                  color: ColoresLocales.chipInactivo,
                  borderRadius: BorderRadius.circular(50),
                  onPressed: () => setState(() => _visibleActividad += 30),
                  child: Text(
                    'Ver más (${filtrada.length - _visibleActividad} restantes)',
                    style: GoogleFonts.baloo2(
                      fontWeight: FontWeight.w800,
                      color: ColoresLocales.acentoVioleta,
                    ),
                  ),
                ),
              ),
            )
          else
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ],
    );
  }

  Widget _buildFiltrosActividad() {
    final actorSel = _actores.firstWhere(
      (a) => a.id == _actorFiltroId,
      orElse: () => ActorMetricaOpcion.todos,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: ColoresLocales.rellenoInput,
              borderRadius: BorderRadius.circular(14),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                isExpanded: true,
                value: _actorFiltroId,
                icon: Icon(
                  CupertinoIcons.chevron_down,
                  size: 16,
                  color: ColoresLocales.acentoVioleta,
                ),
                style: GoogleFonts.baloo2(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: ColoresLocales.textoOnFondoClaro,
                ),
                items: _actores
                    .map(
                      (a) => DropdownMenuItem<String?>(
                        value: a.id,
                        child: Text(
                          a.etiqueta,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.baloo2(
                            fontWeight: a.id == _actorFiltroId
                                ? FontWeight.w900
                                : FontWeight.w600,
                            color: a.activo || a.esLocal || a.id == null
                                ? ColoresLocales.textoOnFondoClaro
                                : ColoresLocales.textoSecundarioOnFondoClaro,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _actorFiltroId = v;
                    _visibleActividad = 30;
                  });
                },
              ),
            ),
          ),
        ),
        if (_actorFiltroId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              'Filtrando por: ${actorSel.etiqueta}',
              style: GoogleFonts.baloo2(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: ColoresLocales.acentoVioleta,
              ),
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              _chipCategoriaTodas(),
              for (final c in _chipsCategoria) _chipCategoria(c),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chipCategoriaTodas() {
    final activo = _categoriasFiltro.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(
          'Todas',
          style: GoogleFonts.baloo2(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: activo ? Colors.white : ColoresLocales.acentoVioleta,
          ),
        ),
        selected: activo,
        onSelected: (_) {
          setState(() {
            _categoriasFiltro.clear();
            _visibleActividad = 30;
          });
        },
        selectedColor: ColoresLocales.acentoVioleta,
        backgroundColor: ColoresLocales.superficie,
        side: BorderSide.none,
        showCheckmark: false,
      ),
    );
  }

  Widget _chipCategoria(CategoriaActividadMetrica categoria) {
    final activo = _categoriasFiltro.contains(categoria);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(
          categoria.etiquetaChip,
          style: GoogleFonts.baloo2(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: activo ? Colors.white : ColoresLocales.acentoVioleta,
          ),
        ),
        selected: activo,
        onSelected: (selected) {
          setState(() {
            if (selected) {
              _categoriasFiltro.add(categoria);
            } else {
              _categoriasFiltro.remove(categoria);
            }
            _visibleActividad = 30;
          });
        },
        selectedColor: ColoresLocales.acentoVioleta,
        backgroundColor: ColoresLocales.superficie,
        side: BorderSide.none,
        showCheckmark: false,
      ),
    );
  }

  Widget _buildVacioActividad() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.tray,
              size: 48,
              color: ColoresLocales.acentoVioleta.withOpacity(0.35),
            ),
            SizedBox(height: 12),
            Text(
              'Sin actividad todavía',
              style: GoogleFonts.baloo2(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: ColoresLocales.textoOnFondoClaro,
              ),
            ),
            SizedBox(height: 6),
            Text(
              _categoriasFiltro.isEmpty && _actorFiltroId == null
                  ? 'Cuando publiques eventos, aceptes listas o canjees promos, lo vas a ver acá.'
                  : 'No hay movimientos con los filtros seleccionados. Probá ampliar tipos o cambiar quién realizó la acción.',
              textAlign: TextAlign.center,
              style: GoogleFonts.baloo2(
                fontSize: 13,
                color: ColoresLocales.textoSecundarioOnFondoClaro,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPestanaRendimientos() {
    if (_cargandoRendimiento) {
      return CustomScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            child: Center(
              child: CircularProgressIndicator(
                color: ColoresLocales.acentoVioleta,
              ),
            ),
          ),
        ],
      );
    }

    if (_errorRendimiento != null) {
      return CustomScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            child: _buildError(_errorRendimiento!, _cargarRendimiento),
          ),
        ],
      );
    }

    final r = _rendimiento;
    final unidadTiempo = _rangoDias >= 60 ? 'semana' : 'día';
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildChipsRango()),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _GraficoLineaMetricas(
                titulo: 'Tráfico en tu local',
                subtitulo:
                    'Vista general · reservas + ingresos + promos por $unidadTiempo',
                color: ColoresLocales.acentoVioleta,
                puntos: r.traficoPorDia,
                rangoDias: _rangoDias,
              ),
              const SizedBox(height: 14),
              _buildKpiRow(r),
              const SizedBox(height: 14),
              _GraficoBarrasMetricas(
                titulo: 'Ingresos canjeados',
                subtitulo: 'Entradas en puerta por $unidadTiempo',
                color: ColoresMetricas.canje,
                puntos: r.canjesEntradasPorDia,
                rangoDias: _rangoDias,
              ),
              SizedBox(height: 14),
              _GraficoBarrasMetricas(
                titulo: 'Reservas aceptadas',
                subtitulo: 'Listas confirmadas por $unidadTiempo',
                color: ColoresMetricas.aceptado,
                puntos: r.reservasPorDia,
                rangoDias: _rangoDias,
              ),
              const SizedBox(height: 14),
              _GraficoBarrasMetricas(
                titulo: 'Promos canjeadas',
                subtitulo: 'Canjes de promoción por $unidadTiempo',
                color: ColoresMetricas.publicado,
                puntos: r.promosCanjeadasPorDia,
                rangoDias: _rangoDias,
              ),
              SizedBox(height: 14),
              _GraficoBarrasMetricas(
                titulo: 'Top eventos por canjes',
                subtitulo: 'Acumulado histórico del local',
                color: ColoresLocales.acentoVioleta,
                puntos: r.topEventosCanjes,
                rangoDias: _rangoDias,
                esRanking: true,
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildPestanaAlcance() {
    if (_cargandoAlcance) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            child: Center(
              child: CircularProgressIndicator(
                color: ColoresLocales.acentoVioleta,
              ),
            ),
          ),
        ],
      );
    }

    if (_errorAlcance != null) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            child: _buildError(_errorAlcance!, _cargarAlcance),
          ),
        ],
      );
    }

    final a = _alcance;
    final unidad = _rangoAlcanceDias == 1 ? 'hoy' : 'día';

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildChipsRangoAlcance()),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Material(
                color: ColoresLocales.superficie,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _abrirFiltroAlcance,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.slider_horizontal_3,
                          size: 18,
                          color: ColoresLocales.acentoVioleta,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _filtroAlcance.etiquetaUi,
                            style: GoogleFonts.baloo2(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              color: ColoresLocales.textoOnFondoClaro,
                            ),
                          ),
                        ),
                        Icon(
                          CupertinoIcons.chevron_down,
                          size: 14,
                          color: ColoresLocales.textoSecundarioOnFondoClaro,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (_rangoAlcanceDias == 1)
                _ResumenImpresionesHoy(
                  total: a.totalImpresiones,
                  perfil: a.totalPerfil,
                  clicks: a.totalClicks,
                )
              else
                _GraficoLineaMetricas(
                  titulo: 'Impresiones',
                  subtitulo: 'Vistas en cartelera, perfil y clicks · por $unidad',
                  color: const Color(0xFF0891B2),
                  puntos: a.seriePorDia,
                  rangoDias: _rangoAlcanceDias,
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _KpiCard(
                      label: 'Total',
                      valor: formatoMetricaCompacto(a.totalImpresiones),
                      icon: CupertinoIcons.eye_fill,
                      color: const Color(0xFF0891B2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _KpiCard(
                      label: 'Visitas perfil',
                      valor: formatoMetricaCompacto(a.totalPerfil),
                      icon: CupertinoIcons.person_crop_circle_fill,
                      color: ColoresLocales.acentoVioleta,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _KpiCard(
                      label: 'Clicks',
                      valor: formatoMetricaCompacto(a.totalClicks),
                      icon: CupertinoIcons.hand_point_right_fill,
                      color: ColoresMetricas.canje,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Visitas perfil = veces que alguien abrió tu ficha en la app de usuarios.',
                style: GoogleFonts.baloo2(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: ColoresLocales.textoSecundarioOnFondoClaro,
                  height: 1.3,
                ),
              ),
              if (_filtroAlcance.tipo == AlcanceFiltroTipo.todas &&
                  a.eventos.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  'Por evento',
                  style: GoogleFonts.baloo2(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: ColoresLocales.tituloAcento,
                  ),
                ),
                const SizedBox(height: 8),
                ...a.eventos
                    .take(12)
                    .map(
                      (ev) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: ColoresLocales.superficie,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              setState(
                                () => _filtroAlcance = AlcanceFiltroMetricas(
                                  tipo: AlcanceFiltroTipo.evento,
                                  idEvento: ev.idEvento,
                                  etiquetaEvento: ev.titulo,
                                ),
                              );
                              _cargarAlcance();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      ev.titulo,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.baloo2(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    CupertinoIcons.eye_fill,
                                    size: 14,
                                    color: ColoresLocales.acentoVioleta,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    formatoMetricaCompacto(ev.conteo),
                                    style: GoogleFonts.baloo2(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                      color: ColoresLocales.acentoVioleta,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
              ] else if (a.totalImpresiones == 0)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Center(
                    child: Text(
                      'Todavía no hay impresiones en este período.\nCuando vean tus eventos en cartelera o abran tu perfil, aparece acá.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.baloo2(
                        fontSize: 13,
                        color: ColoresLocales.textoSecundarioOnFondoClaro,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildChipsRangoAlcance() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          _chipRangoAlcance('Hoy', 1),
          _chipRangoAlcance('7 días', 7),
          _chipRangoAlcance('30 días', 30),
        ],
      ),
    );
  }

  Widget _chipRangoAlcance(String label, int dias) {
    final activo = _rangoAlcanceDias == dias;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(
          label,
          style: GoogleFonts.baloo2(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: activo ? Colors.white : ColoresLocales.acentoVioleta,
          ),
        ),
        selected: activo,
        onSelected: (_) {
          setState(() => _rangoAlcanceDias = dias);
          _cargarAlcance();
        },
        selectedColor: ColoresLocales.acentoVioleta,
        backgroundColor: ColoresLocales.superficie,
        checkmarkColor: ColoresLocales.textoEnBoton,
        side: BorderSide.none,
        showCheckmark: false,
      ),
    );
  }

  Widget _buildChipsRango() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          _chipRango('7 días', 7),
          _chipRango('30 días', 30),
          _chipRango('90 días', 90),
        ],
      ),
    );
  }

  Widget _chipRango(String label, int dias) {
    final activo = _rangoDias == dias;
    return Padding(
      padding: EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(
          label,
          style: GoogleFonts.baloo2(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: activo ? Colors.white : ColoresLocales.acentoVioleta,
          ),
        ),
        selected: activo,
        onSelected: (_) {
          setState(() => _rangoDias = dias);
          _cargarRendimiento();
        },
        selectedColor: ColoresLocales.acentoVioleta,
        backgroundColor: ColoresLocales.superficie,
        checkmarkColor: ColoresLocales.textoEnBoton,
        side: BorderSide.none,
        showCheckmark: false,
      ),
    );
  }

  Widget _buildKpiRow(DatosRendimientoMetricas r) {
    return Row(
      children: [
        Expanded(
          child: _KpiCard(
            label: 'Tráfico',
            valor: formatoMetricaCompacto(r.totalTrafico),
            icon: CupertinoIcons.waveform_path_ecg,
            color: ColoresLocales.acentoVioleta,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            label: 'Reservas',
            valor: formatoMetricaCompacto(r.totalReservas),
            icon: IconosLocales.exito,
            color: ColoresMetricas.aceptado,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            label: 'Ingresos',
            valor: formatoMetricaCompacto(r.totalCanjesEntradas),
            icon: CupertinoIcons.qrcode_viewfinder,
            color: ColoresMetricas.canje,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _KpiCard(
            label: 'Promos',
            valor: formatoMetricaCompacto(r.totalPromosCanjeadas),
            icon: CupertinoIcons.gift_fill,
            color: ColoresMetricas.publicado,
          ),
        ),
      ],
    );
  }

  Widget _buildError(String msg, Future<void> Function() retry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              msg,
              textAlign: TextAlign.center,
              style: GoogleFonts.baloo2(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ColoresLocales.textoOnFondoClaro,
              ),
            ),
            const SizedBox(height: 12),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              color: ColoresLocales.acentoVioleta,
              borderRadius: BorderRadius.circular(50),
              onPressed: () => retry(),
              child: Text(
                'Reintentar',
                style: GoogleFonts.baloo2(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _fmtFechaActividad(DateTime d) {
  final l = d.toLocal();
  final dd = l.day.toString().padLeft(2, '0');
  final mm = l.month.toString().padLeft(2, '0');
  final hh = l.hour.toString().padLeft(2, '0');
  final min = l.minute.toString().padLeft(2, '0');
  return '$dd/$mm · $hh:$min';
}

String _etiquetaEjeY(double value, double maxY) {
  if (maxY >= 1000) return formatoMetricaCompacto(value);
  return value.toInt().toString();
}

// ─── Tile actividad ────────────────────────────────────────────────────────────

class _TileActividad extends StatelessWidget {
  const _TileActividad({required this.item});

  final ActividadMetricaItem item;

  String get _tipoLabel => item.categoria.etiquetaChip;

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final fecha = _fmtFechaActividad(item.fecha);
    final lineaActor = item.lineaActor;

    return Container(
      decoration: ColoresLocales.decoracionCard(sinBorde: true, radius: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: item.colorEstado.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item.icono, color: item.colorEstado, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: item.colorEstado.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Text(
                          item.estadoLabel,
                          style: GoogleFonts.baloo2(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: item.colorEstado,
                          ),
                        ),
                      ),
                      SizedBox(width: 6),
                      Text(
                        _tipoLabel,
                        style: GoogleFonts.baloo2(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: ColoresLocales.textoSecundarioOnFondoClaro,
                        ),
                      ),
                      Spacer(),
                      Text(
                        fecha,
                        style: GoogleFonts.baloo2(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: ColoresLocales.textoSecundarioOnFondoClaro,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Text(
                    item.titulo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.baloo2(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                      color: ColoresLocales.textoOnFondoClaro,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    item.subtitulo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.baloo2(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                      color: ColoresLocales.textoSecundarioOnFondoClaro,
                    ),
                  ),
                  if (lineaActor != null) ...[
                    SizedBox(height: 4),
                    Text(
                      lineaActor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.baloo2(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: ColoresLocales.acentoVioleta.withValues(
                          alpha: 0.85,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── KPI + gráficos ──────────────────────────────────────────────────────────

/// Vista de un solo día: la DB guarda agregados diarios (sin desglose por hora).
class _ResumenImpresionesHoy extends StatelessWidget {
  const _ResumenImpresionesHoy({
    required this.total,
    required this.perfil,
    required this.clicks,
  });

  final int total;
  final int perfil;
  final int clicks;

  int get _cartelera => math.max(0, total - perfil - clicks);

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final hoy = DateTime.now();
    final fechaLabel = '${hoy.day}/${hoy.month}';
    const colorCartelera = Color(0xFF0891B2);
    final colorPerfil = ColoresLocales.acentoVioleta;
    const colorClicks = ColoresMetricas.canje;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: ColoresLocales.decoracionCard(sinBorde: true, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Impresiones de hoy',
            style: GoogleFonts.baloo2(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: ColoresLocales.textoOnFondoClaro,
            ),
          ),
          Text(
            'Acumulado $fechaLabel · datos por día (sin desglose horario)',
            style: GoogleFonts.baloo2(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ColoresLocales.textoSecundarioOnFondoClaro,
            ),
          ),
          const SizedBox(height: 16),
          if (total <= 0)
            SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  'Sin impresiones registradas hoy',
                  style: GoogleFonts.baloo2(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ColoresLocales.textoSecundarioOnFondoClaro,
                  ),
                ),
              ),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(
                  CupertinoIcons.eye_fill,
                  size: 28,
                  color: colorCartelera.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 10),
                Text(
                  formatoMetricaCompacto(total),
                  style: GoogleFonts.baloo2(
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    height: 0.95,
                    letterSpacing: -1,
                    color: ColoresLocales.textoOnFondoClaro,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'impresiones',
                    style: GoogleFonts.baloo2(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ColoresLocales.textoSecundarioOnFondoClaro,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: [
                    if (_cartelera > 0)
                      Expanded(
                        flex: _cartelera,
                        child: ColoredBox(color: colorCartelera),
                      ),
                    if (perfil > 0)
                      Expanded(
                        flex: perfil,
                        child: ColoredBox(color: colorPerfil),
                      ),
                    if (clicks > 0)
                      Expanded(
                        flex: clicks,
                        child: ColoredBox(color: colorClicks),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _LeyendaResumenHoy(
                  color: colorCartelera,
                  label: 'Cartelera',
                  valor: _cartelera,
                ),
                _LeyendaResumenHoy(
                  color: colorPerfil,
                  label: 'Visitas perfil',
                  valor: perfil,
                ),
                _LeyendaResumenHoy(
                  color: colorClicks,
                  label: 'Clicks',
                  valor: clicks,
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Para ver la tendencia diaria, usá 7 o 30 días.',
            style: GoogleFonts.baloo2(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: ColoresLocales.textoSecundarioOnFondoClaro.withValues(
                alpha: 0.85,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LeyendaResumenHoy extends StatelessWidget {
  const _LeyendaResumenHoy({
    required this.color,
    required this.label,
    required this.valor,
  });

  final Color color;
  final String label;
  final int valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          '$label · ${formatoMetricaCompacto(valor)}',
          style: GoogleFonts.baloo2(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: ColoresLocales.textoSecundarioOnFondoClaro,
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.valor,
    required this.icon,
    required this.color,
  });

  final String label;
  final String valor;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: ColoresLocales.decoracionCard(sinBorde: true, radius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          SizedBox(height: 6),
          Text(
            valor,
            style: GoogleFonts.baloo2(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: ColoresLocales.textoOnFondoClaro,
              height: 1,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.baloo2(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ColoresLocales.textoSecundarioOnFondoClaro,
            ),
          ),
        ],
      ),
    );
  }
}

class _GraficoLineaMetricas extends StatelessWidget {
  const _GraficoLineaMetricas({
    required this.titulo,
    required this.subtitulo,
    required this.color,
    required this.puntos,
    required this.rangoDias,
  });

  final String titulo;
  final String subtitulo;
  final Color color;
  final List<PuntoRendimiento> puntos;
  final int rangoDias;

  double get _maxY {
    if (puntos.isEmpty) return 1;
    final maxVal = puntos.map((p) => p.valor).reduce(math.max);
    return math.max(maxVal * 1.2, 1).ceilToDouble();
  }

  bool _mostrarEtiquetaEje(int index) {
    final n = puntos.length;
    if (n <= 8) return true;
    if (rangoDias >= 60) return true;
    return index % 5 == 0 || index == n - 1;
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: ColoresLocales.decoracionCard(sinBorde: true, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: GoogleFonts.baloo2(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: ColoresLocales.textoOnFondoClaro,
            ),
          ),
          Text(
            subtitulo,
            style: GoogleFonts.baloo2(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ColoresLocales.textoSecundarioOnFondoClaro,
            ),
          ),
          SizedBox(height: 10),
          if (puntos.isEmpty)
            SizedBox(
              height: 160,
              child: Center(
                child: Text(
                  'Sin actividad en este rango',
                  style: GoogleFonts.baloo2(
                    fontSize: 12,
                    color: ColoresLocales.textoSecundarioOnFondoClaro,
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 190,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: math.max(puntos.length - 1, 0).toDouble(),
                  minY: 0,
                  maxY: _maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: ColoresLocales.acentoVioleta.withOpacity(0.1),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 34,
                        interval: _maxY <= 5 ? 1 : (_maxY / 4).ceilToDouble(),
                        getTitlesWidget: (value, meta) {
                          if (value == meta.max || value == meta.min) {
                            return const SizedBox.shrink();
                          }
                          if (value % 1 != 0) return SizedBox.shrink();
                          return Text(
                            _etiquetaEjeY(value.toDouble(), _maxY),
                            style: GoogleFonts.baloo2(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: ColoresLocales.textoSecundarioOnFondoClaro,
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: puntos.length <= 8 ? 1 : 5,
                        getTitlesWidget: (value, meta) {
                          final i = value.round();
                          if (i < 0 ||
                              i >= puntos.length ||
                              !_mostrarEtiquetaEje(i)) {
                            return SizedBox.shrink();
                          }
                          return Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text(
                              puntos[i].etiqueta,
                              style: GoogleFonts.baloo2(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color:
                                    ColoresLocales.textoSecundarioOnFondoClaro,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) =>
                          ColoresLocales.textoOnFondoClaro.withOpacity(0.92),
                      getTooltipItems: (spots) => spots.map((spot) {
                        final i = spot.x.toInt();
                        if (i < 0 || i >= puntos.length) return null;
                        return LineTooltipItem(
                          '${puntos[i].etiqueta}\n${formatoMetricaExacto(spot.y)} acciones',
                          GoogleFonts.baloo2(
                            fontWeight: FontWeight.w800,
                            color: ColoresLocales.chipInactivo,
                            fontSize: 11,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < puntos.length; i++)
                          FlSpot(i.toDouble(), puntos[i].valor),
                      ],
                      isCurved: true,
                      curveSmoothness: 0.28,
                      color: color,
                      barWidth: 3,
                      dotData: FlDotData(show: puntos.length <= 14),
                      belowBarData: BarAreaData(
                        show: true,
                        color: color.withOpacity(0.14),
                      ),
                    ),
                  ],
                ),
                duration: const Duration(milliseconds: 350),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScrollHorizontalDesdeReciente extends StatefulWidget {
  const _ScrollHorizontalDesdeReciente({
    required this.width,
    required this.height,
    required this.child,
  });

  final double width;
  final double height;
  final Widget child;

  @override
  State<_ScrollHorizontalDesdeReciente> createState() =>
      _ScrollHorizontalDesdeRecienteState();
}

class _ScrollHorizontalDesdeRecienteState
    extends State<_ScrollHorizontalDesdeReciente> {
  final _ctrl = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _irAlFinal());
  }

  @override
  void didUpdateWidget(covariant _ScrollHorizontalDesdeReciente oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.width != widget.width) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _irAlFinal());
    }
  }

  void _irAlFinal() {
    if (!_ctrl.hasClients) return;
    _ctrl.jumpTo(_ctrl.position.maxScrollExtent);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return SingleChildScrollView(
      controller: _ctrl,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      reverse: false,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: widget.child,
      ),
    );
  }
}

class _GraficoBarrasMetricas extends StatelessWidget {
  const _GraficoBarrasMetricas({
    required this.titulo,
    required this.subtitulo,
    required this.color,
    required this.puntos,
    required this.rangoDias,
    this.esRanking = false,
  });

  final String titulo;
  final String subtitulo;
  final Color color;
  final List<PuntoRendimiento> puntos;
  final int rangoDias;
  final bool esRanking;

  double get _maxY {
    if (puntos.isEmpty) return 1;
    final maxVal = puntos.map((p) => p.valor).reduce(math.max);
    return math.max(maxVal * 1.15, 1).ceilToDouble();
  }

  bool _mostrarEtiquetaEje(int index) {
    if (esRanking) return true;
    final n = puntos.length;
    if (n <= 8) return true;
    if (rangoDias >= 60) return true;
    // 30 días: una etiqueta cada ~5 puntos + la última
    return index % 5 == 0 || index == n - 1;
  }

  BarChartData _buildChartData(double barWidth) {
    return BarChartData(
      maxY: _maxY,
      minY: 0,
      groupsSpace: esRanking ? 18 : 6,
      alignment: BarChartAlignment.spaceBetween,
      barTouchData: BarTouchData(
        enabled: puntos.isNotEmpty,
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) =>
              ColoresLocales.textoOnFondoClaro.withOpacity(0.92),
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            final i = group.x.toInt();
            if (i < 0 || i >= puntos.length) return null;
            final p = puntos[i];
            return BarTooltipItem(
              '${p.etiqueta}\n${formatoMetricaExacto(p.valor)}',
              GoogleFonts.baloo2(
                fontWeight: FontWeight.w800,
                color: ColoresLocales.chipInactivo,
                fontSize: 11,
              ),
            );
          },
        ),
      ),
      titlesData: FlTitlesData(
        show: true,
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 34,
            interval: _maxY <= 5 ? 1 : (_maxY / 4).ceilToDouble(),
            getTitlesWidget: (value, meta) {
              if (value == meta.max || value == meta.min) {
                return const SizedBox.shrink();
              }
              if (value % 1 != 0) return SizedBox.shrink();
              return Text(
                _etiquetaEjeY(value, _maxY),
                style: GoogleFonts.baloo2(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: ColoresLocales.textoSecundarioOnFondoClaro,
                ),
              );
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: esRanking ? 42 : 30,
            getTitlesWidget: (value, meta) {
              final i = value.toInt();
              if (i < 0 || i >= puntos.length || !_mostrarEtiquetaEje(i)) {
                return SizedBox.shrink();
              }
              return Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  esRanking
                      ? _truncar(puntos[i].etiqueta, 10)
                      : puntos[i].etiqueta,
                  textAlign: TextAlign.center,
                  maxLines: esRanking ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.baloo2(
                    fontSize: esRanking ? 8.5 : 9,
                    fontWeight: FontWeight.w600,
                    color: ColoresLocales.textoSecundarioOnFondoClaro,
                  ),
                ),
              );
            },
          ),
        ),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => FlLine(
          color: ColoresLocales.acentoVioleta.withOpacity(0.1),
          strokeWidth: 1,
        ),
      ),
      borderData: FlBorderData(show: false),
      barGroups: [
        for (var i = 0; i < puntos.length; i++)
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: puntos[i].valor,
                fromY: 0,
                width: barWidth,
                color: color.withOpacity(0.9),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(5),
                ),
              ),
            ],
          ),
      ],
    );
  }

  String _truncar(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max - 1)}…';
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final scrollable = !esRanking && puntos.length > 10;
    final barWidth = esRanking ? 32.0 : (rangoDias <= 7 ? 20.0 : 14.0);
    final chartHeight = 210.0;
    final minChartWidth = MediaQuery.sizeOf(context).width - 64;
    final chartWidth = scrollable
        ? math.max(minChartWidth, puntos.length * 24.0)
        : minChartWidth;

    Widget chart = BarChart(
      _buildChartData(barWidth),
      duration: Duration(milliseconds: 350),
    );

    if (scrollable) {
      chart = _ScrollHorizontalDesdeReciente(
        width: chartWidth,
        height: chartHeight,
        child: chart,
      );
    } else {
      chart = SizedBox(height: chartHeight, child: chart);
    }

    return Container(
      padding: EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: ColoresLocales.decoracionCard(sinBorde: true, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: GoogleFonts.baloo2(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: ColoresLocales.textoOnFondoClaro,
            ),
          ),
          Text(
            subtitulo,
            style: GoogleFonts.baloo2(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ColoresLocales.textoSecundarioOnFondoClaro,
            ),
          ),
          if (scrollable) ...[
            SizedBox(height: 4),
            Text(
              'Mostrando lo más reciente · deslizá a la izquierda para ver antes',
              style: GoogleFonts.baloo2(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: ColoresLocales.textoSecundarioOnFondoClaro.withOpacity(
                  0.8,
                ),
              ),
            ),
          ],
          SizedBox(height: 10),
          if (puntos.isEmpty)
            SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  'Sin datos en este rango',
                  style: GoogleFonts.baloo2(
                    fontSize: 12,
                    color: ColoresLocales.textoSecundarioOnFondoClaro,
                  ),
                ),
              ),
            )
          else
            chart,
        ],
      ),
    );
  }
}
