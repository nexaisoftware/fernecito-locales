part of 'locales_flyer_ia.dart';

// ─── Pantalla: lista de generaciones + detalle (grid 4) ──────────────────────

class LocalesFlyerIaResultados extends StatefulWidget {
  const LocalesFlyerIaResultados({super.key});

  @override
  State<LocalesFlyerIaResultados> createState() =>
      _LocalesFlyerIaResultadosState();
}

class _LocalesFlyerIaResultadosState extends State<LocalesFlyerIaResultados> {
  String? _detalleId;
  Timer? _reloj;
  bool _cargandoHistorial = false;

  @override
  void initState() {
    super.initState();
    // Escuchar cambios del historial en tiempo real (retry, nuevas generaciones)
    LocalesFlyerIaHistorial.instance.addListener(_onHistorialCambio);
    // Actualizar timer de retry cada 30 segundos
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    // Sincronizar historial con caché local + Supabase
    _sincronizarHistorial();
  }

  void _onHistorialCambio() {
    // Reconstruir la pantalla cuando el historial cambia (retry, nueva gen)
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    LocalesFlyerIaHistorial.instance.removeListener(_onHistorialCambio);
    _reloj?.cancel();
    super.dispose();
  }

  // ── Sincronización historial completo ────────────────────────────────────
  // 1. Cargar desde caché local (instantáneo, sin red)
  // 2. Completar con historial de Supabase (lo que no está en caché)

  Future<void> _sincronizarHistorial() async {
    if (_cargandoHistorial) return;
    if (mounted) setState(() => _cargandoHistorial = true);

    try {
      final cache = FlyerCacheService();
      final servicio = FlyerIaService();
      final h = LocalesFlyerIaHistorial.instance;

      // Paso 1: cargar generaciones cacheadas localmente.
      // Las entradas de retry se identifican por ID con sufijo "_retry" y se
      // asignan a la card padre en lugar de crear una card nueva.
      final cacheadas = await cache.cargarTodas();

      // Primero pasada: solo padres (IDs sin sufijo "_retry")
      for (final c in cacheadas) {
        if (c.id.endsWith('_retry')) continue; // se procesa en segunda pasada
        if (h.buscarPorId(c.id) != null) continue;
        LocalesFlyerFormSnapshot? snap;
        if (c.formulario != null) {
          snap = LocalesFlyerFormSnapshot.desdeCacheFormulario(c.formulario!);
        }
        h.agregar(LocalesFlyerGeneracion(
          id: c.id,
          titulo: c.titulo,
          urlsLocales: c.localPaths,
          urlsRemotas: [],
          creadoEn: c.createdAt,
          esRetry: false,
          reintentoGratisConsumido: c.retryUsado,
          formularioAlGenerar: snap,
        ));
      }

      // Segunda pasada: entradas de retry → poblar urlsLocalesRetry del padre
      for (final c in cacheadas) {
        if (!c.id.endsWith('_retry')) continue;
        final padreId = c.id.replaceFirst(RegExp(r'_retry$'), '');
        final padre = h.buscarPorId(padreId);
        if (padre == null) continue; // padre no encontrado, ignorar
        // Solo poblar si aún no tiene imágenes de retry (evitar duplicar)
        if (padre.urlsLocalesRetry.isEmpty) {
          padre.urlsLocalesRetry = List<String>.from(c.localPaths);
          padre.reintentoGratisConsumido = true;
        }
      }

      // Paso 2: traer historial de Supabase y agregar lo que no tengamos.
      // Solo generaciones padre (es_retry = false) para no duplicar cards.
      // Los retries remotos se usan solo para marcar reintentoGratisConsumido.
      final remotas = await servicio.obtenerHistorial();
      for (final r in remotas) {
        if (r.esRetry) {
          // Buscar el padre por generacion_padre_id no disponible aquí,
          // pero el retryUsado ya está en el padre remoto → se maneja abajo.
          continue;
        }
        final existente = h.buscarPorId(r.id);
        if (existente == null) {
          h.agregar(LocalesFlyerGeneracion(
            id: r.id,
            titulo: r.titulo,
            urlsLocales: [],
            urlsRemotas: r.urls,
            creadoEn: r.createdAt,
            esRetry: false,
            reintentoGratisConsumido: r.retryUsado,
          ));
        } else {
          // Completar datos faltantes del padre existente
          if (existente.urlsLocales.isEmpty && r.urls.isNotEmpty) {
            existente.urlsRemotas = r.urls;
          }
          // Sincronizar estado de retry desde Supabase (fuente de verdad)
          if (r.retryUsado && !existente.reintentoGratisConsumido) {
            existente.reintentoGratisConsumido = true;
          }
        }
      }
    } catch (e) {
      debugPrint('_sincronizarHistorial error: $e');
    } finally {
      if (mounted) setState(() => _cargandoHistorial = false);
    }
  }

