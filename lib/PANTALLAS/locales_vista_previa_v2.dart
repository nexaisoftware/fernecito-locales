library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants.dart';
import '../core/lanzador_externo.dart';
import '../widgets/tema_locales_scope.dart';
import '../widgets/icono_local.dart';
import '../core/supabase_client.dart';

class LocalesVistaPreviaV2 extends StatefulWidget {
  final Map<String, dynamic> evento;

  const LocalesVistaPreviaV2({super.key, required this.evento});

  @override
  State<LocalesVistaPreviaV2> createState() => _LocalesVistaPreviaV2State();
}

class _LocalesVistaPreviaV2State extends State<LocalesVistaPreviaV2> {
  bool _cargando = true;
  String? _nombreLocal;
  String? _fotoLocal;
  bool _localVerificado = false;
  double? _calificacionPromedio;
  List<_PromoMini> _promos = const [];
  String? _error;

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String && v.trim().isNotEmpty) return DateTime.tryParse(v);
    return DateTime.tryParse(v.toString());
  }

  String _formatFecha(DateTime? d) {
    if (d == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  String _modoListaLabel(String? modoLista) {
    final m = (modoLista ?? '').toLowerCase();
    return switch (m) {
      'auto' => 'Auto',
      'manual' => 'Manual',
      _ => modoLista ?? '—',
    };
  }

  Future<List<_PromoMini>> _fetchPromos(String idEvento) async {
    final res = await ServicioSupabase().cliente
        .from('promociones')
        .select(
          'id_evento, titulo_promocion, descripcion_promocion, fecha_inicio, fecha_fin',
        )
        .eq('id_evento', idEvento);

    final list = (res as List).cast<Map<String, dynamic>>();
    return list.map((e) => _PromoMini.fromMap(e)).toList();
  }

  Future<void> _fetchLocal() async {
    final idLocal = widget.evento['id_local']?.toString();
    if (idLocal == null || idLocal.isEmpty) return;

    final row = await ServicioSupabase().cliente
        .from('perfiles_locales')
        .select(
          'nombre_local, foto_perfil_url, local_verificado, calificacion_promedio',
        )
        .eq('id', idLocal)
        .maybeSingle();

    final calificacionRaw = row?['calificacion_promedio'];
    final calificacion = switch (calificacionRaw) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };

    if (!mounted) return;
    setState(() {
      _nombreLocal = row?['nombre_local'] as String?;
      _fotoLocal = row?['foto_perfil_url'] as String?;
      _localVerificado = row?['local_verificado'] as bool? ?? false;
      _calificacionPromedio = calificacion;
    });
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final idEvento = widget.evento['id_evento']?.toString();
      if (idEvento != null && idEvento.isNotEmpty) {
        _promos = await _fetchPromos(idEvento);
      }
      await _fetchLocal();
    } catch (e) {
      _error = 'No se pudo cargar la vista previa: $e';
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _abrirBottomSheetPromos() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => _BottomSheetVerPromos(promos: _promos),
    );
  }

  Future<void> _abrirCompraEntradas(String rawUrl) async {
    final texto = rawUrl.trim();
    if (texto.isEmpty) return;
    final normalizado =
        texto.startsWith('http://') || texto.startsWith('https://')
        ? texto
        : 'https://$texto';
    final uri = Uri.tryParse(normalizado);
    if (uri == null) return;

    final ok = await lanzarExternoConFallback(uri);
    if (!ok && mounted) {
      showCupertinoDialog<void>(
        context: context,
        builder: (_) => CupertinoAlertDialog(
          title: Text('No se pudo abrir el link'),
          content: Text(
            'Revisá la URL de compra de entradas e intentá de nuevo.',
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _abrirBottomSheetReserva() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => Container(
        height: 420,
        decoration: BoxDecoration(
          color: ColoresLocales.fondoSuperficie,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(
            color: ColoresLocales.acentoVioleta.withOpacity(0.2),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.eye_fill,
                    size: 52,
                    color: ColoresLocales.acentoVioleta.withOpacity(0.9),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Vista previa',
                    style: GoogleFonts.baloo2(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: ColoresLocales.textoOnFondoClaro,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Desde el panel de locales solo podés ver el diseño. La reserva completa se realiza en la app de usuarios.',
                    style: GoogleFonts.baloo2(
                      fontSize: 13,
                      color: ColoresLocales.textoSecundarioOnFondoClaro,
                      height: 1.35,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 18),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: ColoresLocales.acentoVioleta,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Center(
                        child: Text(
                          'Entendido',
                          style: GoogleFonts.baloo2(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: ColoresLocales.superficie,
                          ),
                        ),
                      ),
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

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    final maxFlyerHeight = screenHeight * 0.70;

    final urlFlyer = (widget.evento['url_flyer'] as String?) ?? '';

    final titulo = (widget.evento['titulo_evento'] as String?) ?? 'Evento';
    final descripcion =
        (widget.evento['descripcion_evento'] as String?) ??
        'Vení con amigos y disfrutá.';
    final tipoEvento = (widget.evento['tipo_evento'] as String?) ?? 'evento';
    final modoLista = widget.evento['modo_lista']?.toString();
    final urlCompra = (widget.evento['url_compra_entradas'] as String?) ?? '';

    final fechaInicio = _parseDate(widget.evento['fecha_inicio']);
    final fechaHora = _formatFecha(fechaInicio);

    final appBar = AppBar(
      toolbarHeight: 46,
      backgroundColor: ColoresLocales.fondoPrincipal,
      surfaceTintColor: ColoresLocales.fondoPrincipal,
      elevation: 0,
      centerTitle: true,
      leading: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () => Navigator.of(context).pop(),
        child: Icon(
          CupertinoIcons.chevron_back,
          color: ColoresLocales.acentoVioleta,
          size: 20,
        ),
      ),
      title: Text(
        'Vista previa',
        style: GoogleFonts.baloo2(
          fontWeight: FontWeight.w900,
          fontSize: 18,
          color: ColoresLocales.acentoVioleta,
        ),
      ),
    );

    if (_cargando) {
      return Scaffold(
        appBar: appBar,
        backgroundColor: ColoresLocales.fondoPrincipal,
        body: Center(
          child: CircularProgressIndicator(color: ColoresLocales.acentoVioleta),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: appBar,
        backgroundColor: ColoresLocales.fondoPrincipal,
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.baloo2(
                color: ColoresLocales.textoSecundarioOnFondoClaro,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      backgroundColor: ColoresLocales.fondoPrincipal,
      body: DefaultTextStyle.merge(
        style: TextStyle(
          decoration: TextDecoration.none,
          decorationColor: Colors.transparent,
        ),
        child: Stack(
          children: [
            CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: EdgeInsets.only(top: 8, left: 20, right: 20),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: maxFlyerHeight),
                        child: Center(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: ColoresLocales.acentoVioleta
                                      .withOpacity(0.35),
                                  blurRadius: 28,
                                  spreadRadius: 0,
                                ),
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.4),
                                  blurRadius: 20,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: AspectRatio(
                                aspectRatio: 9 / 16,
                                child: urlFlyer.isEmpty
                                    ? Container(
                                        color: ColoresLocales.fondoSuperficie,
                                        child: Icon(
                                          CupertinoIcons.photo,
                                          size: 64,
                                          color: ColoresLocales
                                              .textoSecundarioOnFondoClaro,
                                        ),
                                      )
                                    : Image.network(
                                        urlFlyer,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: ColoresLocales.fondoSuperficie,
                                          child: Icon(
                                            CupertinoIcons.photo,
                                            size: 64,
                                            color: ColoresLocales
                                                .textoSecundarioOnFondoClaro,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _TarjetaInfoEventoLocales(
                        titulo: titulo,
                        descripcion: descripcion,
                        fechaHora: fechaHora,
                        tipoEvento: tipoEvento,
                        modoLista: _modoListaLabel(modoLista),
                        urlCompra: urlCompra,
                      ),
                      const SizedBox(height: 16),
                      _TarjetaReservaYPromosLocales(
                        cuposRestantes: 12,
                        urlCompra: urlCompra,
                        onReservaLista: _abrirBottomSheetReserva,
                        onVerPromos: _abrirBottomSheetPromos,
                        onObtenerEntrada: () => _abrirCompraEntradas(urlCompra),
                      ),
                      const SizedBox(height: 16),
                      _TarjetaLocalLocales(
                        nombre: _nombreLocal?.trim().isNotEmpty == true
                            ? _nombreLocal!.trim()
                            : ((widget.evento['nombre_local'] as String?)
                                          ?.trim()
                                          .isNotEmpty ==
                                      true
                                  ? (widget.evento['nombre_local'] as String)
                                        .trim()
                                  : 'Local'),
                        avatarUrl: _fotoLocal,
                        verificado: _localVerificado,
                        calificacionPromedio: _calificacionPromedio,
                      ),
                      const SizedBox(height: 28),
                    ]),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaInfoEventoLocales extends StatelessWidget {
  final String titulo;
  final String descripcion;
  final String fechaHora;
  final String tipoEvento;
  final String modoLista;
  final String urlCompra;

  const _TarjetaInfoEventoLocales({
    required this.titulo,
    required this.descripcion,
    required this.fechaHora,
    required this.tipoEvento,
    required this.modoLista,
    required this.urlCompra,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ColoresLocales.fondoSuperficie.withOpacity(0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ColoresLocales.acentoVioleta.withOpacity(0.25),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: GoogleFonts.baloo2(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: ColoresLocales.textoPrincipal,
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 6),
          Text(
            descripcion,
            style: GoogleFonts.baloo2(
              fontSize: 13,
              height: 1.35,
              color: ColoresLocales.textoSecundarioOnFondoClaro,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Icon(
                CupertinoIcons.calendar,
                size: 12,
                color: ColoresLocales.textoSecundarioOnFondoClaro,
              ),
              SizedBox(width: 4),
              Text(
                fechaHora,
                style: GoogleFonts.baloo2(
                  fontSize: 12,
                  color: ColoresLocales.textoSecundarioOnFondoClaro,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _ChipInfo(
                icon: CupertinoIcons.tag_fill,
                texto: 'Tipo: $tipoEvento',
              ),
              _ChipInfo(icon: CupertinoIcons.list_bullet, texto: modoLista),
              if (urlCompra.trim().isNotEmpty)
                _ChipInfo(
                  icon: CupertinoIcons.ticket_fill,
                  texto: 'Venta externa',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TarjetaReservaYPromosLocales extends StatelessWidget {
  final int cuposRestantes;
  final String urlCompra;
  final VoidCallback onReservaLista;
  final VoidCallback onVerPromos;
  final VoidCallback onObtenerEntrada;

  const _TarjetaReservaYPromosLocales({
    required this.cuposRestantes,
    required this.urlCompra,
    required this.onReservaLista,
    required this.onVerPromos,
    required this.onObtenerEntrada,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ColoresLocales.fondoSuperficie.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ColoresLocales.acentoVioleta.withOpacity(0.22),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.flame_fill,
                    size: 10,
                    color: ColoresLocales.textoEnBoton,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Solo quedan $cuposRestantes',
                    style: GoogleFonts.baloo2(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: ColoresLocales.chipInactivo,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onReservaLista,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: ColoresLocales.acentoVioleta,
                borderRadius: BorderRadius.circular(50),
                boxShadow: [
                  BoxShadow(
                    color: ColoresLocales.acentoVioleta.withOpacity(0.5),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.checkmark_circle_fill,
                    size: 20,
                    color: ColoresLocales.textoEnBoton,
                  ),
                  SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Reserva lista ahora!',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: ColoresLocales.chipInactivo,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 12),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onVerPromos,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFF8C42),
                borderRadius: BorderRadius.circular(50),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF8C42).withOpacity(0.5),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.tag_fill,
                    size: 18,
                    color: ColoresLocales.textoEnBoton,
                  ),
                  SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Ver promos!',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: ColoresLocales.chipInactivo,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (urlCompra.trim().isNotEmpty) ...[
            SizedBox(height: 12),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: onObtenerEntrada,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1FAF5C),
                  borderRadius: BorderRadius.circular(50),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1FAF5C).withOpacity(0.45),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.ticket_fill,
                      size: 18,
                      color: ColoresLocales.textoEnBoton,
                    ),
                    SizedBox(width: 8),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Obtener entrada',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: ColoresLocales.textoEnBoton,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TarjetaLocalLocales extends StatelessWidget {
  final String nombre;
  final String? avatarUrl;
  final bool verificado;
  final double? calificacionPromedio;

  const _TarjetaLocalLocales({
    required this.nombre,
    required this.avatarUrl,
    required this.verificado,
    required this.calificacionPromedio,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return GestureDetector(
      onTap: () {
        // En el panel locales, no hay navegación exacta a "perfil público" del usuario.
      },
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: ColoresLocales.fondoSuperficie.withOpacity(0.75),
          border: Border.all(
            color: ColoresLocales.acentoVioleta.withOpacity(0.22),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: ColoresLocales.acentoVioleta.withOpacity(0.6),
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: avatarUrl?.isNotEmpty == true
                    ? Image.network(
                        avatarUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: IconoLocal(
                            size: 18,
                            color: ColoresLocales.textoSecundario,
                          ),
                        ),
                      )
                    : Center(
                        child: IconoLocal(
                          size: 18,
                          color: ColoresLocales.textoSecundario,
                        ),
                      ),
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nombre,
                    style: GoogleFonts.baloo2(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: ColoresLocales.textoPrincipal,
                    ),
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        CupertinoIcons.star_fill,
                        color: Color(0xFFFFC107),
                        size: 16,
                      ),
                      SizedBox(width: 4),
                      Text(
                        calificacionPromedio != null
                            ? calificacionPromedio!.toStringAsFixed(1)
                            : '—',
                        style: GoogleFonts.baloo2(
                          fontSize: 13,
                          color: ColoresLocales.textoSecundarioOnFondoClaro,
                        ),
                      ),
                    ],
                  ),
                  if (verificado) ...[
                    SizedBox(height: 8),
                    _ChipInfo(
                      icon: CupertinoIcons.checkmark_seal_fill,
                      texto: 'Verificado',
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

class _BottomSheetVerPromos extends StatelessWidget {
  final List<_PromoMini> promos;

  const _BottomSheetVerPromos({required this.promos});

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return Container(
      height: 420,
      decoration: BoxDecoration(
        color: ColoresLocales.fondoSuperficie,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(
          color: ColoresLocales.acentoVioleta.withOpacity(0.2),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Text(
                'Promos del evento',
                style: GoogleFonts.baloo2(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: ColoresLocales.textoPrincipal,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
                itemCount: promos.length,
                itemBuilder: (context, index) {
                  final p = promos[index];
                  return Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: ColoresLocales.fondoPrincipal.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: ColoresLocales.acentoVioleta.withOpacity(0.18),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.titulo,
                            style: GoogleFonts.baloo2(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: ColoresLocales.textoPrincipal,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                CupertinoIcons.calendar,
                                size: 14,
                                color: ColoresLocales.textoSecundario,
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${p.fechaInicio != null ? DateTime.fromMillisecondsSinceEpoch(p.fechaInicio!.millisecondsSinceEpoch).toLocal() : ''} - ${p.fechaFin != null ? DateTime.fromMillisecondsSinceEpoch(p.fechaFin!.millisecondsSinceEpoch).toLocal() : ''}',
                                  style: GoogleFonts.baloo2(
                                    fontSize: 12,
                                    color: ColoresLocales.textoSecundario,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          if (p.descripcion.trim().isNotEmpty)
                            Text(
                              p.descripcion,
                              style: GoogleFonts.baloo2(
                                fontSize: 13,
                                color: ColoresLocales.textoSecundario,
                                height: 1.3,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          SizedBox(height: 12),
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              // TODO: Conectar lógica real de QR promo.
                            },
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 14,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF8C42),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    CupertinoIcons.qrcode,
                                    size: 18,
                                    color: ColoresLocales.textoEnBoton,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Obtener mi promo QR!',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: ColoresLocales.textoEnBoton,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipInfo extends StatelessWidget {
  final IconData icon;
  final String texto;

  const _ChipInfo({required this.icon, required this.texto});

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ColoresLocales.fondoSuperficie.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ColoresLocales.acentoVioleta.withOpacity(0.25),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: ColoresLocales.acentoVioleta),
          SizedBox(width: 6),
          Text(
            texto,
            style: GoogleFonts.baloo2(
              fontSize: 12,
              color: ColoresLocales.textoPrincipal,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }
}

class _PromoMini {
  final String idEvento;
  final String titulo;
  final String descripcion;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;

  const _PromoMini({
    required this.idEvento,
    required this.titulo,
    required this.descripcion,
    required this.fechaInicio,
    required this.fechaFin,
  });

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String && v.trim().isNotEmpty) return DateTime.tryParse(v);
    return DateTime.tryParse(v.toString());
  }

  factory _PromoMini.fromMap(Map<String, dynamic> m) {
    return _PromoMini(
      idEvento: m['id_evento'].toString(),
      titulo: (m['titulo_promocion'] as String?) ?? '',
      descripcion: (m['descripcion_promocion'] as String?) ?? '',
      fechaInicio: _parseDate(m['fecha_inicio']),
      fechaFin: _parseDate(m['fecha_fin']),
    );
  }
}
