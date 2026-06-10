/// Generador de flyers con IA — formulario (resultados en part).
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants.dart';
import '../core/crear_evento_desde_flyer_args.dart';
import '../widgets/badge_etiqueta_locales.dart';
import '../widgets/tema_locales_scope.dart';
import '../services/flyer_cache_service.dart';
import '../services/flyer_ia_service.dart';

part 'locales_flyer_ia_resultados.dart';

const String _kTituloAppBar = 'Generar flyer AI';
const int _kMaxPromptLibre = 1000;

enum _FlyerModoCreacion { libre, estructurado }

// ─── Catálogo de estilos ──────────────────────────────────────────────────────

const _kFlyerEstilosAssetDir = 'assets/imagenes/flyer_ia_estilos';

/// Previews locales (1–17). Agregar `N_<id>.jpg` en [_kFlyerEstilosAssetDir].
const Map<String, String> _flyerEstiloPreviewAssets = {
  'dark_night': '$_kFlyerEstilosAssetDir/1_dark_night.jpg',
  'neon_party': '$_kFlyerEstilosAssetDir/2_neon_party.jpg',
  'sunset_party': '$_kFlyerEstilosAssetDir/3_sunset_party.jpg',
  'cinematic': '$_kFlyerEstilosAssetDir/4_cinematic.jpg',
  'caricature': '$_kFlyerEstilosAssetDir/5_caricature.jpg',
  'funny_color': '$_kFlyerEstilosAssetDir/6_funny_color.jpg',
  'gourmet_warm': '$_kFlyerEstilosAssetDir/7_gourmet_warm.jpg',
  'wood_fine': '$_kFlyerEstilosAssetDir/8_wood_fine.jpg',
  'tropical_fiesta': '$_kFlyerEstilosAssetDir/9_tropical_fiesta.jpg',
  'urban_street': '$_kFlyerEstilosAssetDir/10_urban_street.jpg',
  'golden_luxury': '$_kFlyerEstilosAssetDir/11_golden_luxury.jpg',
  'retro_vintage': '$_kFlyerEstilosAssetDir/12_retro_vintage.jpg',
  'epic_stage': '$_kFlyerEstilosAssetDir/13_epic_stage.jpg',
  'pixar_world': '$_kFlyerEstilosAssetDir/14_pixar_world.jpg',
  'synthwave': '$_kFlyerEstilosAssetDir/15_synthwave.jpg',
  'minimal_ibiza': '$_kFlyerEstilosAssetDir/16_minimal_ibiza.jpg',
  'brutalist_type': '$_kFlyerEstilosAssetDir/17_brutalist_type.jpg',
};

class _EstiloFlyer {
  const _EstiloFlyer({
    required this.id,
    required this.nombre,
    required this.descripcion,
  });
  final String id;
  final String nombre;
  final String descripcion;
  String? get previewAsset => _flyerEstiloPreviewAssets[id];
}

List<_EstiloFlyer> _estilos = [
  _EstiloFlyer(id: 'dark_night',      nombre: 'Dark Night',       descripcion: 'Escenario oscuro con spotlights dramáticos. Chrome bold. Layout cinematográfico con glassmorphism footer.'),
  _EstiloFlyer(id: 'neon_party',      nombre: 'Neon Party',       descripcion: 'UV neones eléctricos sobre negro. Layout roto y asimétrico, energía rave underground.'),
  _EstiloFlyer(id: 'sunset_party',    nombre: 'Sunset Party',     descripcion: 'Golden hour editorial. Fecha en header, título serif cursivo al centro. Minimalismo cálido.'),
  _EstiloFlyer(id: 'cinematic',       nombre: 'Cinematic',        descripcion: 'Movie poster con profundidad de capas. Texto integrado en la escena. Teal & orange Hollywood.'),
  _EstiloFlyer(id: 'caricature',      nombre: 'Caricature',       descripcion: 'Ilustración cartoon 2D con linework bold. Badges de starburst, banner ribbon en footer.'),
  _EstiloFlyer(id: 'funny_color',     nombre: 'Funny & Color',    descripcion: 'Color blocking extremo, saturación máxima. Tipografía gigante por bandas de color.'),
  _EstiloFlyer(id: 'gourmet_warm',    nombre: 'Gourmet Warm',     descripcion: 'Editorial gastronómico minimalista. Mucho espacio negativo, serif fina, mármol y madera clara.'),
  _EstiloFlyer(id: 'wood_fine',       nombre: 'Wood & Fine',      descripcion: 'Club privado exclusivo. Sello de cera dorado, madera oscura, candlelight, laureles en footer.'),
  _EstiloFlyer(id: 'tropical_fiesta', nombre: 'Tropical Fiesta',  descripcion: 'Fiesta latina máxima energía. 3D gold extruded, estarburst de fecha, banner footer festivo.'),
  _EstiloFlyer(id: 'urban_street',    nombre: 'Urban Street',     descripcion: 'Street art graffiti auténtico. Layout broken-grid, torn paper reveal en footer, stencil date.'),
  _EstiloFlyer(id: 'golden_luxury',   nombre: 'Golden Luxury',    descripcion: 'Mármol negro con oro 24k exclusivo. Contenedor dorado enchapado, logos gold en footer.'),
  _EstiloFlyer(id: 'retro_vintage',   nombre: 'Retro Vintage',    descripcion: 'Póster boliche 2000s estilo Risograph. Tipografía gig-poster apilada, sello vintage, misregistration.'),
  _EstiloFlyer(id: 'epic_stage',      nombre: 'Epic Stage',       descripcion: 'Estadio épico ALL CAPS. Torn paper metálico revela la fecha. Pyrotecnia y foreshortening de título.'),
  _EstiloFlyer(id: 'pixar_world',     nombre: 'Pixar World',      descripcion: 'CGI 3D calidad Disney/Pixar. Título inflado tipo cartelera, fecha "NOW SHOWING", banner 3D en footer.'),
  _EstiloFlyer(id: 'synthwave',       nombre: 'Synthwave',        descripcion: 'Retrowave 80s: grid de perspectiva, sol retro, palmeras neón. Miami Vice meets Blade Runner.'),
  _EstiloFlyer(id: 'minimal_ibiza',   nombre: 'Minimal Ibiza',    descripcion: 'Lujo minimalista blanco total. Fecha en header, serif editorial Vogue-style, zero contenedores.'),
  _EstiloFlyer(id: 'brutalist_type',  nombre: 'Brutalist Type',   descripcion: 'La tipografía ES el diseño. Swiss grid, Helvetica Black extremo, máximo contraste B&N, Berlin techno.'),
];

Widget _previewEstiloFlyer(_EstiloFlyer e) => _EstiloFlyerPreviewImage(estilo: e);

/// Ancho de una celda del grid de estilos (misma lógica que el carrusel 3 columnas).
double _anchoCeldaGridEstilo(BuildContext context) {
  const formPad = 18.0;
  const cardPad = 18.0;
  const spacing = 10.0;
  final w = MediaQuery.sizeOf(context).width;
  final inner = math.min(w - formPad * 2, 560.0);
  return (inner - cardPad * 2 - spacing * 2) / 3;
}

/// Preview ~3× la celda del grid (ancho ≈ fila completa del grid).
Size _tamanoPreviewEstiloAmpliado(BuildContext context) {
  const aspectoCelda = 0.60;
  final cellW = _anchoCeldaGridEstilo(context);
  var ancho = cellW * 3 + 10 * 2;
  var alto = ancho / aspectoCelda;
  final maxAlto = MediaQuery.sizeOf(context).height * 0.42;
  if (alto > maxAlto) {
    alto = maxAlto;
    ancho = alto * aspectoCelda;
  }
  return Size(ancho, alto);
}

class _EstiloFlyerPreviewImage extends StatelessWidget {
  const _EstiloFlyerPreviewImage({required this.estilo});
  final _EstiloFlyer estilo;

  @override
  Widget build(BuildContext context) {
    final asset = estilo.previewAsset;
    if (asset != null) {
      return Image.asset(
        asset,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _previewEstiloFlyerPlaceholder(),
      );
    }
    return _previewEstiloFlyerPlaceholder();
  }
}

Widget _previewEstiloFlyerPlaceholder() {
  return ColoredBox(
    color: ColoresLocales.cardLavanda,
    child: Center(
      child: Icon(
        CupertinoIcons.sparkles,
        color: ColoresLocales.acentoVioleta.withOpacity(0.45),
        size: 28,
      ),
    ),
  );
}

List<String> _diasSemana = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
List<String> _meses = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];

// ─── Colores internos ─────────────────────────────────────────────────────────

// ─── Modelo en memoria (luego edge / Supabase) ───────────────────────────────