  // ── Retry ────────────────────────────────────────────────────────────────

  void _crearEventoConPieza(LocalesFlyerGeneracion reg, FlyerPieza pieza) {
    HapticFeedback.lightImpact();
    final snap = reg.formularioAlGenerar;
    DateTime? inicio;
    DateTime? fin;
    if (snap != null) {
      inicio = CrearEventoDesdeFlyerArgs.fechaDesdePartes(
        mesIdx: snap.mesIdx,
        diaMes: snap.diaMes,
        hora: snap.hora,
        minuto: snap.minuto,
      );
      fin = CrearEventoDesdeFlyerArgs.fechaFinDesdeInicio(inicio);
    }
    final promo = snap?.promos?.trim();
    final args = CrearEventoDesdeFlyerArgs(
      tituloEvento: reg.titulo,
      rutaFlyerLocal: pieza.localPath.isNotEmpty ? pieza.localPath : null,
      urlFlyerRemota: pieza.remoteUrl.isNotEmpty ? pieza.remoteUrl : null,
      nombrePromo: promo != null && promo.isNotEmpty ? promo : null,
      fechaInicio: inicio,
      fechaFin: fin,
      activarPromos: promo != null && promo.isNotEmpty,
    );
    Navigator.of(context).pushNamed('/crear_evento', arguments: args);
  }

