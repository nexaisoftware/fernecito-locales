part of 'locales_flyer_ia.dart';

// ─── Pantalla: lista de generaciones ─────────────────────────────────────────

class LocalesFlyerIaResultados extends StatefulWidget {
  const LocalesFlyerIaResultados({
    super.key,
    this.abrirGeneracionId,
    this.abrirIndice = 0,
  });

  /// Tras generar, abrir la galería de esta generación automáticamente.
  final String? abrirGeneracionId;
  final int abrirIndice;

  @override
  State<LocalesFlyerIaResultados> createState() =>
      _LocalesFlyerIaResultadosState();
}

class _LocalesFlyerIaResultadosState extends State<LocalesFlyerIaResultados> {
  Timer? _reloj;
  bool _cargandoHistorial = false;
  bool _abrioGaleriaInicial = false;

  @override
  void initState() {
    super.initState();
    LocalesFlyerIaHistorial.instance.addListener(_onHistorialCambio);
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _sincronizarHistorial();
  }

  void _onHistorialCambio() {
    if (mounted) setState(() {});
    _intentarAbrirGaleriaInicial();
  }

  void _intentarAbrirGaleriaInicial() {
    if (_abrioGaleriaInicial || widget.abrirGeneracionId == null) return;
    final reg =
        LocalesFlyerIaHistorial.instance.buscarPorId(widget.abrirGeneracionId!);
    if (reg == null || reg.todasLasPiezas.isEmpty) return;
    _abrioGaleriaInicial = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final idx = widget.abrirIndice.clamp(0, reg.todasLasPiezas.length - 1);
      _abrirFullscreen(reg, idx);
    });
  }

  @override
  void dispose() {
    LocalesFlyerIaHistorial.instance.removeListener(_onHistorialCambio);
    _reloj?.cancel();
    super.dispose();
  }

  Future<void> _sincronizarHistorial() async {
    if (_cargandoHistorial) return;
    if (mounted) setState(() => _cargandoHistorial = true);

    try {
      final cache = FlyerCacheService();
      final servicio = FlyerIaService();
      final h = LocalesFlyerIaHistorial.instance;

      final cacheadas = await cache.cargarTodas();

      for (final c in cacheadas) {
        if (c.id.endsWith('_retry')) continue;
        if (h.buscarPorId(c.id) != null) continue;
        LocalesFlyerFormSnapshot? snap;
        if (c.formulario != null) {
          snap = LocalesFlyerFormSnapshot.desdeCacheFormulario(c.formulario!);
        }
        h.agregar(LocalesFlyerGeneracion(
          id: c.id,
          titulo: c.titulo,
          urlsLocales: c.localPaths,
          urlsRemotas: c.remoteUrls,
          creadoEn: c.createdAt,
          esRetry: false,
          reintentoGratisConsumido: c.retryUsado,
          formularioAlGenerar: snap,
        ));
      }

      for (final c in cacheadas) {
        if (!c.id.endsWith('_retry')) continue;
        final padreId = c.id.replaceFirst(RegExp(r'_retry$'), '');
        final padre = h.buscarPorId(padreId);
        if (padre == null) continue;
        if (padre.urlsLocalesRetry.isEmpty && padre.urlsRemotasRetry.isEmpty) {
          padre.urlsLocalesRetry = List<String>.from(c.localPaths);
          padre.urlsRemotasRetry = List<String>.from(c.remoteUrls);
          padre.reintentoGratisConsumido = true;
        }
      }

      final remotas = await servicio.obtenerHistorial();
      for (final r in remotas) {
        if (r.esRetry) continue;
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
          if (existente.urlsLocales.isEmpty && r.urls.isNotEmpty) {
            existente.urlsRemotas = r.urls;
          }
          if (r.retryUsado && !existente.reintentoGratisConsumido) {
            existente.reintentoGratisConsumido = true;
          }
        }
      }
    } catch (e) {
      debugPrint('_sincronizarHistorial error: $e');
    } finally {
      if (mounted) {
        setState(() => _cargandoHistorial = false);
        _intentarAbrirGaleriaInicial();
      }
    }
  }

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

  Future<GuardarImagenResultado?> _guardarPiezaEnDispositivo(
    FlyerPieza pieza,
    String tituloFlyer, {
    bool feedbackEnOverlay = true,
  }) async {
    HapticFeedback.lightImpact();

    if (pieza.localPath.isEmpty && pieza.remoteUrl.isEmpty) {
      if (feedbackEnOverlay) {
        FeedbackLocales.mostrarError(
          context,
          'Imagen no disponible',
          conNavBar: false,
        );
      }
      return GuardarImagenResultado.error('Imagen no disponible');
    }

    if (feedbackEnOverlay && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ColoresLocales.textoEnBoton,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                kIsWeb ? 'Preparando descarga…' : 'Guardando en dispositivo…',
                style: GoogleFonts.baloo2(
                  fontWeight: FontWeight.w700,
                  color: ColoresLocales.textoEnBoton,
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 20),
          backgroundColor: ColoresLocales.violetaLogoMarca,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
    }

    final resultado = await GuardarImagenDispositivo.guardar(
      localPath: pieza.localPath,
      remoteUrl: pieza.remoteUrl,
      titulo: tituloFlyer,
      etiquetaPieza: pieza.label,
    );

    if (!mounted) return resultado;
    if (feedbackEnOverlay) {
      ScaffoldMessenger.of(context).clearSnackBars();
      if (resultado.ok) {
        HapticFeedback.mediumImpact();
        FeedbackLocales.mostrarExito(
          context,
          resultado.mensaje ??
              (kIsWeb ? 'Descarga iniciada' : 'Guardado en tu galería'),
          conNavBar: false,
        );
      } else {
        HapticFeedback.heavyImpact();
        FeedbackLocales.mostrarError(
          context,
          resultado.mensaje ?? 'No se pudo guardar la imagen',
          conNavBar: false,
        );
      }
    }

    return resultado;
  }

  Future<GuardarImagenResultado?> _guardarPorIndice(
    LocalesFlyerGeneracion reg,
    int index, {
    bool feedbackEnOverlay = true,
  }) async {
    final piezas = reg.todasLasPiezas;
    if (index >= 0 && index < piezas.length) {
      return _guardarPiezaEnDispositivo(
        piezas[index],
        reg.titulo,
        feedbackEnOverlay: feedbackEnOverlay,
      );
    }
    return null;
  }

  PreferredSizeWidget _appBarLista() => AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        backgroundColor: Colors.transparent,
        forceMaterialTransparency: true,
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
          'Tus flyers',
          style: GoogleFonts.baloo2(
            color: ColoresLocales.acentoVioleta,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
      );

  Widget _tarjetaLista(LocalesFlyerGeneracion reg) {
    return Container(
      decoration: ColoresLocales.decoracionCard(radius: 18, sinBorde: true),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            reg.titulo,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.baloo2(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: ColoresLocales.textoOnFondoClaro,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _FlyerTipoBadge(esLibre: reg.esFlyerLibre),
              const SizedBox(width: 8),
              Text(
                _fechaRelativaFlyer(reg.creadoEn),
                style: GoogleFonts.baloo2(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: ColoresLocales.textoSecundarioOnFondoClaro,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _FlyerMiniaturasFila(
            reg: reg,
            onTapSlot: (slot) {
              final idx = reg.indiceGlobalDesdeSlot(slot);
              if (idx >= 0) _abrirFullscreen(reg, idx);
            },
          ),
          const SizedBox(height: 10),
          _FlyerReintentoBar(
            reg: reg,
            onReintentar: () => _abrirReintento(reg),
          ),
        ],
      ),
    );
  }

  Widget _cuerpoLista() {
    final items = LocalesFlyerIaHistorial.instance.itemsMasRecientesPrimero;

    if (items.isEmpty && _cargandoHistorial) {
      return Center(
        child: CircularProgressIndicator(color: ColoresLocales.violetaLogoMarca),
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
            decoration: ColoresLocales.decoracionCard(radius: 22, sinBorde: true),
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
                  'Generá el primero desde Flyer IA.',
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
      color: ColoresLocales.violetaLogoMarca,
      onRefresh: _sincronizarHistorial,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _tarjetaLista(items[i]),
      ),
    );
  }

  void _abrirFullscreen(LocalesFlyerGeneracion reg, int initialIndex) {
    Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        fullscreenDialog: true,
        opaque: false,
        barrierColor: Colors.black.withOpacity(0.94),
        pageBuilder: (context, animation, secondaryAnimation) => _FlyerGallery(
          reg: reg,
          initialIndex: initialIndex,
          onGuardar: (i) => _guardarPorIndice(
            reg,
            i,
            feedbackEnOverlay: false,
          ),
          onCrearEvento: (i) {
            final piezas = reg.todasLasPiezas;
            if (i >= 0 && i < piezas.length) {
              _crearEventoConPieza(reg, piezas[i]);
            }
          },
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return ListenableBuilder(
      listenable: LocalesFlyerIaHistorial.instance,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: ColoresLocales.fondoFormulario,
          appBar: _appBarLista(),
          body: _cuerpoLista(),
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

class _FlyerTipoBadge extends StatelessWidget {
  const _FlyerTipoBadge({required this.esLibre});
  final bool esLibre;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: esLibre
            ? ColoresLocales.violetaLogoMarca.withValues(alpha: 0.12)
            : ColoresLocales.cardLavanda,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        esLibre ? 'Descripción libre' : 'Estructura profesional',
        style: GoogleFonts.baloo2(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: esLibre
              ? ColoresLocales.violetaLogoMarca
              : ColoresLocales.textoSecundarioOnFondoClaro,
        ),
      ),
    );
  }
}

class _FlyerMiniaturasFila extends StatelessWidget {
  const _FlyerMiniaturasFila({
    required this.reg,
    required this.onTapSlot,
  });

  final LocalesFlyerGeneracion reg;
  final void Function(int slot) onTapSlot;

  static const _ancho = 94.0;
  static const _alto = 124.0;
  static const _gap = 15.0;

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final slots = reg.slotsCuatro;
    final conReintento = reg.cantidadReintento > 0;
    final cantidad = conReintento ? 4 : 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < cantidad; i++) ...[
                if (i > 0) const SizedBox(width: _gap),
                _FlyerMiniThumb(
                  pieza: slots[i],
                  label: _labelParaSlot(i, conReintento),
                  esReintento: conReintento && i >= 2,
                  ancho: _ancho,
                  alto: _alto,
                  onTap: slots[i] != null && reg.indiceGlobalDesdeSlot(i) >= 0
                      ? () => onTapSlot(i)
                      : null,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _labelParaSlot(int slot, bool conReintento) {
    if (!conReintento) return slot == 0 ? 'A' : 'B';
    if (slot < 2) return slot == 0 ? 'A' : 'B';
    return slot == 2 ? 'R·A' : 'R·B';
  }
}

class _FlyerMiniThumb extends StatelessWidget {
  const _FlyerMiniThumb({
    required this.pieza,
    required this.label,
    required this.esReintento,
    required this.ancho,
    required this.alto,
    this.onTap,
  });

  final FlyerPieza? pieza;
  final String label;
  final bool esReintento;
  final double ancho;
  final double alto;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final vacio = pieza == null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: ancho,
          height: alto,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: esReintento && !vacio
                  ? ColoresLocales.violetaLogoMarca.withValues(alpha: 0.08)
                  : ColoresLocales.cardLavanda,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: vacio
                  ? Center(
                      child: Icon(
                        CupertinoIcons.photo,
                        size: 26,
                        color: ColoresLocales.textoSecundarioOnFondoClaro
                            .withValues(alpha: 0.4),
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        _ImagenFlyer(
                          localPath: pieza!.localPath,
                          remoteUrl: pieza!.remoteUrl,
                          fit: BoxFit.cover,
                        ),
                        Positioned(
                          left: 5,
                          bottom: 5,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              label,
                              style: GoogleFonts.baloo2(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
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
}

class _FlyerReintentoBar extends StatelessWidget {
  const _FlyerReintentoBar({
    required this.reg,
    required this.onReintentar,
  });

  final LocalesFlyerGeneracion reg;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    if (reg.puedeReintentar) {
      final min = reg.minutosRestantesReintento;
      return SizedBox(
        width: double.infinity,
        height: 38,
        child: ElevatedButton.icon(
          onPressed: onReintentar,
          icon: const Icon(CupertinoIcons.refresh, size: 15),
          label: Text(
            'Reintentar gratis · ${min}m',
            style: GoogleFonts.baloo2(
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: ColoresLocales.violetaLogoMarca,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      );
    }

    final texto = reg.reintentoGratisConsumido
        ? 'Reintento ya utilizado'
        : 'Ventana de reintento cerrada';
    final icono = reg.reintentoGratisConsumido
        ? CupertinoIcons.checkmark_circle
        : CupertinoIcons.clock;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: ColoresLocales.superficieElevada,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icono, size: 14, color: ColoresLocales.textoSecundarioOnFondoClaro),
          const SizedBox(width: 6),
          Text(
            texto,
            style: GoogleFonts.baloo2(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ColoresLocales.textoSecundarioOnFondoClaro,
            ),
          ),
        ],
      ),
    );
  }
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
    if (localPath.isNotEmpty && !kIsWeb) {
      final file = File(localPath);
      return FutureBuilder<bool>(
        future: file.exists(),
        builder: (context, snap) {
          if (snap.data == true) {
            return Image.file(
              file,
              fit: fit,
              errorBuilder: (_, __, ___) => _remotoOPlaceholder(),
            );
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
                  strokeWidth: 2,
                  color: ColoresLocales.violetaLogoMarca,
                ),
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
        child: Icon(
          CupertinoIcons.photo,
          color: ColoresLocales.acentoVioleta.withOpacity(0.35),
        ),
      );
}

// ─── Galería a pantalla completa ─────────────────────────────────────────────

class _FlyerGallery extends StatefulWidget {
  const _FlyerGallery({
    required this.reg,
    required this.initialIndex,
    required this.onGuardar,
    required this.onCrearEvento,
  });

  final LocalesFlyerGeneracion reg;
  final int initialIndex;
  final Future<GuardarImagenResultado?> Function(int index) onGuardar;
  final void Function(int index) onCrearEvento;

  @override
  State<_FlyerGallery> createState() => _FlyerGalleryState();
}

class _FlyerGalleryState extends State<_FlyerGallery> {
  late final PageController _pc;
  late int _index;
  double _dragY = 0;
  bool _guardando = false;
  String? _feedbackGuardado;
  bool _feedbackExito = false;
  Timer? _feedbackTimer;

  @override
  void initState() {
    super.initState();
    final total = _total;
    _index = widget.initialIndex.clamp(0, total > 0 ? total - 1 : 0);
    _pc = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _pc.dispose();
    super.dispose();
  }

  List<FlyerPieza> get _piezas => widget.reg.todasLasPiezas;
  int get _total => _piezas.length;

  FlyerPieza? get _piezaActual =>
      _index >= 0 && _index < _piezas.length ? _piezas[_index] : null;

  void _mostrarFeedbackGuardado(GuardarImagenResultado? resultado) {
    _feedbackTimer?.cancel();
    if (resultado == null) return;

    final ok = resultado.ok;
    final msg = ok
        ? (resultado.mensaje ??
            (kIsWeb ? 'Descarga iniciada' : 'Guardado en tu galería'))
        : (resultado.mensaje ?? 'No se pudo guardar la imagen');

    if (ok) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }

    setState(() {
      _feedbackExito = ok;
      _feedbackGuardado = msg;
    });

    _feedbackTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _feedbackGuardado = null);
    });
  }

  Future<void> _onGuardarTap() async {
    if (_guardando) return;
    setState(() {
      _guardando = true;
      _feedbackGuardado = null;
    });
    final resultado = await widget.onGuardar(_index);
    if (!mounted) return;
    setState(() => _guardando = false);
    _mostrarFeedbackGuardado(resultado);
  }

  String get _textoBotonGuardar {
    if (_guardando) {
      return kIsWeb ? 'Descargando…' : 'Guardando…';
    }
    if (_feedbackExito && _feedbackGuardado != null) {
      return kIsWeb ? '¡Descargado!' : '¡Guardado!';
    }
    return kIsWeb ? 'Descargar imagen' : 'Guardar en dispositivo';
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final pieza = _piezaActual;
    final esRetry = pieza?.label.startsWith('Reintento') ?? false;

    return PopScope(
      canPop: true,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onVerticalDragUpdate: (d) => setState(() => _dragY += d.delta.dy),
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
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                    child: Column(
                      children: [
                        Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white30,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(
                                CupertinoIcons.xmark,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  Text(
                                    widget.reg.titulo,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.baloo2(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${pieza?.label ?? ''} · ${_index + 1}/$_total',
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
                            const SizedBox(width: 48),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _FlyerTipoBadge(esLibre: widget.reg.esFlyerLibre),
                            if (pieza != null && esRetry) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: ColoresLocales.violetaLogoMarca
                                      .withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Reintento',
                                  style: GoogleFonts.baloo2(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pc,
                    itemCount: _total,
                    onPageChanged: (i) => setState(() {
                      _index = i;
                      _feedbackGuardado = null;
                    }),
                    itemBuilder: (context, i) {
                      final p = _piezas[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: _ImagenFlyer(
                            localPath: p.localPath,
                            remoteUrl: p.remoteUrl,
                            fit: BoxFit.contain,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: _feedbackGuardado == null
                              ? const SizedBox.shrink(key: ValueKey('sin_fb'))
                              : Container(
                                  key: ValueKey(_feedbackGuardado),
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _feedbackExito
                                        ? const Color(0xFF16A34A)
                                            .withValues(alpha: 0.92)
                                        : const Color(0xFFDC2626)
                                            .withValues(alpha: 0.92),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _feedbackExito
                                            ? CupertinoIcons
                                                .checkmark_circle_fill
                                            : CupertinoIcons
                                                .exclamationmark_circle_fill,
                                        size: 18,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _feedbackGuardado!,
                                          style: GoogleFonts.baloo2(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: _guardando ? null : _onGuardarTap,
                            icon: _guardando
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: ColoresLocales.violetaLogoMarca,
                                    ),
                                  )
                                : Icon(
                                    _feedbackExito && _feedbackGuardado != null
                                        ? CupertinoIcons.checkmark
                                        : (kIsWeb
                                            ? CupertinoIcons.arrow_down_circle
                                            : CupertinoIcons.arrow_down_to_line),
                                    size: 20,
                                  ),
                            label: Text(
                              _textoBotonGuardar,
                              style: GoogleFonts.baloo2(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: Colors.white,
                              foregroundColor: ColoresLocales.violetaLogoMarca,
                              disabledBackgroundColor:
                                  Colors.white.withValues(alpha: 0.7),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 46,
                          child: TextButton.icon(
                            onPressed: pieza == null
                                ? null
                                : () => widget.onCrearEvento(_index),
                            icon: const Icon(
                              CupertinoIcons.add_circled,
                              size: 20,
                            ),
                            label: Text(
                              'Crear evento con este flyer',
                              style: GoogleFonts.baloo2(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.white.withValues(alpha: 0.12),
                              disabledForegroundColor: Colors.white38,
                              disabledBackgroundColor:
                                  Colors.white.withValues(alpha: 0.06),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Deslizá hacia abajo para cerrar',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.baloo2(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white38,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