class LocalesFlyerFormSnapshot {
  const LocalesFlyerFormSnapshot({
    this.modo = 'estructurado',
    this.promptLibre,
    required this.claim,
    required this.fondo,
    required this.estiloId,
    required this.mostrarPropio,
    required this.textoPropio,
    required this.diaIdx,
    required this.diaMes,
    required this.mesIdx,
    required this.hora,
    required this.minuto,
    this.promos,
    this.lineup,
    this.sponsors,
    this.dresscode,
  });

  /// `estructurado` | `libre`
  final String modo;
  final String? promptLibre;
  final String claim;
  final String fondo;
  final String estiloId;
  final bool mostrarPropio;
  final String textoPropio;
  final int diaIdx;
  final int diaMes;
  final int mesIdx;
  final int hora;
  final int minuto;

  // Campos opcionales
  final String? promos;
  final String? lineup;
  final String? sponsors;
  final String? dresscode;

  bool get esLibre => modo == 'libre';

  /// Convierte a FlyerCacheFormulario para persistir en disco.
  FlyerCacheFormulario toCacheFormulario() => FlyerCacheFormulario(
        modo: modo,
        promptLibre: promptLibre,
        claim: claim,
        fondo: fondo,
        estiloId: estiloId,
        mostrarPropio: mostrarPropio,
        textoPropio: textoPropio,
        diaIdx: diaIdx,
        diaMes: diaMes,
        mesIdx: mesIdx,
        hora: hora,
        minuto: minuto,
      );

  /// Crea un snapshot desde un FlyerCacheFormulario.
  static LocalesFlyerFormSnapshot desdeCacheFormulario(FlyerCacheFormulario f) =>
      LocalesFlyerFormSnapshot(
        modo: f.modo,
        promptLibre: f.promptLibre,
        claim: f.claim,
        fondo: f.fondo,
        estiloId: f.estiloId,
        mostrarPropio: f.mostrarPropio,
        textoPropio: f.textoPropio,
        diaIdx: f.diaIdx,
        diaMes: f.diaMes,
        mesIdx: f.mesIdx,
        hora: f.hora,
        minuto: f.minuto,
      );
}

class LocalesFlyerIaRetryArgs {
  const LocalesFlyerIaRetryArgs({
    required this.registroId,
    required this.titulo,
    this.formulario,
  });
  final String registroId;
  final String titulo;
  final LocalesFlyerFormSnapshot? formulario;
}

/// Una "pieza" dentro de una generación: imagen + label para mostrar al usuario.
class FlyerPieza {
  const FlyerPieza({
    required this.label,
    required this.localPath,
    required this.remoteUrl,
  });
  final String label;      // "Original A", "Original B", "Reintento A", "Reintento B"
  final String localPath;  // ruta local en dispositivo (puede ser vacía)
  final String remoteUrl;  // URL remota fallback (puede ser vacía)
}

class LocalesFlyerGeneracion {
  LocalesFlyerGeneracion({
    required this.id,
    required this.titulo,
    List<String> urlsLocales = const [],
    List<String> urlsRemotas = const [],
    required this.creadoEn,
    this.esRetry = false,
    this.reintentoGratisConsumido = false,
    this.formularioAlGenerar,
  })  : urlsLocales = List<String>.from(urlsLocales),
        urlsRemotas = List<String>.from(urlsRemotas);

  final String id;
  final String titulo;

  /// Rutas en el dispositivo (caché local) — imágenes de la generación original.
  List<String> urlsLocales;

  /// URLs remotas — imágenes de la generación original.
  List<String> urlsRemotas;

  /// Imágenes del retry (se agregan cuando llega el reintento, no reemplazan).
  List<String> urlsLocalesRetry = [];
  List<String> urlsRemotasRetry = [];

  DateTime creadoEn;
  final bool esRetry;
  bool reintentoGratisConsumido;
  LocalesFlyerFormSnapshot? formularioAlGenerar;

  static const Duration ventanaReintento = Duration(minutes: 10);

  bool get puedeReintentar =>
      !esRetry &&
      DateTime.now().isBefore(creadoEn.add(ventanaReintento)) &&
      !reintentoGratisConsumido;

  int get minutosRestantesReintento {
    final fin = creadoEn.add(ventanaReintento);
    final s = fin.difference(DateTime.now()).inSeconds;
    if (s <= 0) return 0;
    return (s / 60).ceil();
  }

  /// Todas las piezas disponibles en orden: originales primero, luego retry.
  /// Máximo 4 (2 originales + 2 retry si hubo reintento).
  List<FlyerPieza> get todasLasPiezas {
    final resultado = <FlyerPieza>[];
    final labelsOrig = ['Original A', 'Original B'];
    final labelsRetry = ['Reintento A', 'Reintento B'];
    final cantOrig = urlsLocales.length > urlsRemotas.length
        ? urlsLocales.length
        : urlsRemotas.length;
    for (var i = 0; i < cantOrig; i++) {
      resultado.add(FlyerPieza(
        label: i < labelsOrig.length ? labelsOrig[i] : 'Original ${i + 1}',
        localPath: i < urlsLocales.length ? urlsLocales[i] : '',
        remoteUrl: i < urlsRemotas.length ? urlsRemotas[i] : '',
      ));
    }
    final cantRetry = urlsLocalesRetry.length > urlsRemotasRetry.length
        ? urlsLocalesRetry.length
        : urlsRemotasRetry.length;
    for (var i = 0; i < cantRetry; i++) {
      resultado.add(FlyerPieza(
        label: i < labelsRetry.length ? labelsRetry[i] : 'Reintento ${i + 1}',
        localPath: i < urlsLocalesRetry.length ? urlsLocalesRetry[i] : '',
        remoteUrl: i < urlsRemotasRetry.length ? urlsRemotasRetry[i] : '',
      ));
    }
    return resultado;
  }
}

class LocalesFlyerIaHistorial extends ChangeNotifier {
  LocalesFlyerIaHistorial._();
  static final LocalesFlyerIaHistorial instance = LocalesFlyerIaHistorial._();

  final List<LocalesFlyerGeneracion> _items = [];

  List<LocalesFlyerGeneracion> get itemsMasRecientesPrimero =>
      List<LocalesFlyerGeneracion>.from(_items.reversed);

  String nuevoId() =>
      '${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(1 << 30)}';

  LocalesFlyerGeneracion? buscarPorId(String id) {
    for (final g in _items) {
      if (g.id == id) return g;
    }
    return null;
  }

  void agregar(LocalesFlyerGeneracion g) {
    _items.add(g);
    notifyListeners();
  }

  void aplicarReintento(
    String id,
    List<String> nuevasUrlsRemotas,
    List<String> nuevasUrlsLocales,
    LocalesFlyerFormSnapshot formulario,
  ) {
    final g = buscarPorId(id);
    if (g == null) return;
    // Las imágenes del retry se AGREGAN como segunda tanda, no reemplazan las originales
    g.urlsRemotasRetry = List<String>.from(nuevasUrlsRemotas);
    g.urlsLocalesRetry = List<String>.from(nuevasUrlsLocales);
    g.reintentoGratisConsumido = true;
    g.formularioAlGenerar = formulario;
    notifyListeners();
  }
}

// ─── Widget principal ─────────────────────────────────────────────────────────

class LocalesFlyerIa extends StatefulWidget {
  const LocalesFlyerIa({super.key, this.retry});

  final LocalesFlyerIaRetryArgs? retry;

  @override
  State<LocalesFlyerIa> createState() => _LocalesFlyerIaState();
}

class _LocalesFlyerIaState extends State<LocalesFlyerIa> {
  _FlyerModoCreacion? _modoCreacion;

  final _ctrlTitulo   = TextEditingController();
  final _ctrlClaim    = TextEditingController();
  final _ctrlPropio   = TextEditingController();
  final _ctrlFondo    = TextEditingController();
  final _ctrlPromptLibre = TextEditingController();

  // Campos opcionales
  final _ctrlPromos    = TextEditingController();
  final _ctrlLineup    = TextEditingController();
  final _ctrlSponsors  = TextEditingController();
  final _ctrlDresscode = TextEditingController();

  // Acordeones de opcionales
  bool _mostrarPromos    = false;
  bool _mostrarLineup    = false;
  bool _mostrarSponsors  = false;
  bool _mostrarDresscode = false;

  // Segunda fecha opcional
  bool _mostrarSegundaFecha = false;
  int _diaIdx2  = 5; // sábado
  int _diaMes2  = 19;
  int _mesIdx2  = 2;

  final FocusNode _focusPropio = FocusNode();
  final FocusNode _focusFondo = FocusNode();

  int _diaIdx  = 4;
  int _diaMes  = 18;
  int _mesIdx  = 2; // 0-based
  int _hora    = 22;
  int _minuto  = 0;