  void _abrirReintento(LocalesFlyerGeneracion reg) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LocalesFlyerIa(
          retry: LocalesFlyerIaRetryArgs(
            registroId: reg.id,
            titulo: reg.titulo,
            formulario: reg.formularioAlGenerar,
          ),
        ),
      ),
    );
  }

  // ── Descarga / compartir una pieza (local → remota → error) ──────────────

  Future<void> _descargarPieza(FlyerPieza pieza, String tituloFlyer) async {
    HapticFeedback.lightImpact();
    String? localPath;

    // 1. Intentar archivo local en caché
    if (pieza.localPath.isNotEmpty) {
      if (await File(pieza.localPath).exists()) {
        localPath = pieza.localPath;
      }
    }

    // 2. Si no hay caché, descargar temporalmente
    if (localPath == null) {
      if (pieza.remoteUrl.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Imagen no disponible', style: GoogleFonts.baloo2(color: ColoresLocales.textoPrincipal)),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ));
        }
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: ColoresLocales.textoEnBoton)),
            SizedBox(width: 12),
            Text('Descargando...', style: GoogleFonts.baloo2(color: ColoresLocales.textoPrincipal)),
          ]),
          duration: Duration(seconds: 15),
          backgroundColor: ColoresLocales.acentoVioleta,
          behavior: SnackBarBehavior.floating,
        ));
      }
      try {
        final resp = await http.get(Uri.parse(pieza.remoteUrl)).timeout(Duration(seconds: 30));
        if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
        final dir = await getTemporaryDirectory();
        final slug = pieza.label.toLowerCase().replaceAll(' ', '_');
        final tmp = File('${dir.path}/flyer_tmp_$slug.jpg');
        await tmp.writeAsBytes(resp.bodyBytes);
        localPath = tmp.path;
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error al descargar la imagen', style: GoogleFonts.baloo2(color: ColoresLocales.textoPrincipal)),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ));
        }
        return;
      }
    }

    if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
    try {
      await Share.shareXFiles(
        [XFile(localPath, mimeType: 'image/jpeg')],
        text: '$tituloFlyer — ${pieza.label} · Generado con Fernecito ✨',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo compartir la imagen', style: GoogleFonts.baloo2(color: ColoresLocales.textoPrincipal)),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // Wrapper para compatibilidad con galería fullscreen (recibe índice global)
  Future<void> _descargarPorIndice(LocalesFlyerGeneracion reg, int index) async {
    final piezas = reg.todasLasPiezas;
    if (index < piezas.length) {
      await _descargarPieza(piezas[index], reg.titulo);
    }
  }

  // ── AppBars ──────────────────────────────────────────────────────────────

  PreferredSizeWidget _appBarLista() => AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: ColoresLocales.superficie,
        centerTitle: true,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: Icon(CupertinoIcons.chevron_back, color: ColoresLocales.acentoVioleta),
        ),
        title: Text(
          'Tus flyers generados',
          style:
              GoogleFonts.baloo2(color: ColoresLocales.acentoVioleta, fontWeight: FontWeight.w900),
        ),
      );

  PreferredSizeWidget _appBarDetalle(LocalesFlyerGeneracion reg) => AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: ColoresLocales.superficie,
        centerTitle: true,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => setState(() => _detalleId = null),
          child: Icon(CupertinoIcons.chevron_back, color: ColoresLocales.acentoVioleta),
        ),
        title: Text(
          reg.titulo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              GoogleFonts.baloo2(color: ColoresLocales.acentoVioleta, fontWeight: FontWeight.w900),
        ),
      );

  // ── Tarjeta de lista ─────────────────────────────────────────────────────

  Widget _tarjetaLista(LocalesFlyerGeneracion reg) {
    final activo = reg.puedeReintentar;
    final minLeft = reg.minutosRestantesReintento;
    final piezas = reg.todasLasPiezas;
    final nPiezas = piezas.length;
    final varianteTxt = nPiezas == 1 ? '1 variante' : '$nPiezas variantes';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _detalleId = reg.id),
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: ColoresLocales.decoracionCard(radius: 22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FlyerListaIconoPreview(
                      pieza: piezas.isNotEmpty ? piezas.first : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reg.titulo,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.baloo2(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: ColoresLocales.acentoVioleta,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$varianteTxt · ${_etiquetaEstiloFlyer(reg)} · ${_fechaRelativaFlyer(reg.creadoEn)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.baloo2(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: ColoresLocales.textoSecundarioOnFondoClaro,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _FlyerEstadoChip(
                            activo: activo,
                            minLeft: minLeft,
                            reintentoUsado: reg.reintentoGratisConsumido,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4),
                      child: Icon(
                        CupertinoIcons.chevron_right,
                        size: 18,
                        color: ColoresLocales.acentoVioleta.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
                if (nPiezas > 0) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Divider(
                      height: 1,
                      thickness: 1,
                      color: ColoresLocales.separador,
                    ),
                  ),
                  _MiniaturasRow(reg: reg, onTap: (i) => _abrirFullscreen(reg, i)),
                ],
                if (activo) ...[
                  const SizedBox(height: 12),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _abrirReintento(reg),
                      borderRadius: BorderRadius.circular(14),
                      child: Ink(
                        decoration: BoxDecoration(
                          color: ColoresFeaturesLocales.flyersIa.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: ColoresFeaturesLocales.flyersIa.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.refresh,
                                size: 16,
                                color: ColoresFeaturesLocales.flyersIa,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Reintentar gratis · ${minLeft}m restantes',
                                style: GoogleFonts.baloo2(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: ColoresFeaturesLocales.flyersIa,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Lista ────────────────────────────────────────────────────────────────

  Widget _cuerpoLista() {
    final items = LocalesFlyerIaHistorial.instance.itemsMasRecientesPrimero;

    if (items.isEmpty && _cargandoHistorial) {
      return Center(
        child: CircularProgressIndicator(color: ColoresLocales.acentoVioleta),
      );
    }

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: ColoresLocales.decoracionCard(radius: 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: ColoresLocales.cardLavanda,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    CupertinoIcons.photo_on_rectangle,
                    size: 28,
                    color: ColoresLocales.acentoVioleta.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Todavía no tenés flyers',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.baloo2(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: ColoresLocales.acentoVioleta,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Generá el primero desde el formulario de Flyer IA.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.baloo2(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ColoresLocales.textoSecundarioOnFondoClaro,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: ColoresLocales.acentoVioleta,
      onRefresh: _sincronizarHistorial,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _tarjetaLista(items[i]),
      ),
    );
  }

  // ── Fullscreen ────────────────────────────────────────────────────────────

  void _abrirFullscreen(LocalesFlyerGeneracion reg, int initialIndex) {
    Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        fullscreenDialog: true,
        opaque: false,
        barrierColor: Colors.black.withOpacity(0.92),
        pageBuilder: (context, animation, secondaryAnimation) => _FlyerGallery(
          reg: reg,
          initialIndex: initialIndex,
          onDescarga: (i) => _descargarPorIndice(reg, i),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  // ── Detalle (grid 2×2) ────────────────────────────────────────────────────

  Widget _cuerpoDetalle(LocalesFlyerGeneracion reg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Variantes generadas',
                style: GoogleFonts.baloo2(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: ColoresLocales.acentoVioleta,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${reg.todasLasPiezas.length} imágenes · ${_etiquetaEstiloFlyer(reg)}',
                style: GoogleFonts.baloo2(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: ColoresLocales.textoSecundarioOnFondoClaro,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Builder(builder: (context) {
              final piezas = reg.todasLasPiezas;
              return GridView.builder(
                physics: const BouncingScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.48,
                ),
                itemCount: piezas.length,
                itemBuilder: (context, index) {
                  final pieza = piezas[index];
                  return _GridFlyerTile(
                    localPath: pieza.localPath,
                    remoteUrl: pieza.remoteUrl,
                    label: pieza.label,
                    index: index,
                    onTap: () => _abrirFullscreen(reg, index),
                    onDescarga: () => _descargarPieza(pieza, reg.titulo),
                    onCrearEvento: () => _crearEventoConPieza(reg, pieza),
                  );
                },
              );
            }),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 8, 18, 14),
            child: Column(
              children: [
                Text(
                  '¿No es lo que esperabas?',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.baloo2(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ColoresLocales.textoSecundarioOnFondoClaro,
                  ),
                ),
                SizedBox(height: 7),
                if (reg.puedeReintentar)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () => _abrirReintento(reg),
                      icon: const Icon(CupertinoIcons.refresh, size: 17),
                      label: Text(
                        'Reintentar gratis · ${reg.minutosRestantesReintento}m',
                        style: GoogleFonts.baloo2(fontSize: 14, fontWeight: FontWeight.w900),
                      ),
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: ColoresFeaturesLocales.flyersIa,
                        foregroundColor: ColoresLocales.textoEnBoton,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                    decoration: BoxDecoration(
                      color: ColoresLocales.superficie,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: ColoresLocales.bordeSuave),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          reg.reintentoGratisConsumido
                              ? CupertinoIcons.checkmark_circle_fill
                              : CupertinoIcons.clock,
                          size: 16,
                          color: ColoresLocales.textoSecundarioOnFondoClaro,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          reg.reintentoGratisConsumido
                              ? 'Reintento ya utilizado'
                              : 'Ventana de reintento cerrada',
                          style: GoogleFonts.baloo2(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: ColoresLocales.textoSecundarioOnFondoClaro,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return ListenableBuilder(
      listenable: LocalesFlyerIaHistorial.instance,
      builder: (context, _) {
        final h = LocalesFlyerIaHistorial.instance;
        LocalesFlyerGeneracion? reg;
        if (_detalleId != null) {
          reg = h.buscarPorId(_detalleId!);
          if (reg == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _detalleId = null);
            });
          }
        }

        final enDetalle = reg != null;

        return Scaffold(
          backgroundColor: ColoresLocales.fondoFormulario,
          appBar: enDetalle ? _appBarDetalle(reg) : _appBarLista(),
          body: enDetalle ? _cuerpoDetalle(reg) : _cuerpoLista(),
        );
      },
    );
  }
}

// ─── Helpers de presentación ─────────────────────────────────────────────────

String _fechaRelativaFlyer(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'Hace un momento';
  if (diff.inHours < 1) return 'Hace ${diff.inMinutes} min';
  if (diff.inDays < 1) return 'Hace ${diff.inHours} h';
  if (diff.inDays < 7) return 'Hace ${diff.inDays} d';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String _etiquetaEstiloFlyer(LocalesFlyerGeneracion reg) {
  final snap = reg.formularioAlGenerar;
  if (snap?.esLibre == true) return 'Descripción libre';
  final id = snap?.estiloId ?? '';
  if (id.isEmpty || id == 'prompt_libre') {
    return id == 'prompt_libre' ? 'Descripción libre' : 'Flyer IA';
  }
  for (final e in _estilos) {
    if (e.id == id) return e.nombre;
  }
  return id.replaceAll('_', ' ');
}

class _FlyerListaIconoPreview extends StatelessWidget {
  const _FlyerListaIconoPreview({this.pieza});
  final FlyerPieza? pieza;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 68,
      decoration: BoxDecoration(
        color: ColoresLocales.cardLavanda,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ColoresLocales.bordeSuave),
      ),
      clipBehavior: Clip.antiAlias,
      child: pieza != null
          ? _ImagenFlyer(
              localPath: pieza!.localPath,
              remoteUrl: pieza!.remoteUrl,
              fit: BoxFit.cover,
            )
          : Icon(
              CupertinoIcons.sparkles,
              size: 24,
              color: ColoresLocales.acentoVioleta.withValues(alpha: 0.4),
            ),
    );
  }
}

class _FlyerEstadoChip extends StatelessWidget {
  const _FlyerEstadoChip({
    required this.activo,
    required this.minLeft,
    required this.reintentoUsado,
  });

  final bool activo;
  final int minLeft;
  final bool reintentoUsado;

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    late final Color border;
    late final String texto;
    late final IconData icono;

    if (activo) {
      bg = ColoresFeaturesLocales.flyersIa.withValues(alpha: 0.1);
      fg = ColoresFeaturesLocales.flyersIa;
      border = ColoresFeaturesLocales.flyersIa.withValues(alpha: 0.25);
      texto = 'Reintento disponible · ${minLeft}m';
      icono = CupertinoIcons.refresh;
    } else if (reintentoUsado) {
      bg = ColoresLocales.cardLavanda;
      fg = ColoresLocales.acentoVioleta.withValues(alpha: 0.75);
      border = ColoresLocales.acentoVioleta.withValues(alpha: 0.18);
      texto = 'Reintento usado';
      icono = CupertinoIcons.checkmark_circle_fill;
    } else {
      bg = ColoresLocales.superficieElevada;
      fg = ColoresLocales.textoSecundarioOnFondoClaro;
      border = ColoresLocales.bordeSuave;
      texto = 'Reintento no disponible';
      icono = CupertinoIcons.clock;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 12, color: fg),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              texto,
              style: GoogleFonts.baloo2(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Miniaturas en scroll horizontal (lista) ─────────────────────────────────

class _MiniaturasRow extends StatelessWidget {
  const _MiniaturasRow({required this.reg, required this.onTap});
  final LocalesFlyerGeneracion reg;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final piezas = reg.todasLasPiezas;
    if (piezas.isEmpty) return const SizedBox.shrink();

    final tieneRetry = piezas.any((p) => p.label.startsWith('Reintento'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tocá una miniatura para ampliar',
          style: GoogleFonts.baloo2(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: ColoresLocales.textoSecundarioOnFondoClaro,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: piezas.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final pieza = piezas[i];
              final esRetry = pieza.label.startsWith('Reintento');
              return GestureDetector(
                onTap: () => onTap(i),
                child: SizedBox(
                  width: 58,
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: esRetry
                                  ? ColoresFeaturesLocales.flyersIa.withValues(alpha: 0.35)
                                  : ColoresLocales.bordeSuave,
                              width: esRetry ? 1.4 : 1,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _ImagenFlyer(
                            localPath: pieza.localPath,
                            remoteUrl: pieza.remoteUrl,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _abreviarLabelPieza(pieza.label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.baloo2(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: esRetry
                              ? ColoresFeaturesLocales.flyersIa
                              : ColoresLocales.textoSecundarioOnFondoClaro,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (tieneRetry) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                CupertinoIcons.arrow_2_squarepath,
                size: 12,
                color: ColoresFeaturesLocales.flyersIa.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 4),
              Text(
                'Incluye variantes del reintento',
                style: GoogleFonts.baloo2(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: ColoresFeaturesLocales.flyersIa.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

String _abreviarLabelPieza(String label) {
  if (label.startsWith('Reintento')) {
    final suf = label.replaceFirst('Reintento', '').trim();
    return suf.isEmpty ? 'Reint.' : 'R$suf';
  }
  if (label.startsWith('Original')) {
    final suf = label.replaceFirst('Original', '').trim();
    return suf.isEmpty ? 'Orig.' : 'O$suf';
  }
  return label.length > 8 ? '${label.substring(0, 8)}…' : label;
}

// ─── Widget imagen con prioridad: local → remoto → placeholder ────────────────

class _ImagenFlyer extends StatelessWidget {
  const _ImagenFlyer({
    required this.localPath,
    required this.remoteUrl,
    this.fit = BoxFit.cover,
  });

  final String localPath;
  final String remoteUrl;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    if (localPath.isNotEmpty) {
      final file = File(localPath);
      return FutureBuilder<bool>(
        future: file.exists(),
        builder: (context, snap) {
          if (snap.data == true) {
            return Image.file(file,
                fit: fit,
                errorBuilder: (_, __, ___) => _remotoOPlaceholder());
          }
          return _remotoOPlaceholder();
        },
      );
    }
    return _remotoOPlaceholder();
  }

  Widget _remotoOPlaceholder() {
    if (remoteUrl.isNotEmpty) {
      return Image.network(
        remoteUrl,
        fit: fit,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            color: ColoresLocales.cardLavanda,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: ColoresLocales.acentoVioleta),
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
        color: ColoresLocales.cardLavanda,
        child:
            Icon(CupertinoIcons.photo, color: ColoresLocales.acentoVioleta.withOpacity(0.35)),
      );
}

// ─── Tile del grid de resultados ─────────────────────────────────────────────

class _GridFlyerTile extends StatelessWidget {
  const _GridFlyerTile({
    required this.localPath,
    required this.remoteUrl,
    required this.label,
    required this.index,
    required this.onTap,
    required this.onDescarga,
    required this.onCrearEvento,
  });
  final String localPath;
  final String remoteUrl;
  final String label;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onDescarga;
  final VoidCallback onCrearEvento;

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final esRetry = label.startsWith('Reintento');
    return Container(
      decoration: ColoresLocales.decoracionCard(radius: 18),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ImagenFlyer(
                    localPath: localPath,
                    remoteUrl: remoteUrl,
                    fit: BoxFit.cover,
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: esRetry
                            ? ColoresFeaturesLocales.flyersIa.withValues(alpha: 0.92)
                            : ColoresLocales.superficie.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: esRetry
                              ? ColoresFeaturesLocales.flyersIa
                              : ColoresLocales.bordeSuave,
                        ),
                      ),
                      child: Text(
                        _abreviarLabelPieza(label),
                        style: GoogleFonts.baloo2(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: esRetry
                              ? ColoresLocales.textoEnBoton
                              : ColoresLocales.acentoVioleta,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            decoration: BoxDecoration(
              color: ColoresLocales.superficie,
              border: Border(
                top: BorderSide(color: ColoresLocales.separador),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _FlyerAccionIcono(
                    icono: CupertinoIcons.arrow_down_circle,
                    tooltip: 'Descargar',
                    onTap: onDescarga,
                  ),
                ),
                Container(
                  width: 1,
                  height: 28,
                  color: ColoresLocales.separador,
                ),
                Expanded(
                  child: _FlyerAccionIcono(
                    icono: CupertinoIcons.add_circled,
                    tooltip: 'Crear evento',
                    onTap: onCrearEvento,
                    destacado: true,
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

class _FlyerAccionIcono extends StatelessWidget {
  const _FlyerAccionIcono({
    required this.icono,
    required this.tooltip,
    required this.onTap,
    this.destacado = false,
  });

  final IconData icono;
  final String tooltip;
  final VoidCallback onTap;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icono,
                size: 22,
                color: destacado
                    ? ColoresLocales.acentoVioleta
                    : ColoresLocales.textoSecundarioOnFondoClaro,
              ),
              const SizedBox(height: 2),
              Text(
                tooltip,
                style: GoogleFonts.baloo2(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: destacado
                      ? ColoresLocales.acentoVioleta
                      : ColoresLocales.textoSecundarioOnFondoClaro,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Galería a pantalla completa ─────────────────────────────────────────────

class _FlyerGallery extends StatefulWidget {
  const _FlyerGallery({
    required this.reg,
    required this.initialIndex,
    required this.onDescarga,
  });
  final LocalesFlyerGeneracion reg;
  final int initialIndex;
  final void Function(int index) onDescarga;

  @override
  State<_FlyerGallery> createState() => _FlyerGalleryState();
}

class _FlyerGalleryState extends State<_FlyerGallery> {
  late final PageController _pc;
  late int _index;
  double _dragY = 0;

  @override
  void initState() {
    super.initState();
    final total = _total;
    _index = widget.initialIndex.clamp(0, total > 0 ? total - 1 : 0);
    _pc = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  List<FlyerPieza> get _piezas => widget.reg.todasLasPiezas;
  int get _total => _piezas.length;

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return PopScope(
      canPop: true,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onVerticalDragUpdate: (d) =>
              setState(() => _dragY += d.delta.dy),
          onVerticalDragEnd: (d) {
            if (_dragY > 80 || (d.primaryVelocity ?? 0) > 350) {
              Navigator.of(context).pop();
            } else {
              setState(() => _dragY = 0);
            }
          },
          onVerticalDragCancel: () => setState(() => _dragY = 0),
          child: Transform.translate(
            offset: Offset(0, _dragY),
            child: Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(Icons.close_rounded,
                              color: ColoresLocales.textoEnBoton, size: 26),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white30,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                '${_index < _piezas.length ? _piezas[_index].label : ''} · ${_index + 1}/$_total  ·  Deslizá abajo para cerrar',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.baloo2(
                                  color: Colors.white60,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Botón de descarga en fullscreen
                        IconButton(
                          onPressed: () => widget.onDescarga(_index),
                          icon: Icon(
                            CupertinoIcons.arrow_down_circle_fill,
                            color: ColoresLocales.textoEnBoton,
                            size: 28,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pc,
                    itemCount: _total,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) {
                      final pieza = i < _piezas.length
                          ? _piezas[i]
                          : FlyerPieza(label: '', localPath: '', remoteUrl: '');
                      final esRetry = pieza.label.startsWith('Reintento');
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: _ImagenFlyer(
                                localPath: pieza.localPath,
                                remoteUrl: pieza.remoteUrl,
                                fit: BoxFit.contain,
                              ),
                            ),
                            // Label badge en la galería fullscreen
                            if (pieza.label.isNotEmpty)
                              Positioned(
                                top: 12,
                                left: 20,
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: esRetry
                                        ? ColoresFeaturesLocales.flyersIa.withOpacity(0.85)
                                        : Colors.black.withOpacity(0.55),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    pieza.label,
                                    style: GoogleFonts.baloo2(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: ColoresLocales.textoEnBoton,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