  String _estiloId = _estilos.first.id;
  bool _mostrarPropio = false;
  int _creditos = 0;

  bool _modoReintentoGratis = false;
  bool _tituloBloqueado = false;
  String? _registroRetryId;

  // ── Estado de generación real ────────────────────────────────────────────
  bool _generando = false;
  String? _errorGeneracion;

  _EstiloFlyer? _estiloHint;
  Timer? _hintTimer;
  Timer? _placeholderTimer;

  int _hintPropioIndex = 0;
  int _hintFondoIndex = 0;

  static const List<String> _ideasEstilo = [
    'Ej: tipografía ultra bold, tonos fríos y glow azul eléctrico.',
    'Ej: letras retro infladas, colores pop y contraste extremo.',
    'Ej: estilo elegante minimal con serif fina y acentos dorados.',
    'Ej: look cyberpunk con neón magenta/cian y sombras intensas.',
    'Ej: estética comic loca con títulos gigantes y colores ácidos.',
  ];

  static const List<String> _ideasPromptLibre = [
    'Ej: Flyer para fiesta electrónica el sábado 15/8 en Club X, 23hs. Título "NEON NIGHT", colores neón, DJ Luna y Marco en el lineup, 2x1 en trago hasta medianoche.',
    'Ej: Cartel vertical para cena degustación viernes 20/6, estilo gourmet minimal, título "Sabores de Invierno", dress code elegante, reservas al 11-5555-1234.',
    'Ej: Boliche retro 2000s, título gigante "FLASHBACK", fecha sábado 12 de julio 00:30hs, estética risograph vintage, promo entrada libre mujeres hasta 1am.',
  ];

  static const List<String> _ideasFondo = [
    'Ej: DJ con traje de astronauta tocando techno en Marte.',
    'Ej: hamburguesa gigante con papas surfeando en un río de cheddar.',
    'Ej: unicornio barista sirviendo espresso en una galaxia neón.',
    'Ej: conejo apocalíptico cantando reggaetón en una disco lunar.',
    'Ej: pista boliche en una nave espacial con lluvia de confetti láser.',
  ];


  @override
  void initState() {
    super.initState();
    final r = widget.retry;
    if (r != null) {
      _ctrlTitulo.text = r.titulo;
      _tituloBloqueado = true;
      _modoReintentoGratis = true;
      _registroRetryId = r.registroId;
      final f = r.formulario;
      if (f != null) {
        _aplicarFormularioDesdeSnapshot(f);
        _modoCreacion = f.esLibre ? _FlyerModoCreacion.libre : _FlyerModoCreacion.estructurado;
      } else {
        _modoCreacion = _FlyerModoCreacion.estructurado;
      }
    }
    _placeholderTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      setState(() {
        if (!_focusPropio.hasFocus) {
          _hintPropioIndex = (_hintPropioIndex + 1) % _ideasEstilo.length;
        }
        if (!_focusFondo.hasFocus) {
          _hintFondoIndex = (_hintFondoIndex + 1) % _ideasFondo.length;
        }
      });
    });
    // Cargar créditos reales y verificar pendiente al abrir
    _cargarCreditosYVerificarPendiente();
  }

  Future<void> _cargarCreditosYVerificarPendiente() async {
    final servicio = FlyerIaService();
    final creditos = await servicio.obtenerCreditos();
    if (mounted) setState(() => _creditos = creditos);

    // Solo verificar pendiente si no es un retry (evitar confusión)
    if (widget.retry == null) {
      final pendiente = await servicio.verificarPendiente();
      if (pendiente != null && mounted) {
        // Hay un flyer pendiente no entregado — cachearlo y navegar
        final h = LocalesFlyerIaHistorial.instance;
        final yaExiste = h.buscarPorId(pendiente.generacionId) != null;
        if (!yaExiste) {
          // Guardar en caché local antes de confirmar
          final cacheada = await FlyerCacheService().guardarGeneracion(
            id: pendiente.generacionId,
            titulo: pendiente.titulo,
            estiloNombre: pendiente.estiloNombre,
            urls: pendiente.urls,
            esRetry: pendiente.esRetry,
            retryUsado: pendiente.retryUsado,
            createdAt: pendiente.createdAt,
          );
          h.agregar(LocalesFlyerGeneracion(
            id: pendiente.generacionId,
            titulo: pendiente.titulo,
            urlsLocales: cacheada.localPaths,
            urlsRemotas: pendiente.urls,
            creadoEn: pendiente.createdAt,
            reintentoGratisConsumido: pendiente.retryUsado,
          ));
        }
        // Confirmar entrega → edge borra el Storage
        await servicio.confirmarEntrega(pendiente.generacionId);
      }
    }
  }

  bool get _esModoLibre =>
      _modoCreacion == _FlyerModoCreacion.libre ||
      (widget.retry?.formulario?.esLibre ?? false);

  bool get _formularioCompleto {
    if (_esModoLibre) {
      final p = _ctrlPromptLibre.text.trim();
      return p.isNotEmpty && p.length <= _kMaxPromptLibre;
    }
    final tituloOk = _ctrlTitulo.text.trim().isNotEmpty;
    final claimOk = _ctrlClaim.text.trim().isNotEmpty;
    final fondoOk = _ctrlFondo.text.trim().isNotEmpty;
    final propioOk = !_mostrarPropio || _ctrlPropio.text.trim().isNotEmpty;
    return tituloOk && claimOk && fondoOk && propioOk;
  }

  String _tituloParaGeneracion() {
    if (_esModoLibre) {
      final p = _ctrlPromptLibre.text.trim();
      if (p.isEmpty) return 'Flyer IA';
      final linea = p.split('\n').first.trim();
      return linea.length > 80 ? '${linea.substring(0, 80)}…' : linea;
    }
    return _ctrlTitulo.text.trim();
  }

  static int _normalizarMinutoPicker(int m) {
    const opts = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55];
    var best = opts.first;
    var diff = 99;
    for (final o in opts) {
      final d = (m - o).abs();
      if (d < diff) {
        diff = d;
        best = o;
      }
    }
    return best;
  }

  void _aplicarFormularioDesdeSnapshot(LocalesFlyerFormSnapshot f) {
    if (f.esLibre) {
      _ctrlPromptLibre.text = f.promptLibre ?? '';
      return;
    }
    _ctrlClaim.text = f.claim;
    _ctrlFondo.text = f.fondo;
    _ctrlPropio.text = f.textoPropio;
    final idOk = _estilos.any((e) => e.id == f.estiloId);
    _estiloId = idOk ? f.estiloId : _estilos.first.id;
    _mostrarPropio = f.mostrarPropio;
    _diaIdx = f.diaIdx.clamp(0, 6);
    _diaMes = f.diaMes.clamp(1, 31);
    _mesIdx = f.mesIdx.clamp(0, 11);
    _hora = f.hora.clamp(0, 23);
    _minuto = _normalizarMinutoPicker(f.minuto);
  }

  LocalesFlyerFormSnapshot _capturarFormulario() {
    if (_esModoLibre) {
      return LocalesFlyerFormSnapshot(
        modo: 'libre',
        promptLibre: _ctrlPromptLibre.text.trim(),
        claim: '',
        fondo: '',
        estiloId: 'prompt_libre',
        mostrarPropio: false,
        textoPropio: '',
        diaIdx: _diaIdx,
        diaMes: _diaMes,
        mesIdx: _mesIdx,
        hora: _hora,
        minuto: _minuto,
      );
    }

    // Fecha: si hay segunda fecha, construir string combinado
    final String? promos   = _mostrarPromos   && _ctrlPromos.text.trim().isNotEmpty   ? _ctrlPromos.text.trim()   : null;
    final String? lineup   = _mostrarLineup   && _ctrlLineup.text.trim().isNotEmpty   ? _ctrlLineup.text.trim()   : null;
    final String? sponsors = _mostrarSponsors && _ctrlSponsors.text.trim().isNotEmpty ? _ctrlSponsors.text.trim() : null;
    final String? dresscode = _mostrarDresscode && _ctrlDresscode.text.trim().isNotEmpty ? _ctrlDresscode.text.trim() : null;

    return LocalesFlyerFormSnapshot(
      modo: 'estructurado',
      claim: _ctrlClaim.text.trim(),
      fondo: _ctrlFondo.text.trim(),
      estiloId: _estiloId,
      mostrarPropio: _mostrarPropio,
      textoPropio: _ctrlPropio.text.trim(),
      diaIdx: _diaIdx,
      diaMes: _diaMes,
      mesIdx: _mesIdx,
      hora: _hora,
      minuto: _minuto,
      promos: promos,
      lineup: lineup,
      sponsors: sponsors,
      dresscode: dresscode,
    );
  }

  // Construye el string de fecha (soporta segunda fecha opcional)
  String _buildFechaString() {
    final mes1 = _meses[_mesIdx];
    final base = '$_diaMes de $mes1';
    if (!_mostrarSegundaFecha) return base;
    final mes2 = _meses[_mesIdx2];
    if (_mesIdx2 == _mesIdx) {
      // mismo mes: "Viernes 11 y Sábado 12 de Julio"
      return '$_diaMes y $_diaMes2 de $mes1';
    }
    return '$_diaMes de $mes1 y $_diaMes2 de $mes2';
  }

  String _buildDiaSemanaString() {
    final dia1 = _diasSemana[_diaIdx];
    if (!_mostrarSegundaFecha) return dia1;
    return '$dia1 y ${_diasSemana[_diaIdx2]}';
  }

  void _avisarTituloNoEditable() {
    if (!_tituloBloqueado || !mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Este campo no se puede editar en un reintento gratis.',
          style: GoogleFonts.baloo2(
            fontWeight: FontWeight.w800,
            color: ColoresLocales.textoEnBoton,
          ),
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _placeholderTimer?.cancel();
    _focusPropio.dispose();
    _focusFondo.dispose();
    _ctrlTitulo.dispose();
    _ctrlClaim.dispose();
    _ctrlPropio.dispose();
    _ctrlFondo.dispose();
    _ctrlPromptLibre.dispose();
    _ctrlPromos.dispose();
    _ctrlLineup.dispose();
    _ctrlSponsors.dispose();
    _ctrlDresscode.dispose();
    super.dispose();
  }

  // ── Helpers visuales ────────────────────────────────────────────────────────

  String _diaSemanaCorto() {
    final cortos = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    return cortos[_diaIdx];
  }

  String _mesCorto() {
    final cortos = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    return cortos[_mesIdx];
  }

  InputDecoration _dec(String hint, {String? helper}) => InputDecoration(
        hintText: hint,
        helperText: helper,
        hintStyle: GoogleFonts.baloo2(
          color: ColoresLocales.textoSecundarioOnFondoClaro,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        helperStyle: GoogleFonts.baloo2(
          fontSize: 12,
          color: ColoresLocales.textoSecundarioOnFondoClaro,
        ),
        filled: true,
        fillColor: ColoresLocales.rellenoInput,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: BorderSide(color: ColoresLocales.acentoVioleta, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: BorderSide(color: ColoresLocales.acentoVioleta.withOpacity(0.28), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: BorderSide(color: ColoresLocales.acentoVioleta, width: 2),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      );

  InputDecoration _decMultilinea(String hint, {String? helper}) => InputDecoration(
        hintText: hint,
        helperText: helper,
        hintStyle: GoogleFonts.baloo2(
          color: ColoresLocales.textoSecundarioOnFondoClaro,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        helperStyle: GoogleFonts.baloo2(
          fontSize: 12,
          color: ColoresLocales.textoSecundarioOnFondoClaro,
        ),
        filled: true,
        fillColor: ColoresLocales.rellenoInput,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: ColoresLocales.acentoVioleta, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: ColoresLocales.acentoVioleta.withOpacity(0.28), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: ColoresLocales.acentoVioleta, width: 2),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        width: double.infinity,
        padding: padding ?? EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: ColoresLocales.superficie,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: ColoresLocales.acentoVioleta.withOpacity(0.14)),
          boxShadow: [
            BoxShadow(
              color: ColoresLocales.acentoVioleta.withOpacity(0.07),
              blurRadius: 20,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: child,
      );

  Widget _seccionLabel(String texto) => Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Text(
          texto,
          style: GoogleFonts.baloo2(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: ColoresLocales.acentoVioleta,
          ),
        ),
      );

  Widget _seccionLabelIcono(String texto, IconData icono) => Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Icon(icono, size: 16, color: ColoresLocales.acentoVioleta),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                texto,
                style: GoogleFonts.baloo2(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: ColoresLocales.acentoVioleta,
                ),
              ),
            ),
          ],
        ),
      );

  // ── Selector iOS-style: bottom sheet con CupertinoPicker ────────────────────

  Future<void> _pickDiaSemana() async {
    int temp = _diaIdx;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => _PickerSheet(
        title: 'Día de la semana',
        child: CupertinoPicker(
          scrollController: FixedExtentScrollController(initialItem: temp),
          itemExtent: 44,
          onSelectedItemChanged: (i) => temp = i,
          children: _diasSemana
              .map((d) => Center(
                    child: Text(d,
                        style: GoogleFonts.baloo2(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                  ))
              .toList(),
        ),
        onDone: () => setState(() => _diaIdx = temp),
      ),
    );
  }

  Future<void> _pickFecha() async {
    int tempDia = _diaMes;
    int tempMes = _mesIdx;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => _PickerSheet(
        title: 'Día y mes',
        child: Row(
          children: [
            Expanded(
              child: CupertinoPicker(
                scrollController: FixedExtentScrollController(initialItem: tempDia - 1),
                itemExtent: 44,
                onSelectedItemChanged: (i) => tempDia = i + 1,
                children: List.generate(
                  31,
                  (i) => Center(
                    child: Text('${i + 1}',
                        style: GoogleFonts.baloo2(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: CupertinoPicker(
                scrollController: FixedExtentScrollController(initialItem: tempMes),
                itemExtent: 44,
                onSelectedItemChanged: (i) => tempMes = i,
                children: _meses
                    .map((m) => Center(
                          child: Text(m,
                              style: GoogleFonts.baloo2(
                                  fontSize: 17, fontWeight: FontWeight.w700)),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
        onDone: () => setState(() {
          _diaMes = tempDia;
          _mesIdx = tempMes;
        }),
      ),
    );
  }

  Future<void> _pickHora() async {
    int tempH = _hora;
    int tempM = _minuto;
    final minutosOpciones = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55];
    int tempMIdx = minutosOpciones.indexOf(tempM).clamp(0, minutosOpciones.length - 1);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => _PickerSheet(
        title: 'Hora de inicio',
        child: Row(
          children: [
            Expanded(
              child: CupertinoPicker(
                scrollController: FixedExtentScrollController(initialItem: tempH),
                itemExtent: 44,
                onSelectedItemChanged: (i) => tempH = i,
                children: List.generate(
                  24,
                  (i) => Center(
                    child: Text(i.toString().padLeft(2, '0'),
                        style: GoogleFonts.baloo2(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ),
            Text(':',
                style: GoogleFonts.baloo2(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: ColoresLocales.acentoVioleta)),
            Expanded(
              child: CupertinoPicker(
                scrollController: FixedExtentScrollController(initialItem: tempMIdx),
                itemExtent: 44,
                onSelectedItemChanged: (i) => tempMIdx = i,
                children: minutosOpciones
                    .map((m) => Center(
                          child: Text(m.toString().padLeft(2, '0'),
                              style: GoogleFonts.baloo2(
                                  fontSize: 20, fontWeight: FontWeight.w800)),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
        onDone: () => setState(() {
          _hora   = tempH;
          _minuto = minutosOpciones[tempMIdx];
        }),
      ),
    );
  }

  // ── Toque en un estilo → pista flotante 5 s (cerrar tocando fuera) ───────────

  void _cerrarHintEstilo() {
    _hintTimer?.cancel();
    _hintTimer = null;
    if (_estiloHint == null) return;
    setState(() => _estiloHint = null);
  }

  void _mostrarDescripcionEstilo(_EstiloFlyer e) {
    _hintTimer?.cancel();
    setState(() {
      _estiloId = e.id;
      _estiloHint = e;
    });
    _hintTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      _cerrarHintEstilo();
    });
  }

  // ── Selector picker en chip inline ──────────────────────────────────────────

  Widget _chipSelector({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool compact = false,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 16, vertical: compact ? 7 : 11),
          decoration: BoxDecoration(
            color: ColoresLocales.cardAlt,
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: ColoresLocales.acentoVioleta.withOpacity(0.3), width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 14 : 17, color: ColoresLocales.acentoVioleta),
              SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.baloo2(
                  fontSize: compact ? 11 : 14,
                  fontWeight: FontWeight.w700,
                  color: ColoresLocales.textoOnFondoClaro,
                ),
              ),
              SizedBox(width: 6),
              Icon(CupertinoIcons.chevron_down, size: 13, color: ColoresLocales.acentoVioleta),
            ],
          ),
        ),
      );

  // ── Helpers para campos opcionales colapsables ──────────────────────────────

  Widget _extraDivider() => Divider(height: 1, thickness: 1, color: ColoresLocales.acentoVioleta.withOpacity(0.08));

  Widget _extraRow({
    required IconData icono,
    required String label,
    required bool activo,
    required VoidCallback onToggle,
    Widget? child,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(icono, size: 16, color: activo ? ColoresLocales.acentoVioleta : ColoresLocales.textoSecundarioOnFondoClaro),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.baloo2(
                      fontSize: 14,
                      fontWeight: activo ? FontWeight.w800 : FontWeight.w600,
                      color: activo ? ColoresLocales.acentoVioleta : ColoresLocales.textoOnFondoClaro,
                    ),
                  ),
                ),
                Icon(
                  activo ? CupertinoIcons.chevron_up : CupertinoIcons.plus,
                  size: 14,
                  color: activo ? ColoresLocales.acentoVioleta : ColoresLocales.textoSecundarioOnFondoClaro,
                ),
              ],
            ),
          ),
        ),
        ?child,
      ],
    );
  }

  Widget _extraField({
    required TextEditingController ctrl,
    required String hint,
    String? helper,
  }) =>
      Padding(
        padding: EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: TextField(
          controller: ctrl,
          maxLines: 2,
          onChanged: (_) => setState(() {}),
          style: GoogleFonts.baloo2(
            color: ColoresLocales.textoOnFondoClaro,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          decoration: _decMultilinea(hint, helper: helper).copyWith(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
      );

  // ── Generación real con Grok ─────────────────────────────────────────────────

  Future<void> _confirmarGeneracion() async {
    if (_generando) return;

    final eraReintento = _registroRetryId != null;
    final padreId = _registroRetryId; // ID del padre — fijo antes de limpiar estado
    final titulo = _tituloParaGeneracion();
    final snap = _capturarFormulario();

    setState(() {
      _generando = true;
      _errorGeneracion = null;
    });
    HapticFeedback.mediumImpact();

    // Mostrar pantalla de carga fullscreen
    if (!mounted) return;
    final completadoNotifier = ValueNotifier<bool>(false);
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      pageBuilder: (ctx, _, __) => _FlyerLoadingOverlay(
        esReintento: eraReintento,
        completado: completadoNotifier,
        onCancel: null,
      ),
    );

    try {
      final FlyerIaResultado resultado;
      if (snap.esLibre) {
        resultado = await FlyerIaService().generar(
          modo: 'libre',
          titulo: titulo,
          promptLibre: snap.promptLibre,
          generacionPadreId: eraReintento ? padreId : null,
        );
      } else {
        resultado = await FlyerIaService().generar(
          modo: 'estructurado',
          titulo: titulo,
          claim: snap.claim,
          diaSemana: _buildDiaSemanaString(),
          fecha: _buildFechaString(),
          hora: '${snap.hora.toString().padLeft(2, '0')}:${snap.minuto.toString().padLeft(2, '0')}',
          fondoDescripcion: snap.fondo,
          estiloId: snap.estiloId,
          estiloPropio: snap.mostrarPropio ? snap.textoPropio : null,
          generacionPadreId: eraReintento ? padreId : null,
          promos: snap.promos,
          lineup: snap.lineup,
          sponsors: snap.sponsors,
          dresscode: snap.dresscode,
        );
      }

      final h = LocalesFlyerIaHistorial.instance;

      if (eraReintento) {
        // Guardar las imágenes del RETRY en un subdirectorio separado
        // (no sobreescribir las originales — el usuario puede ver todas las 4)
        final cacheadaRetry = await FlyerCacheService().guardarGeneracion(
          id: '${padreId!}_retry',
          titulo: '$titulo (reintento)',
          estiloNombre: snap.estiloId,
          urls: resultado.urls,
          esRetry: true,
          retryUsado: false,
          createdAt: DateTime.now(),
          formulario: snap.toCacheFormulario(),
        );
        // Marcar el padre como retry-usado en caché
        await FlyerCacheService().marcarRetryUsado(padreId);
        // Agregar las imágenes del retry a la card del padre (sin reemplazar las originales)
        h.aplicarReintento(padreId, resultado.urls, cacheadaRetry.localPaths, snap);
        // Confirmar entrega del nuevo registro de retry en la edge
        FlyerIaService().confirmarEntrega(resultado.generacionId);
      } else {
        // Guardar imágenes originales en caché local
        final cacheada = await FlyerCacheService().guardarGeneracion(
          id: resultado.generacionId,
          titulo: titulo,
          estiloNombre: snap.estiloId,
          urls: resultado.urls,
          esRetry: false,
          retryUsado: false,
          createdAt: DateTime.now(),
          formulario: snap.toCacheFormulario(),
        );
        h.agregar(LocalesFlyerGeneracion(
          id: resultado.generacionId,
          titulo: titulo,
          urlsLocales: cacheada.localPaths,
          urlsRemotas: resultado.urls,
          creadoEn: DateTime.now(),
          esRetry: false,
          formularioAlGenerar: snap,
        ));
        FlyerIaService().confirmarEntrega(resultado.generacionId);
      }

      if (!mounted) return;

      // Señalizar al overlay que la respuesta llegó → barra acelera al 100%
      completadoNotifier.value = true;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // cierra overlay

      setState(() {
        _generando = false;
        _creditos = resultado.creditosRestantes;
        if (eraReintento) {
          _modoReintentoGratis = false;
          _tituloBloqueado = false;
          _registroRetryId = null;
        }
      });

      HapticFeedback.mediumImpact();

      if (eraReintento) {
        // Volver a la pantalla de resultados (ya estaba abierta, pop del formulario)
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => LocalesFlyerIaResultados(),
          ),
        );
      }
    } on FlyerIaException catch (e) {
      completadoNotifier.dispose();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // cierra overlay
      setState(() {
        _generando = false;
        _errorGeneracion = e.mensaje;
      });
    } catch (e) {
      completadoNotifier.dispose();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // cierra overlay
      setState(() {
        _generando = false;
        _errorGeneracion = 'Error inesperado. Intentá de nuevo.';
      });
    }
  }

  // ── AppBar ──────────────────────────────────────────────────────────────────

  PreferredSizeWidget _appBar() {
    final enSelector = _modoCreacion == null && widget.retry == null;
    final tituloBar = enSelector
        ? _kTituloAppBar
        : (_esModoLibre ? 'Descripción libre' : 'Estructura profesional');
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: ColoresLocales.superficie,
      centerTitle: true,
      leading: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () {
          if (_modoCreacion != null && widget.retry == null) {
            setState(() {
              _modoCreacion = null;
              _cerrarHintEstilo();
            });
          } else {
            Navigator.pop(context);
          }
        },
        child: Icon(CupertinoIcons.chevron_back, color: ColoresLocales.acentoVioleta),
      ),
      title: Text(
        tituloBar,
        style: GoogleFonts.baloo2(color: ColoresLocales.acentoVioleta, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _buildCuerpo() {
    if (widget.retry != null) {
      return _esModoLibre ? _buildFormularioLibre() : _buildFormulario();
    }
    if (_modoCreacion == null) return _buildSelectorModo();
    if (_modoCreacion == _FlyerModoCreacion.libre) return _buildFormularioLibre();
    return _buildFormulario();
  }

  Widget _buildSelectorModo() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '¿Cómo querés crear tu flyer?',
                style: GoogleFonts.baloo2(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: ColoresLocales.tituloAcento,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Elegí el flujo que mejor se adapte a tu idea.',
                style: GoogleFonts.baloo2(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: ColoresLocales.textoSecundarioOnFondoClaro,
                ),
              ),
              const SizedBox(height: 20),
              _cardModoFlyer(
                icon: CupertinoIcons.text_quote,
                titulo: 'Descripción libre',
                subtitulo:
                    'Describí libremente el contenido y estilo de tu flyer.',
                colorIcono: ColoresFeaturesLocales.flyersIa,
                onTap: () => setState(() => _modoCreacion = _FlyerModoCreacion.libre),
              ),
              const SizedBox(height: 14),
              _cardModoFlyer(
                icon: CupertinoIcons.rectangle_grid_2x2_fill,
                titulo: 'Estructura profesional',
                subtitulo:
                    'Usá templates para obtener resultados profesionales de manera más fácil.',
                chipNuevo: true,
                onTap: () => setState(() => _modoCreacion = _FlyerModoCreacion.estructurado),
              ),
              const SizedBox(height: 14),
              _cardModoFlyer(
                icon: CupertinoIcons.photo_on_rectangle,
                titulo: 'Ver mis flyers',
                subtitulo: _creditos == 1
                    ? 'Tenés $_creditos crédito de flyers IA. Revisá lo que ya generaste.'
                    : 'Tenés $_creditos créditos de flyers IA. Revisá lo que ya generaste.',
                colorIcono: ColoresFeaturesLocales.flyersIa,
                onTap: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(builder: (_) => const LocalesFlyerIaResultados()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardModoFlyer({
    required IconData icon,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
    Color? colorIcono,
    bool chipNuevo = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          decoration: ColoresLocales.decoracionCard(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: ColoresLocales.superficieElevada,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: ColoresLocales.bordeSuave),
                ),
                child: Icon(
                  icon,
                  size: 40,
                  color: colorIcono ?? ColoresLocales.acentoVioleta,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            titulo,
                            style: GoogleFonts.baloo2(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: ColoresLocales.tituloAcento,
                            ),
                          ),
                        ),
                        if (chipNuevo) const BadgeNuevoLocales(),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitulo,
                      style: GoogleFonts.baloo2(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: ColoresLocales.textoSecundarioOnFondoClaro,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Icon(
                  CupertinoIcons.chevron_right,
                  size: 18,
                  color: ColoresLocales.acentoVioleta.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBarraCreditosCompacta() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: ColoresFeaturesLocales.flyersIa.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ColoresFeaturesLocales.flyersIa.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.sparkles, size: 18, color: ColoresFeaturesLocales.flyersIa),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$_creditos créditos de flyers IA disponibles',
              style: GoogleFonts.baloo2(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: ColoresFeaturesLocales.flyersIa,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => LocalesFlyerIaResultados()),
              );
            },
            child: Text(
              'Ver mis flyers',
              style: GoogleFonts.baloo2(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: ColoresLocales.acentoVioleta,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormularioLibre() {
    final len = _ctrlPromptLibre.text.length;
    final hintIdx = len % _ideasPromptLibre.length;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildBarraCreditosCompacta(),
              const SizedBox(height: 16),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _seccionLabelIcono(
                      'Describí tu flyer',
                      CupertinoIcons.text_quote,
                    ),
                    Text(
                      'Incluí título, fecha, estilo visual, colores, promos y todo lo que quieras ver en el diseño (máx. $_kMaxPromptLibre caracteres).',
                      style: GoogleFonts.baloo2(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: ColoresLocales.textoSecundarioOnFondoClaro,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _ctrlPromptLibre,
                      maxLines: 12,
                      maxLength: _kMaxPromptLibre,
                      onChanged: (_) => setState(() {}),
                      style: GoogleFonts.baloo2(
                        color: ColoresLocales.textoOnFondoClaro,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      decoration: _decMultilinea(
                        _ideasPromptLibre[hintIdx],
                        helper: 'La IA generará 2 variantes en formato 9:16.',
                      ).copyWith(
                        counterStyle: GoogleFonts.baloo2(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: len > _kMaxPromptLibre
                              ? const Color(0xFFE53935)
                              : ColoresLocales.textoSecundarioOnFondoClaro,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (_errorGeneracion != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0F0),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFFCDD2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        CupertinoIcons.exclamationmark_circle,
                        color: Color(0xFFE53935),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorGeneracion!,
                          style: GoogleFonts.baloo2(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFE53935),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                height: 58,
                child: ElevatedButton(
                  onPressed: (_formularioCompleto && !_generando) ? _confirmarGeneracion : null,
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor:
                        _modoReintentoGratis ? ColoresFeaturesLocales.flyersIa : ColoresLocales.acentoVioleta,
                    foregroundColor: ColoresLocales.textoEnBoton,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _modoReintentoGratis ? 'Confirmar reintento gratis' : '¡Generar mi flyer!',
                        style: GoogleFonts.baloo2(fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: ColoresFeaturesLocales.flyersIa.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(
                            color: ColoresFeaturesLocales.flyersIa.withOpacity(0.5),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.sparkles,
                              size: 15,
                              color: ColoresLocales.textoEnBoton,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _modoReintentoGratis ? 'gratis' : '-1',
                              style: GoogleFonts.baloo2(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: ColoresLocales.textoEnBoton,
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
          ),
        ),
      ),
    );
  }

  // ── Formulario estructurado (templates) ─────────────────────────────────────

  Widget _buildFormulario() {
    final estiloActivo = _estilos.firstWhere((e) => e.id == _estiloId);

    return SingleChildScrollView(
      physics: BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(18, 10, 18, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Pill de créditos + acceso a resultados ──
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: ColoresFeaturesLocales.flyersIa.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: ColoresFeaturesLocales.flyersIa.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.sparkles, size: 15, color: ColoresFeaturesLocales.flyersIa),
                        SizedBox(width: 6),
                        Text(
                          '$_creditos crédito${_creditos != 1 ? 's' : ''} disponible${_creditos != 1 ? 's' : ''}',
                          style: GoogleFonts.baloo2(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: ColoresFeaturesLocales.flyersIa,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 38,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => LocalesFlyerIaResultados(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: ColoresLocales.acentoVioleta,
                        foregroundColor: ColoresLocales.textoEnBoton,
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50),
                        ),
                      ),
                      child: Text(
                        'Ver mis flyers',
                        style: GoogleFonts.baloo2(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 18),

              // ── Subtítulo ──
              Text(
                '¿Cómo querés que se vea tu flyer?',
                style: GoogleFonts.baloo2(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: ColoresLocales.textoOnFondoClaro,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Completá los datos del evento y elegí un estilo visual.',
                style: GoogleFonts.baloo2(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                  color: ColoresLocales.textoSecundarioOnFondoClaro,
                ),
              ),
              SizedBox(height: 20),

              // ── Card 1: Datos del evento ──
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _seccionLabelIcono('Datos del evento', CupertinoIcons.list_bullet),
                    TextField(
                      controller: _ctrlTitulo,
                      readOnly: _tituloBloqueado,
                      onChanged: (_) => setState(() {}),
                      onTap: _tituloBloqueado ? _avisarTituloNoEditable : null,
                      style: GoogleFonts.baloo2(
                        color: ColoresLocales.textoOnFondoClaro,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: _dec('Título del evento *').copyWith(
                        fillColor:
                            _tituloBloqueado ? ColoresLocales.cardAlt : ColoresLocales.chipInactivo,
                        filled: true,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(50),
                          borderSide: BorderSide(
                            color: _tituloBloqueado
                                ? Colors.red.shade400
                                : ColoresLocales.acentoVioleta.withOpacity(0.28),
                            width: _tituloBloqueado ? 1.8 : 1.5,
                          ),
                        ),
                      ),
                    ),
                    if (_tituloBloqueado) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              CupertinoIcons.lock_fill,
                              size: 17,
                              color: Colors.red.shade800,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'El título no se puede editar en un reintento gratis. El resto de los campos sí.',
                                style: GoogleFonts.baloo2(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.red.shade900,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: 12),
                    TextField(
                      controller: _ctrlClaim,
                      style: GoogleFonts.baloo2(
                        color: ColoresLocales.textoOnFondoClaro,
                        fontWeight: FontWeight.w600,
                      ),
                      onChanged: (_) => setState(() {}),
                      maxLines: 2,
                      decoration: _decMultilinea('Claims o promociones del evento *'),
                    ),
                    const SizedBox(height: 20),
                    _seccionLabelIcono('¿Cuándo arranca?', CupertinoIcons.calendar),
                    Row(
                      children: [
                        Expanded(
                          child: _chipSelector(
                            compact: true,
                            icon: CupertinoIcons.calendar,
                            label: _diaSemanaCorto(),
                            onTap: _pickDiaSemana,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: _chipSelector(
                            compact: true,
                            icon: CupertinoIcons.calendar_today,
                            label: '$_diaMes ${_mesCorto()}',
                            onTap: _pickFecha,
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: _chipSelector(
                            compact: true,
                            icon: CupertinoIcons.time,
                            label: '${_hora.toString().padLeft(2, '0')}:${_minuto.toString().padLeft(2, '0')}',
                            onTap: _pickHora,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 18),

              // ── Card 2: Estilo ──
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Prompt de fondo ──
                    _seccionLabelIcono('¿Qué querés en el fondo del flyer?', CupertinoIcons.photo),
                    TextField(
                      controller: _ctrlFondo,
                      focusNode: _focusFondo,
                      maxLines: 3,
                      onChanged: (_) => setState(() {}),
                      style: GoogleFonts.baloo2(
                        color: ColoresLocales.textoOnFondoClaro,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: _decMultilinea(
                        _ideasFondo[_hintFondoIndex],
                        helper: 'Cuanto más concreto, mejor resultado.',
                      ),
                    ),
                    SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _seccionLabelIcono('Elegí tu estilo', CupertinoIcons.sparkles),
                        ),
                        // Pill estilo seleccionado
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: ColoresLocales.acentoVioleta,
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: Text(
                            estiloActivo.nombre,
                            style: GoogleFonts.baloo2(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: ColoresLocales.textoEnBoton,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Tocá para seleccionar y ver la descripción.',
                      style: GoogleFonts.baloo2(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: ColoresLocales.textoSecundarioOnFondoClaro,
                      ),
                    ),
                    SizedBox(height: 10),
                    SizedBox(
                      height: 228,
                      child: GridView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: _estilos.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.60,
                      ),
                      itemBuilder: (context, i) {
                        final e = _estilos[i];
                        final active = _estiloId == e.id;
                        return GestureDetector(
                          onTap: () => _mostrarDescripcionEstilo(e),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: active ? ColoresLocales.acentoVioleta : Colors.black.withOpacity(0.08),
                                width: active ? 2.5 : 1,
                              ),
                              boxShadow: active
                                  ? [
                                      BoxShadow(
                                        color: ColoresLocales.acentoVioleta.withOpacity(0.3),
                                        blurRadius: 12,
                                        spreadRadius: 0,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        _previewEstiloFlyer(e),
                                        if (active)
                                          Positioned(
                                            top: 5,
                                            right: 5,
                                            child: Container(
                                              width: 22,
                                              height: 22,
                                              decoration: BoxDecoration(
                                                color: ColoresLocales.acentoVioleta,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                CupertinoIcons.check_mark,
                                                size: 13,
                                                color: ColoresLocales.superficie,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    color: active
                                        ? ColoresLocales.acentoVioleta.withOpacity(0.1)
                                        : ColoresLocales.superficieElevada,
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 6),
                                    child: Text(
                                      e.nombre,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.baloo2(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        color: active
                                            ? ColoresLocales.acentoVioleta
                                            : ColoresLocales.textoOnFondoClaro,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    ),
                    SizedBox(height: 18),

                    // ── Describir estilo propio (no compite con tarjetas) ──
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () =>
                            setState(() => _mostrarPropio = !_mostrarPropio),
                        style: TextButton.styleFrom(
                          foregroundColor: ColoresLocales.acentoVioleta,
                          padding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: Icon(
                          _mostrarPropio
                              ? CupertinoIcons.chevron_up
                              : CupertinoIcons.pencil,
                          size: 15,
                        ),
                        label: Text(
                          _mostrarPropio
                              ? 'Ocultar estilo propio'
                              : 'Describir uno propio',
                          style: GoogleFonts.baloo2(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: ColoresLocales.acentoVioleta,
                          ),
                        ),
                      ),
                    ),
                    if (_mostrarPropio) ...[
                      SizedBox(height: 10),
                      TextField(
                        controller: _ctrlPropio,
                        focusNode: _focusPropio,
                        maxLines: 3,
                        style: GoogleFonts.baloo2(
                          color: ColoresLocales.textoOnFondoClaro,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: _decMultilinea(
                          _ideasEstilo[_hintPropioIndex],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ── Card 3: Extras opcionales ──
              _card(
                padding: const EdgeInsets.all(4),
                child: Column(
                  children: [
                    // ── Segunda fecha ──
                    _extraRow(
                      icono: CupertinoIcons.calendar_badge_plus,
                      label: 'Agregar segunda fecha',
                      activo: _mostrarSegundaFecha,
                      onToggle: () => setState(() => _mostrarSegundaFecha = !_mostrarSegundaFecha),
                      child: _mostrarSegundaFecha
                          ? Padding(
                              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _chipSelector(
                                      compact: true,
                                      icon: CupertinoIcons.calendar,
                                      label: _diasSemana[_diaIdx2].substring(0, 3),
                                      onTap: () async {
                                        int temp = _diaIdx2;
                                        await showCupertinoModalPopup<void>(
                                          context: context,
                                          builder: (_) => _PickerSheet(
                                            title: 'Segundo día',
                                            child: CupertinoPicker(
                                              scrollController: FixedExtentScrollController(initialItem: temp),
                                              itemExtent: 44,
                                              onSelectedItemChanged: (i) => temp = i,
                                              children: _diasSemana.map((d) => Center(child: Text(d, style: GoogleFonts.baloo2(fontSize: 17, fontWeight: FontWeight.w700)))).toList(),
                                            ),
                                            onDone: () => setState(() => _diaIdx2 = temp),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: _chipSelector(
                                      compact: true,
                                      icon: CupertinoIcons.calendar_today,
                                      label: '$_diaMes2 ${_meses[_mesIdx2].substring(0, 3)}',
                                      onTap: () async {
                                        int tempD = _diaMes2;
                                        int tempM = _mesIdx2;
                                        await showCupertinoModalPopup<void>(
                                          context: context,
                                          builder: (_) => _PickerSheet(
                                            title: 'Segunda fecha',
                                            child: Row(children: [
                                              Expanded(child: CupertinoPicker(scrollController: FixedExtentScrollController(initialItem: tempD - 1), itemExtent: 44, onSelectedItemChanged: (i) => tempD = i + 1, children: List.generate(31, (i) => Center(child: Text('${i + 1}', style: GoogleFonts.baloo2(fontSize: 17, fontWeight: FontWeight.w700)))))),
                                              Expanded(flex: 2, child: CupertinoPicker(scrollController: FixedExtentScrollController(initialItem: tempM), itemExtent: 44, onSelectedItemChanged: (i) => tempM = i, children: _meses.map((m) => Center(child: Text(m, style: GoogleFonts.baloo2(fontSize: 17, fontWeight: FontWeight.w700)))).toList())),
                                            ]),
                                            onDone: () => setState(() { _diaMes2 = tempD; _mesIdx2 = tempM; }),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : null,
                    ),

                    _extraDivider(),

                    // ── Lineup / DJs ──
                    _extraRow(
                      icono: CupertinoIcons.music_mic,
                      label: 'Lineup / DJs o artistas',
                      activo: _mostrarLineup,
                      onToggle: () => setState(() => _mostrarLineup = !_mostrarLineup),
                      child: _mostrarLineup
                          ? _extraField(
                              ctrl: _ctrlLineup,
                              hint: 'Ej: DJ Memo • DJ Valentina • La K\'onga',
                              helper: 'Se verá resaltado en el flyer',
                            )
                          : null,
                    ),

                    _extraDivider(),

                    // ── Promos ──
                    _extraRow(
                      icono: CupertinoIcons.tag_fill,
                      label: 'Promociones',
                      activo: _mostrarPromos,
                      onToggle: () => setState(() => _mostrarPromos = !_mostrarPromos),
                      child: _mostrarPromos
                          ? _extraField(
                              ctrl: _ctrlPromos,
                              hint: 'Ej: Entrada libre hasta las 00hs • 2x1 en tragos',
                              helper: 'Aparecerá destacado en el footer del flyer',
                            )
                          : null,
                    ),

                    _extraDivider(),

                    // ── Sponsors ──
                    _extraRow(
                      icono: CupertinoIcons.star_fill,
                      label: 'Sponsors',
                      activo: _mostrarSponsors,
                      onToggle: () => setState(() => _mostrarSponsors = !_mostrarSponsors),
                      child: _mostrarSponsors
                          ? _extraField(
                              ctrl: _ctrlSponsors,
                              hint: 'Ej: Fernet Branca, Coca-Cola, Speed',
                              helper: 'La IA dibujará los logos en el footer',
                            )
                          : null,
                    ),

                    _extraDivider(),

                    // ── Dress code ──
                    _extraRow(
                      icono: CupertinoIcons.person_crop_circle_badge_checkmark,
                      label: 'Dress code',
                      activo: _mostrarDresscode,
                      onToggle: () => setState(() => _mostrarDresscode = !_mostrarDresscode),
                      child: _mostrarDresscode
                          ? _extraField(
                              ctrl: _ctrlDresscode,
                              hint: 'Ej: Smart Casual • No deportivo',
                              helper: 'Se incluirá en el diseño del flyer',
                            )
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Error de generación ──
              if (_errorGeneracion != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0F0),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFFCDD2)),
                  ),
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.exclamationmark_circle, color: Color(0xFFE53935), size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorGeneracion!,
                          style: GoogleFonts.baloo2(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFE53935),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // ── Botón generar ──
              SizedBox(
                height: 58,
                child: ElevatedButton(
                  onPressed: (_formularioCompleto && !_generando) ? _confirmarGeneracion : null,
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: _modoReintentoGratis ? ColoresFeaturesLocales.flyersIa : ColoresLocales.acentoVioleta,
                    foregroundColor: ColoresLocales.textoEnBoton,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50),
                    ),
                  ),
                  child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _modoReintentoGratis ? 'Confirmar reintento gratis' : '¡Generar mi flyer!',
                              style: GoogleFonts.baloo2(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(width: 12),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: ColoresFeaturesLocales.flyersIa.withOpacity(0.22),
                                borderRadius: BorderRadius.circular(50),
                                border: Border.all(color: ColoresFeaturesLocales.flyersIa.withOpacity(0.5), width: 1.2),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(CupertinoIcons.sparkles, size: 15, color: ColoresLocales.textoEnBoton),
                                  SizedBox(width: 4),
                                  Text(
                                    _modoReintentoGratis ? 'gratis' : '-1',
                                    style: GoogleFonts.baloo2(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      color: ColoresLocales.textoEnBoton,
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
          ),
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final hintTop = MediaQuery.of(context).padding.top + 52;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Scaffold(
          backgroundColor: ColoresLocales.fondoFormulario,
          appBar: _appBar(),
          body: _buildCuerpo(),
        ),
        if (_estiloHint != null && _modoCreacion == _FlyerModoCreacion.estructurado) ...[
          Positioned.fill(
            child: GestureDetector(
              onTap: _cerrarHintEstilo,
              behavior: HitTestBehavior.opaque,
              child: const _FlyerEstiloHintScrim(visible: true),
            ),
          ),
          Positioned(
            top: hintTop,
            left: 12,
            right: 12,
            child: GestureDetector(
              onTap: () {},
              behavior: HitTestBehavior.opaque,
              child: _FlyerEstiloHintPanel(
                key: ValueKey<String>(_estiloHint!.id),
                estilo: _estiloHint!,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Pista de estilo — flotante, no bloquea el scroll del formulario ──────────

class _FlyerEstiloHintScrim extends StatelessWidget {
  const _FlyerEstiloHintScrim({required this.visible});
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: visible ? 1 : 0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      builder: (context, t, _) => ColoredBox(
        color: Colors.black.withValues(alpha: 0.52 * t),
      ),
    );
  }
}

class _FlyerEstiloHintPanel extends StatelessWidget {
  const _FlyerEstiloHintPanel({super.key, required this.estilo});
  final _EstiloFlyer estilo;

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - t)),
            child: child,
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FlyerEstiloHintPill(estilo: estilo),
          const SizedBox(height: 14),
          _FlyerEstiloPreviewAmpliado(estilo: estilo),
        ],
      ),
    );
  }
}

class _FlyerEstiloHintPill extends StatelessWidget {
  const _FlyerEstiloHintPill({required this.estilo});
  final _EstiloFlyer estilo;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: ColoresLocales.superficie,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ColoresLocales.acentoVioleta.withOpacity(0.2), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: ColoresLocales.acentoVioleta.withOpacity(0.1),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                CupertinoIcons.sparkles,
                size: 15,
                color: ColoresLocales.acentoVioleta,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    estilo.nombre,
                    style: GoogleFonts.baloo2(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: ColoresLocales.acentoVioleta,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Text(
                        estilo.descripcion,
                        style: GoogleFonts.baloo2(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: ColoresLocales.textoSecundarioOnFondoClaro,
                          height: 1.4,
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

class _FlyerEstiloPreviewAmpliado extends StatelessWidget {
  const _FlyerEstiloPreviewAmpliado({required this.estilo});
  final _EstiloFlyer estilo;

  @override
  Widget build(BuildContext context) {
    final size = _tamanoPreviewEstiloAmpliado(context);
    return Center(
      child: Material(
        color: Colors.transparent,
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: size.width,
          height: size.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: ColoresLocales.superficie,
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: _EstiloFlyerPreviewImage(estilo: estilo),
          ),
        ),
      ),
    );
  }
}

// ─── Overlay fullscreen de carga ─────────────────────────────────────────────

class _FlyerLoadingOverlay extends StatefulWidget {
  const _FlyerLoadingOverlay({
    required this.esReintento,
    required this.completado,
    this.onCancel,
  });
  final bool esReintento;
  final ValueNotifier<bool> completado;
  final VoidCallback? onCancel;

  @override
  State<_FlyerLoadingOverlay> createState() => _FlyerLoadingOverlayState();
}

class _FlyerLoadingOverlayState extends State<_FlyerLoadingOverlay>
    with TickerProviderStateMixin {
  // Barra fase 1: 0 → 0.62 en 25 s (simulado, suave)
  late final AnimationController _barCtrl;
  late final Animation<double> _barAnim;

  // Barra fase 2: 0.62 → 1.0 en 0.5 s (cuando llega la respuesta)
  late final AnimationController _barFinCtrl;
  late final Animation<double> _barFinAnim;

  bool _completado = false;

  // Pulso del ícono de IA
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  // Carrusel de tips
  late final Timer _tipTimer;
  int _tipIdx = 0;

  static const List<String> _tips = [
    'Tenés 1 reintento gratis por generación si el resultado no te convence.',
    'Las imágenes se guardan en tu dispositivo para verlas sin internet.',
    'Usá una descripción de fondo creativa para mejores resultados.',
    'Podés descargar y compartir cada flyer desde la pantalla de resultados.',
    'El reintento gratis tiene una ventana de 10 minutos después de generar.',
    'Cada generación usa 1 crédito. Los reintentos son siempre gratis.',
  ];

  @override
  void initState() {
    super.initState();

    // Barra: 0 → 0.62 en 25 segundos con ease-out suave
    _barCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 25),
    );
    _barAnim = Tween<double>(begin: 0, end: 0.62).animate(
      CurvedAnimation(parent: _barCtrl, curve: Curves.easeOut),
    );
    _barCtrl.forward();

    // Pulso del ícono: scale 1.0 → 1.12 → 1.0, infinito
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Barra fase 2: 0.62 → 1.0 en 500 ms (se activa cuando completado llega)
    _barFinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _barFinAnim = Tween<double>(begin: 0.62, end: 1.0).animate(
      CurvedAnimation(parent: _barFinCtrl, curve: Curves.easeInOut),
    );

    // Escuchar al notifier del padre para disparar fase 2
    widget.completado.addListener(_onCompletado);

    // Rotar tips cada 4 segundos
    _tipTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(() => _tipIdx = (_tipIdx + 1) % _tips.length);
    });
  }

  void _onCompletado() {
    if (!widget.completado.value) return;
    _barCtrl.stop();
    _barFinCtrl.forward();
    if (mounted) setState(() => _completado = true);
  }

  @override
  void dispose() {
    widget.completado.removeListener(_onCompletado);
    _barCtrl.dispose();
    _barFinCtrl.dispose();
    _pulseCtrl.dispose();
    _tipTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return PopScope(
      canPop: false, // no se puede cerrar con back
      child: Material(
        color: ColoresLocales.acentoVioleta,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Ícono pulsante ──
                ScaleTransition(
                  scale: _pulseAnim,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CupertinoIcons.sparkles,
                      size: 40,
                      color: ColoresLocales.textoEnBoton,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // ── Título ──
                Text(
                  widget.esReintento
                      ? 'Regenerando tu flyer...'
                      : 'Estamos generando\ntu flyer con IA',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.baloo2(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: ColoresLocales.textoEnBoton,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),

                Text(
                  'Esto puede tardar entre 20 y 60 segundos',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.baloo2(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                  ),
                ),
                SizedBox(height: 40),

                // ── Barra de progreso iOS-style (dos fases) ──
                AnimatedBuilder(
                  animation: _completado ? _barFinAnim : _barAnim,
                  builder: (context, _) {
                    final progress = _completado ? _barFinAnim.value : _barAnim.value;
                    return Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: Container(
                            height: 6,
                            color: Colors.white.withOpacity(0.2),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: progress,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: ColoresLocales.textoEnBoton,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${(progress * 100).round()}%',
                          style: GoogleFonts.baloo2(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white60,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 40),

                // ── Carrusel de tips ──
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.15),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Container(
                    key: ValueKey<int>(_tipIdx),
                    padding: EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(CupertinoIcons.info_circle,
                              size: 16, color: Colors.white70),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _tips[_tipIdx],
                            style: GoogleFonts.baloo2(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: ColoresLocales.textoEnBoton,
                              height: 1.4,
                            ),
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

// ─── Bottom sheet picker genérico ────────────────────────────────────────────

class _PickerSheet extends StatelessWidget {
  const _PickerSheet({
    required this.title,
    required this.child,
    required this.onDone,
  });
  final String title;
  final Widget child;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    // Material evita el subrayado amarillo de debug en Text del título.
    // CupertinoTheme claro + pickerTextStyle oscuro = ruedas legibles.
    return Material(
      color: Colors.transparent,
      child: Container(
        height: 300,
        decoration: BoxDecoration(
          color: ColoresLocales.superficie,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 10, 8, 0),
              child: Row(
                children: [
                  Text(
                    title,
                    style: GoogleFonts.baloo2(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: ColoresLocales.textoOnFondoClaro,
                    ),
                  ),
                  Spacer(),
                  CupertinoButton(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    onPressed: () {
                      onDone();
                      Navigator.pop(context);
                    },
                    child: Text(
                      'Listo',
                      style: GoogleFonts.baloo2(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: ColoresLocales.acentoVioleta,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoTheme(
                data: const CupertinoThemeData(
                  brightness: Brightness.light,
                  textTheme: CupertinoTextThemeData(
                    pickerTextStyle: TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
