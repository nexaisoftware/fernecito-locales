library;

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import '../core/comprimir_imagen_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import '../core/crear_evento_desde_flyer_args.dart';
import '../core/tema_app_locales.dart';
import '../widgets/tema_locales_scope.dart';
import '../widgets/feedback_locales.dart';
import '../core/supabase_client.dart';
import '../core/servicio_edges_eventos.dart';
import '../core/navegacion_posicionamiento.dart';
import '../widgets/asistente_evento_sheet.dart';

enum _IntencionPublicacion { estandar, recFernecito, topCartelera, topUltra }

class LocalesCrearEvento extends StatefulWidget {
  const LocalesCrearEvento({super.key, this.datosFlyer});

  final CrearEventoDesdeFlyerArgs? datosFlyer;

  @override
  State<LocalesCrearEvento> createState() => _LocalesCrearEventoState();
}

class _LocalesCrearEventoState extends State<LocalesCrearEvento> {
  final ScrollController _scrollController = ScrollController();
  final _formPaso1Key = GlobalKey<FormState>();
  final _picker = ImagePicker();

  int _paso = 1;
  bool _cargandoPerfil = true;
  bool _guardando = false;

  String? _idLocal;
  bool _localVerificado = false;
  String? _nombreLocal;
  String? _ciudadLocal;
  bool _esOrganizadorEventos = false;

  final _tituloEventoCtrl = TextEditingController();
  final _descripcionEventoCtrl = TextEditingController();
  final _direccionEventoCtrl = TextEditingController();
  final _ciudadEventoCtrl = TextEditingController();
  final _provinciaEventoCtrl = TextEditingController();
  final _urlMapsEventoCtrl = TextEditingController();
  final _advertenciasCtrl = TextEditingController();
  final _edadMinimaCtrl = TextEditingController();
  final _cupoListaCtrl = TextEditingController();
  final _urlCompraEntradasCtrl = TextEditingController();

  Uint8List? _flyerBytes;
  Uint8List? _flyerBytesComprimidos;
  String _flyerExtension = 'webp';
  String? _flyerNombre;

  /// URL pública del flyer después de subir al bucket flyers_eventos.
  String? _urlFlyerSubido;
  bool _procesandoFlyer = false;
  String? _errorFlyer;

  String _tipoEvento = 'evento';
  DateTime? _fechaInicio;
  DateTime? _fechaFin;

  /// Modo de publicación:
  ///   'completo' = funcional (lista, cupos, promos, QR).
  ///   'simple'   = vidriera informativa (solo se muestra en cartelera).
  String _modoEvento = 'completo';
  bool get _esSimple => _modoEvento == 'simple';

  bool _esEnLocal = true;
  String _modoLista = 'auto';
  bool _permiteSquads = true;
  bool _limitarCupoLista = false;

  bool _agregarPromos = false;
  final List<_PromoDraft> _promos = [];
  bool _autocompletandoUbicacion = false;

  /// Secciones opcionales colapsadas en modo completo (paso 1).
  bool _expandUbicacionExterna = false;
  bool _expandVentaEntradas = false;
  bool _expandSistemaIngreso = false;
  bool _expandAdvertenciasExtras = false;

  static const List<String> _provinciasEvento = ['Córdoba'];
  static const List<String> _ciudadesCordobaEvento = [
    'Córdoba capital',
    'Alta Gracia',
    'Bell Ville',
    'Bialet Massé',
    'Capilla del Monte',
    'Colonia Caroya',
    'Cosquín',
    'Embalse',
    'Hernando',
    'Jesús María',
    'La Calera',
    'La Falda',
    'Malagueño',
    'Marcos Juárez',
    'Mendiolaza',
    'Mina Clavero',
    'Nono',
    'Río Ceballos',
    'Río Cuarto',
    'Río Tercero',
    'Saldán',
    'San Francisco',
    'Santa María de Punilla',
    'Unquillo',
    'Villa Allende',
    'Villa Carlos Paz',
    'Villa Cura Brochero',
    'Villa María',
    'Villa Nueva',
  ];

  /// Visibilidad elegida en paso 2 (la jerarquía premium se aplica luego vía créditos; el alta en DB va con jerarquía base).
  _IntencionPublicacion _intencionPublicacion = _IntencionPublicacion.estandar;

  /// Créditos reales desde perfiles_locales.
  int _credRecomendados = 0;
  int _credTop = 0;
  int _credTopUltra = 0;
  static const int _maxRecomendados = 16;
  static const int _maxTop = 6;
  static const int _maxTopUltra = 2;

  String? _idEventoPublicado;

  void _irAPaso(int paso) {
    setState(() => _paso = paso);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _cargarPerfilLocal();
    WidgetsBinding.instance.addPostFrameCallback((_) => _aplicarDatosFlyer());
  }

  Future<void> _aplicarDatosFlyer() async {
    final args = widget.datosFlyer;
    if (args == null || !mounted) return;

    _tituloEventoCtrl.text = args.tituloEvento;

    if (args.fechaInicio != null) {
      _fechaInicio = args.fechaInicio;
      _fechaFin =
          args.fechaFin ?? args.fechaInicio!.add(const Duration(hours: 5));
    }

    if (args.activarPromos &&
        args.nombrePromo != null &&
        args.nombrePromo!.trim().isNotEmpty) {
      _agregarPromos = true;
      if (_promos.isEmpty) _promos.add(_PromoDraft());
      final p = _promos.first;
      p.tituloCtrl.text = args.nombrePromo!.trim();
      p.inicioEsDelEvento = true;
      p.finEsDelEvento = true;
    }

    await _cargarFlyerDesdeArgs(args);
    if (mounted) setState(() {});
  }

  Future<void> _cargarFlyerDesdeArgs(CrearEventoDesdeFlyerArgs args) async {
    Uint8List? raw = args.flyerBytes;
    if (raw == null &&
        args.rutaFlyerLocal != null &&
        args.rutaFlyerLocal!.isNotEmpty) {
      final f = File(args.rutaFlyerLocal!);
      if (await f.exists()) raw = await f.readAsBytes();
    }
    if (raw == null &&
        args.urlFlyerRemota != null &&
        args.urlFlyerRemota!.trim().isNotEmpty) {
      try {
        final resp = await http
            .get(Uri.parse(args.urlFlyerRemota!.trim()))
            .timeout(const Duration(seconds: 30));
        if (resp.statusCode == 200) raw = resp.bodyBytes;
      } catch (_) {}
    }
    if (raw == null || !mounted) return;

    setState(() {
      _flyerBytes = raw;
      _flyerNombre =
          'flyer_ia.${args.rutaFlyerLocal?.split('.').last ?? 'jpg'}';
      _procesandoFlyer = true;
      _errorFlyer = null;
    });

    try {
      final (compressed, extension) = await _comprimirFlyer(raw);
      if (!mounted) return;
      setState(() {
        _flyerBytesComprimidos = compressed;
        _flyerExtension = extension;
        _procesandoFlyer = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _procesandoFlyer = false;
        _errorFlyer = 'No se pudo preparar el flyer desde IA.';
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tituloEventoCtrl.dispose();
    _descripcionEventoCtrl.dispose();
    _direccionEventoCtrl.dispose();
    _ciudadEventoCtrl.dispose();
    _provinciaEventoCtrl.dispose();
    _urlMapsEventoCtrl.dispose();
    _advertenciasCtrl.dispose();
    _edadMinimaCtrl.dispose();
    _cupoListaCtrl.dispose();
    _urlCompraEntradasCtrl.dispose();
    for (final promo in _promos) {
      promo.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarPerfilLocal() async {
    final uid = ServicioSupabase().usuarioActual?.id;
    if (uid == null) {
      if (mounted) setState(() => _cargandoPerfil = false);
      return;
    }
    try {
      Map<String, dynamic>? row;
      try {
        row = await ServicioSupabase().cliente
            .from('perfiles_locales')
            .select(
              'id, local_verificado, direccion, url_maps, nombre_local, ciudad, provincia, cupos_recomendado, cupos_top_cartelera, cupos_top_ultra, es_organizador_eventos',
            )
            .eq('id', uid)
            .maybeSingle();
      } catch (_) {
        row = await ServicioSupabase().cliente
            .from('perfiles_locales')
            .select(
              'id, local_verificado, direccion, url_maps, nombre_local, ciudad, provincia, cupos_recomendado, cupos_top_cartelera, cupos_top_ultra',
            )
            .eq('id', uid)
            .maybeSingle();
      }
      if (!mounted) return;
      final esOrg = row?['es_organizador_eventos'] == true;
      setState(() {
        _idLocal = uid;
        _localVerificado = row?['local_verificado'] as bool? ?? false;
        _nombreLocal = row?['nombre_local'] as String?;
        _ciudadLocal = row?['ciudad'] as String?;
        _esOrganizadorEventos = esOrg;
        _esEnLocal = !esOrg;
        if (esOrg) _expandUbicacionExterna = true;
        _credRecomendados = (row?['cupos_recomendado'] as num?)?.toInt() ?? 0;
        _credTop = (row?['cupos_top_cartelera'] as num?)?.toInt() ?? 0;
        _credTopUltra = (row?['cupos_top_ultra'] as num?)?.toInt() ?? 0;
        _intencionPublicacion = _IntencionPublicacion.estandar;
        _cargandoPerfil = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargandoPerfil = false);
    }
  }

  String _textoFecha(DateTime? d) {
    if (d == null) return 'Seleccionar fecha y hora';
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(d.day)}/${dos(d.month)}/${d.year} ${dos(d.hour)}:${dos(d.minute)}';
  }

  String _textoFechaPromoInicio(_PromoDraft p) {
    if (p.inicioEsDelEvento) {
      return _fechaInicio != null
          ? 'Igual al inicio del evento'
          : 'Se usará la fecha de inicio del evento';
    }
    return _textoFecha(p.fechaInicio);
  }

  String _textoFechaPromoFin(_PromoDraft p) {
    if (p.finEsDelEvento) {
      return _fechaFin != null
          ? 'Igual al fin del evento'
          : 'Se usará la fecha de fin del evento';
    }
    return _textoFecha(p.fechaFin);
  }

  Future<DateTime?> _seleccionarFechaHora(
    BuildContext context,
    DateTime? actual,
  ) async {
    final ahora = DateTime.now();
    final DateTime base = actual ?? ahora;
    final DateTime minDate = DateTime(ahora.year - 1);
    final DateTime maxDate = DateTime(ahora.year + 5, 12, 31, 23, 59);
    DateTime temporal = base.isBefore(minDate)
        ? minDate
        : (base.isAfter(maxDate) ? maxDate : base);

    final seleccion = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: ColoresLocales.superficie,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SizedBox(
              height: 320,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Localizations.override(
                        context: ctx,
                        locale: const Locale('es', 'AR'),
                        delegates: const [
                          GlobalCupertinoLocalizations.delegate,
                          GlobalWidgetsLocalizations.delegate,
                          GlobalMaterialLocalizations.delegate,
                        ],
                        child: CupertinoTheme(
                          data: CupertinoThemeData(
                            brightness: TemaAppLocales.instancia.esOscuro
                                ? Brightness.dark
                                : Brightness.light,
                          ),
                          child: CupertinoDatePicker(
                            mode: CupertinoDatePickerMode.dateAndTime,
                            use24hFormat: true,
                            initialDateTime: temporal,
                            minimumDate: minDate,
                            maximumDate: maxDate,
                            onDateTimeChanged: (value) {
                              setSheetState(() => temporal = value);
                            },
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: ColoresLocales.cardLavanda,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Text(
                          'Año: ${temporal.year}',
                          style: GoogleFonts.baloo2(
                            color: ColoresLocales.acentoVioleta,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text(
                            'Cancelar',
                            style: GoogleFonts.baloo2(
                              color: ColoresLocales.acentoVioleta,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: () => Navigator.of(ctx).pop(temporal),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ColoresLocales.acentoVioleta,
                            foregroundColor: ColoresLocales.textoEnBoton,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(50),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'Listo',
                            style: GoogleFonts.baloo2(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    return seleccion;
  }

  Future<(Uint8List, String)> _comprimirFlyer(Uint8List bytes) async {
    final r = await comprimirImagenStorage(
      bytes,
      perfil: PerfilImagenStorage.flyerEvento,
    );
    return (r.bytes, r.extension);
  }

  /// Sube el flyer al bucket flyers_eventos y retorna la URL pública.
  /// Ruta: <uid>/flyer_<timestamp>.webp
  Future<String> _subirFlyerABucket(Uint8List bytes, String extension) async {
    final uid = _idLocal ?? ServicioSupabase().usuarioActual?.id;
    if (uid == null) throw Exception('Sesión no encontrada');

    const bucket = 'flyers_eventos';
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = '$uid/flyer_$ts.$extension';

    await ServicioSupabase().cliente.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            // Evita requerir policy de UPDATE cuando solo queremos alta nueva.
            upsert: false,
            contentType: contentTypeDesdeExtension(extension),
          ),
        );
    return ServicioSupabase().cliente.storage.from(bucket).getPublicUrl(path);
  }

  Future<void> _seleccionarFlyer() async {
    if (_procesandoFlyer) return;
    try {
      final x = await _picker.pickImage(source: ImageSource.gallery);
      if (x == null) return;

      final rawBytes = await x.readAsBytes();
      if (!mounted) return;
      setState(() {
        _flyerBytes = rawBytes;
        _flyerNombre = x.name;
        _errorFlyer = null;
        _procesandoFlyer = true;
        _flyerBytesComprimidos = null;
        _urlFlyerSubido = null;
      });

      final (compressed, extension) = await _comprimirFlyer(rawBytes);

      if (!mounted) return;
      setState(() {
        _flyerBytesComprimidos = compressed;
        _flyerExtension = extension;
        _procesandoFlyer = false;
        _errorFlyer = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _procesandoFlyer = false;
        _errorFlyer = 'No se pudo procesar el flyer. Intentá de nuevo.';
      });
      _mostrarError('Error al procesar el flyer: $e', bloqueante: true);
    }
  }

  static const _flyerMiniW = 62.0;
  static const _flyerMiniH = 93.0;

  void _navegarGenerarFlyerIa() {
    Navigator.pushNamed(context, '/flyer_ia');
  }

  Widget _buildSubCardSubirFlyer() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: ColoresLocales.cardLavanda.withOpacity(0.45),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Subir flyer',
            style: GoogleFonts.baloo2(
              color: ColoresLocales.textoOnFondoClaro,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 40,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _buildColumnSubirDesdeGaleria(),
                  ),
                ),
                Expanded(
                  flex: 60,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: _buildPromoFlyerIa(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumnSubirDesdeGaleria() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Subir desde galería',
          style: GoogleFonts.baloo2(
            color: ColoresLocales.textoOnFondoClaro,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Align(alignment: Alignment.center, child: _buildMiniaturaFlyerSubir()),
        if (_errorFlyer != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorFlyer!,
            style: GoogleFonts.baloo2(
              color: Colors.red.shade700,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ] else if (_procesandoFlyer ||
            _flyerBytesComprimidos != null ||
            (_flyerNombre != null && _flyerNombre!.isNotEmpty)) ...[
          const SizedBox(height: 6),
          Text(
            _procesandoFlyer
                ? 'Procesando flyer...'
                : _flyerBytesComprimidos != null
                ? 'Flyer listo · tocá para reemplazar'
                : _flyerNombre!,
            style: GoogleFonts.baloo2(
              color: ColoresLocales.textoSecundarioOnFondoClaro,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMiniaturaFlyerSubir() {
    return GestureDetector(
      onTap: _procesandoFlyer ? null : _seleccionarFlyer,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: _flyerMiniW,
              height: _flyerMiniH,
              color: ColoresLocales.acentoVioleta.withOpacity(0.08),
              child: _flyerBytes != null
                  ? Image.memory(_flyerBytes!, fit: BoxFit.cover)
                  : _urlFlyerSubido != null
                  ? Image.network(_urlFlyerSubido!, fit: BoxFit.cover)
                  : Icon(
                      CupertinoIcons.plus,
                      size: 22,
                      color: ColoresLocales.acentoVioleta.withOpacity(0.75),
                    ),
            ),
            if (_procesandoFlyer)
              Container(
                width: _flyerMiniW,
                height: _flyerMiniH,
                color: Colors.black.withOpacity(0.45),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ColoresLocales.superficie,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromoFlyerIa() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '¿No tenés flyer? Hacé uno en minutos con la herramienta IA de Fernecito.',
          style: GoogleFonts.baloo2(
            color: ColoresLocales.textoSecundarioOnFondoClaro,
            fontSize: 11,
            height: 1.25,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 32,
          child: TextButton.icon(
            onPressed: _navegarGenerarFlyerIa,
            icon: const Icon(CupertinoIcons.wand_stars, size: 14),
            label: Text(
              'Generar flyer IA',
              style: GoogleFonts.baloo2(
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            style: TextButton.styleFrom(
              foregroundColor: ColoresLocales.acentoVioleta,
              backgroundColor: ColoresLocales.acentoVioleta.withValues(
                alpha: 0.1,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _agregarPromo() {
    setState(() => _promos.add(_PromoDraft()));
  }

  bool _validarPaso1() {
    final formState = _formPaso1Key.currentState;
    if (formState != null) {
      if (!formState.validate()) return false;
    } else {
      // En Paso 2 el Form de Paso 1 no está montado; validamos manualmente.
      if (_tituloEventoCtrl.text.trim().isEmpty) {
        _mostrarError('Completá el título del evento.');
        return false;
      }
      if (!_esSimple && _descripcionEventoCtrl.text.trim().isEmpty) {
        _mostrarError('Completá la descripción del evento.');
        return false;
      }
    }
    if (_flyerBytesComprimidos == null) {
      if (_procesandoFlyer) {
        _mostrarError('Esperá a que termine de procesarse el flyer.');
      } else if (_errorFlyer != null) {
        _mostrarError('Subí de nuevo el flyer. Hubo un error al procesarlo.');
      } else {
        _mostrarError('Subí el flyer del evento para continuar.');
      }
      return false;
    }
    if (!_esSimple) {
      if (_fechaInicio == null || _fechaFin == null) {
        _mostrarError('Seleccioná fecha y hora de inicio y fin.');
        return false;
      }
      if (!_fechaFin!.isAfter(_fechaInicio!)) {
        _mostrarError('La fecha de fin debe ser posterior al inicio.');
        return false;
      }
    }
    if (_esOrganizadorEventos || (!_esSimple && !_esEnLocal)) {
      if (_direccionEventoCtrl.text.trim().isEmpty) {
        _mostrarError('Completá la dirección del evento.');
        setState(() => _expandUbicacionExterna = true);
        return false;
      }
      if (_ciudadEventoCtrl.text.trim().isEmpty) {
        _mostrarError('Completá la ciudad del evento.');
        setState(() => _expandUbicacionExterna = true);
        return false;
      }
      if (_provinciaEventoCtrl.text.trim().isEmpty) {
        _mostrarError('Completá la provincia del evento.');
        setState(() => _expandUbicacionExterna = true);
        return false;
      }
      if (_urlMapsEventoCtrl.text.trim().isEmpty) {
        _mostrarError('Completá la URL de Google Maps del evento.');
        setState(() => _expandUbicacionExterna = true);
        return false;
      }
    }
    // Cupo es opcional (null = sin límite). Si se ingresa, debe ser >= 1.
    if (!_esSimple && _limitarCupoLista) {
      final cupo = int.tryParse(_cupoListaCtrl.text.trim());
      if (cupo == null || cupo <= 0) {
        _mostrarError('Si limitás el cupo, ingresá un número válido (>= 1).');
        setState(() => _expandSistemaIngreso = true);
        return false;
      }
    }
    return true;
  }

  bool _validarPromos() {
    if (!_agregarPromos) return true;
    if (_promos.isEmpty) {
      _mostrarError(
        'Agregá al menos una promo o desactivá la sección de promociones.',
      );
      return false;
    }
    for (var i = 0; i < _promos.length; i++) {
      final p = _promos[i];
      if (p.tituloCtrl.text.trim().isEmpty ||
          p.descripcionCtrl.text.trim().isEmpty) {
        _mostrarError('Completá título y descripción en la promo ${i + 1}.');
        return false;
      }
      final ini = p.inicioEfectivo(_fechaInicio);
      final fin = p.finEfectivo(_fechaFin);
      if (ini == null || fin == null) {
        _mostrarError(
          'Definí fechas del evento o personalizá las de la promo ${i + 1}.',
        );
        return false;
      }
      if (!fin.isAfter(ini)) {
        _mostrarError(
          'La fecha fin de la promo ${i + 1} debe ser posterior al inicio.',
        );
        return false;
      }
      if (p.limitarCantidad) {
        final cupos = int.tryParse(p.cuposCtrl.text.trim());
        if (cupos == null || cupos <= 0) {
          _mostrarError('Ingresá una cantidad válida en la promo ${i + 1}.');
          return false;
        }
      }
      if (p.modoUso == 'squad') {
        final min = int.tryParse(p.minMiembrosCtrl.text.trim());
        final max = int.tryParse(p.maxMiembrosCtrl.text.trim());
        if (min == null || max == null || min < 2 || max < min) {
          _mostrarError(
            'Completá mínimo/máximo de squad válidos en la promo ${i + 1} (mínimo 2).',
          );
          return false;
        }
      }
    }
    return true;
  }

  /// Mapea _IntencionPublicacion al string de jerarquía que espera subir_evento.
  /// La edge valida permisos y créditos server-side; aquí solo enviamos la intención.
  String get _jerarquiaPayload {
    switch (_intencionPublicacion) {
      case _IntencionPublicacion.recFernecito:
        return 'recomendado_fernecito';
      case _IntencionPublicacion.topCartelera:
        return 'top';
      case _IntencionPublicacion.topUltra:
        return 'top_ultra';
      case _IntencionPublicacion.estandar:
        // local_verificado → normal; sin verificar → gratis (edge lo fuerza igual)
        return _localVerificado ? 'normal' : 'gratis';
    }
  }

  String _diaSemana(DateTime d) {
    // Día calendario en Argentina (UTC-3 fijo). Evita que un sábado 23:00 AR
    // (domingo 02:00 UTC) se guarde como "domingo".
    final ar = d.toUtc().subtract(const Duration(hours: 3));
    const dias = [
      'lunes',
      'martes',
      'miercoles',
      'jueves',
      'viernes',
      'sabado',
      'domingo',
    ];
    return dias[ar.weekday - 1]; // weekday: 1=lunes ... 7=domingo
  }

  Map<String, dynamic> _buildPayloadEvento() {
    // Cupo: null si no se quiere limitar, entero positivo si se limitó.
    final cupoLista = _limitarCupoLista
        ? int.tryParse(_cupoListaCtrl.text.trim())
        : null;
    final edad = _edadMinimaCtrl.text.trim().isEmpty
        ? null
        : int.tryParse(_edadMinimaCtrl.text.trim());
    final urlCompra = _urlCompraEntradasCtrl.text.trim();
    final descripcion = _descripcionEventoCtrl.text.trim();

    return {
      // --- Modo del evento (la edge neutraliza los campos funcionales si simple) ---
      'modo_evento': _modoEvento,
      // --- Datos básicos ---
      'titulo_evento': _tituloEventoCtrl.text.trim(),
      'descripcion_evento': _esSimple
          ? null
          : (descripcion.isEmpty ? null : descripcion),
      'url_flyer': _urlFlyerSubido ?? '',
      // Campos funcionales: en modo simple se mandan neutralizados.
      'url_compra_entradas': _esSimple
          ? null
          : (urlCompra.isEmpty ? null : urlCompra),
      'tipo_evento': _tipoEvento,
      'edad_minima': _esSimple ? null : edad,
      if (!_esSimple) ...{
        'fecha_inicio': _fechaInicio!.toUtc().toIso8601String(),
        'fecha_fin': _fechaFin!.toUtc().toIso8601String(),
        'dia_semana': _diaSemana(_fechaInicio!),
      },
      // --- Lista (irrelevante en modo simple, la edge la fuerza a 'auto') ---
      'modo_lista': _esSimple ? 'auto' : _modoLista,
      'cupo_lista_max': _esSimple ? null : cupoLista, // null = sin límite
      'permite_squads': _esSimple ? false : _permiteSquads,
      // --- Ubicación: organizador nunca "en mi local"; simple de local sí. ---
      'es_en_local': _esOrganizadorEventos
          ? false
          : (_esSimple ? true : _esEnLocal),
      if (!_esEnLocal) 'direccion_evento': _direccionEventoCtrl.text.trim(),
      'ciudad_evento': _esEnLocal ? null : _ciudadEventoCtrl.text.trim(),
      'provincia_evento': _esEnLocal ? null : _provinciaEventoCtrl.text.trim(),
      if (!_esEnLocal) 'url_maps_evento': _urlMapsEventoCtrl.text.trim(),
      // --- Advertencias ---
      if (!_esSimple && _advertenciasCtrl.text.trim().isNotEmpty)
        'advertencias_evento': _advertenciasCtrl.text.trim(),
      // --- Jerarquía (la edge valida permisos/créditos server-side) ---
      'jerarquia': _jerarquiaPayload,
      // --- Promos ---
      'tiene_promo': !_esSimple && _agregarPromos && _promos.isNotEmpty,
    };
  }

  List<Map<String, dynamic>> _buildPayloadPromos(String idEvento) {
    if (_esSimple || !_agregarPromos) return [];
    return _promos.map((p) {
      final cuposTotales = p.limitarCantidad
          ? int.tryParse(p.cuposCtrl.text.trim())
          : null;
      final minMiembros = p.modoUso == 'squad'
          ? int.tryParse(p.minMiembrosCtrl.text.trim())
          : null;
      final maxMiembros = p.modoUso == 'squad'
          ? int.tryParse(p.maxMiembrosCtrl.text.trim())
          : null;
      final ini = p.inicioEfectivo(_fechaInicio)!;
      final fin = p.finEfectivo(_fechaFin)!;
      return {
        'titulo_promocion': p.tituloCtrl.text.trim(),
        'descripcion_promocion': p.descripcionCtrl.text.trim(),
        'fecha_inicio': ini.toUtc().toIso8601String(),
        'fecha_fin': fin.toUtc().toIso8601String(),
        'cupos_totales': cuposTotales,
        'modo_uso': p.modoUso,
        'min_miembros_squad': minMiembros,
        'max_miembros_squad': maxMiembros,
      };
    }).toList();
  }

  Future<void> _publicarEvento() async {
    if (_guardando) return;
    if (!_validarPaso1() || !_validarPromos()) return;
    if (_idLocal == null) {
      _mostrarError('No encontramos tu sesión. Volvé a iniciar sesión.');
      return;
    }
    if (_flyerBytesComprimidos == null) {
      _mostrarError('Primero seleccioná un flyer válido.');
      return;
    }
    setState(() => _guardando = true);
    try {
      final urlFlyer = await _subirFlyerABucket(
        _flyerBytesComprimidos!,
        _flyerExtension,
      );
      _urlFlyerSubido = urlFlyer;
      final payloadEvento = _buildPayloadEvento();
      final payloadPromos = _buildPayloadPromos('');
      final idEvento = await ServicioEdgesEventos().subirEvento(
        payloadEvento: payloadEvento,
        promociones: payloadPromos,
      );

      // TODO: Lógica final de publicación (ej. caché, indexación, métricas).
      if (!mounted) return;
      setState(() {
        _idEventoPublicado = idEvento;
        _paso = 3;
      });
    } catch (e) {
      if (mounted) {
        _mostrarError('No se pudo publicar el evento: $e', bloqueante: true);
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// Publica el evento con los datos del asistente IA.
  /// NO muta el estado del form (si falla, el formulario detrás queda intacto).
  /// Comprime el flyer y sube por el mismo camino que el form → `subir_evento`.
  Future<({String? error, String? idEvento})> _publicarDesdeAsistente(
    DatosEventoChat d,
  ) async {
    ({String? error, String? idEvento}) fail(String msg) =>
        (error: msg, idEvento: null);

    final uid = _idLocal ?? ServicioSupabase().usuarioActual?.id;
    if (uid == null) {
      return fail('No encontramos tu sesión. Volvé a iniciar sesión.');
    }
    if (d.flyerBytes == null) return fail('Falta el flyer del evento.');
    if (d.titulo.trim().isEmpty) return fail('Completá el título del evento.');
    if ((d.descripcion ?? '').trim().isEmpty) {
      return fail('Completá la descripción del evento.');
    }
    if (d.fechaInicio == null || d.fechaFin == null) {
      return fail('Faltan las fechas del evento.');
    }
    if (!d.fechaFin!.isAfter(d.fechaInicio!)) {
      return fail('La fecha de fin debe ser posterior al inicio.');
    }
    if (!d.esEnLocal) {
      if ((d.direccion ?? '').trim().isEmpty) {
        return fail('Completá la dirección del evento.');
      }
      if ((d.ciudad ?? '').trim().isEmpty) {
        return fail('Completá la ciudad del evento.');
      }
      if ((d.provincia ?? '').trim().isEmpty) {
        return fail('Completá la provincia del evento.');
      }
      if ((d.urlMaps ?? '').trim().isEmpty) {
        return fail('Completá la URL de Google Maps del evento.');
      }
    }
    if (d.cupoListaMax != null && d.cupoListaMax! <= 0) {
      return fail('Si limitás el cupo, ingresá un número válido (>= 1).');
    }
    final conPromos = d.agregarPromos && d.promos.isNotEmpty;
    if (d.agregarPromos && d.promos.isEmpty) {
      return fail('Agregá al menos una promo o salteá esa sección.');
    }
    if (conPromos) {
      for (var i = 0; i < d.promos.length; i++) {
        final p = d.promos[i];
        if (p.titulo.trim().isEmpty || p.descripcion.trim().isEmpty) {
          return fail('Completá título y descripción en la promo ${i + 1}.');
        }
        if (p.cuposTotales != null && p.cuposTotales! <= 0) {
          return fail('Ingresá una cantidad válida en la promo ${i + 1}.');
        }
        if (p.modoUso == 'squad') {
          final min = p.minSquad;
          final max = p.maxSquad;
          if (min == null || max == null || min < 2 || max < min) {
            return fail(
              'Completá mínimo/máximo de squad válidos en la promo ${i + 1} (mínimo 2).',
            );
          }
        }
      }
    }

    try {
      // Misma optimización/compresión que el form tradicional.
      final (compressed, extension) = await _comprimirFlyer(d.flyerBytes!);
      final urlFlyer = await _subirFlyerABucket(compressed, extension);

      final jerarquia = _localVerificado ? 'normal' : 'gratis';
      final edad = d.edadMinima;
      final urlCompra = (d.urlCompraEntradas ?? '').trim();
      final advertencias = (d.advertencias ?? '').trim();

      final payloadEvento = <String, dynamic>{
        'modo_evento': 'completo',
        'titulo_evento': d.titulo.trim(),
        'descripcion_evento': d.descripcion!.trim(),
        'url_flyer': urlFlyer,
        'url_compra_entradas': urlCompra.isEmpty ? null : urlCompra,
        'tipo_evento': d.tipo,
        'edad_minima': edad,
        'fecha_inicio': d.fechaInicio!.toUtc().toIso8601String(),
        'fecha_fin': d.fechaFin!.toUtc().toIso8601String(),
        'dia_semana': _diaSemana(d.fechaInicio!),
        'modo_lista': d.modoLista == 'manual' ? 'manual' : 'auto',
        'cupo_lista_max': d.cupoListaMax,
        'permite_squads': d.permiteSquads,
        'es_en_local': d.esEnLocal,
        if (!d.esEnLocal) 'direccion_evento': d.direccion!.trim(),
        'ciudad_evento': d.esEnLocal ? null : d.ciudad!.trim(),
        'provincia_evento': d.esEnLocal ? null : d.provincia!.trim(),
        if (!d.esEnLocal) 'url_maps_evento': d.urlMaps!.trim(),
        if (advertencias.isNotEmpty) 'advertencias_evento': advertencias,
        'jerarquia': jerarquia,
        'tiene_promo': conPromos,
      };

      final payloadPromos = conPromos
          ? d.promos.map((p) {
              return <String, dynamic>{
                'titulo_promocion': p.titulo.trim(),
                'descripcion_promocion': p.descripcion.trim(),
                'fecha_inicio': d.fechaInicio!.toUtc().toIso8601String(),
                'fecha_fin': d.fechaFin!.toUtc().toIso8601String(),
                'cupos_totales': p.cuposTotales,
                'modo_uso': p.modoUso,
                'min_miembros_squad':
                    p.modoUso == 'squad' ? p.minSquad : null,
                'max_miembros_squad':
                    p.modoUso == 'squad' ? p.maxSquad : null,
              };
            }).toList()
          : <Map<String, dynamic>>[];

      final idEvento = await ServicioEdgesEventos().subirEvento(
        payloadEvento: payloadEvento,
        promociones: payloadPromos,
      );
      return (error: null, idEvento: idEvento);
    } catch (e) {
      return fail('No se pudo publicar el evento: $e');
    }
  }

  /// Abre el asistente IA (chatbot) para crear el evento. Solo en modo completo.
  Future<void> _abrirAsistenteEvento() async {
    if (_guardando || _cargandoPerfil) return;
    await mostrarAsistenteEventoSheet(
      context,
      ciudadLocal: _ciudadLocal,
      esOrganizador: _esOrganizadorEventos,
      flyerInicial: _flyerBytes ?? _flyerBytesComprimidos,
      onPublicar: (d) => _publicarDesdeAsistente(d),
      onIrHome: () =>
          Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false),
      onSubirJerarquia: (idEvento) {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false);
        Future.delayed(const Duration(milliseconds: 80), () {
          NavegacionPosicionamiento.irAEvento(idEvento ?? '');
        });
      },
    );
  }

  void _mostrarError(String mensaje, {bool bloqueante = false}) {
    final esErrorRed =
        bloqueante ||
        mensaje.startsWith('No se pudo') ||
        mensaje.startsWith('Error al');
    if (!esErrorRed) {
      HapticFeedback.lightImpact();
      FeedbackLocales.mostrarAdvertencia(context, mensaje, conNavBar: false);
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ColoresLocales.superficie,
        title: Text(
          'Atención',
          style: GoogleFonts.baloo2(
            color: ColoresLocales.textoOnFondoClaro,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          mensaje,
          style: GoogleFonts.baloo2(
            color: ColoresLocales.textoSecundarioOnFondoClaro,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'OK',
              style: GoogleFonts.baloo2(
                color: ColoresLocales.acentoVioleta,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _mensajeVisibilidadExito {
    switch (_intencionPublicacion) {
      case _IntencionPublicacion.estandar:
        return _localVerificado
            ? 'Visibilidad: Zona Normal (cartelera estándar para locales verificados).'
            : 'Visibilidad: Zona Gratis. Verificá tu cuenta para mayor alcance.';
      case _IntencionPublicacion.recFernecito:
        return 'Visibilidad: Recomendado Fernecito ✨ Usaste 1 crédito. Tu evento aparece destacado en la sección de recomendados.';
      case _IntencionPublicacion.topCartelera:
        return 'Visibilidad: Top Cartelera ⭐ Usaste 1 crédito. Máxima visibilidad en el carousel principal.';
      case _IntencionPublicacion.topUltra:
        return 'Visibilidad: Top Ultra 🔥 Usaste 1 crédito. Tu evento aparece en las stories que se abren al entrar a la app.';
    }
  }

  Future<void> _publicarEnJerarquia(_IntencionPublicacion intencion) async {
    if (_guardando) return;

    // Premium: solo exige créditos (no verificación).
    if (intencion == _IntencionPublicacion.recFernecito &&
        _credRecomendados <= 0) {
      return;
    }
    if (intencion == _IntencionPublicacion.topCartelera && _credTop <= 0) {
      return;
    }
    if (intencion == _IntencionPublicacion.topUltra && _credTopUltra <= 0) {
      return;
    }

    setState(() => _intencionPublicacion = intencion);
    await _publicarEvento();
  }

  void _mostrarModalJerarquias() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ColoresLocales.superficie,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ColoresLocales.separador,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Niveles de visibilidad',
                  style: GoogleFonts.baloo2(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: ColoresLocales.textoOnFondoClaro,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Elegí dónde querés que aparezca tu evento en la cartelera de usuarios.',
                  style: GoogleFonts.baloo2(
                    fontSize: 13,
                    height: 1.4,
                    color: ColoresLocales.textoSecundarioOnFondoClaro,
                  ),
                ),
                const SizedBox(height: 18),
                _filaJerarquiaInfo(
                  icono: CupertinoIcons.square_grid_2x2,
                  color: ColoresLocales.acentoVioletaMarca,
                  titulo: 'Estándar',
                  subtitulo: _localVerificado ? 'Zona normal' : 'Zona gratis',
                  descripcion: _localVerificado
                      ? 'Tu evento entra a la cartelera de tu ciudad con la visibilidad incluida en tu plan verificado.'
                      : 'Tu evento aparece en la cartelera con visibilidad básica. Verificá tu cuenta para más alcance.',
                  costo: 'Gratis',
                ),
                _filaJerarquiaInfo(
                  icono: IconosFeaturesLocales.recomendadoFernecito,
                  color: ColoresFeaturesLocales.recomendadoFernecito,
                  titulo: 'Recomendado Fernecito',
                  subtitulo: 'Destacado en recomendados',
                  descripcion:
                      'Aparece en la sección de recomendados, con mayor exposición frente a usuarios afines a tu propuesta. El boost dura hasta 15 días o hasta que venza el evento.',
                  costo: '1 crédito · te quedan $_credRecomendados',
                ),
                _filaJerarquiaInfo(
                  icono: IconosFeaturesLocales.topCartelera,
                  color: ColoresFeaturesLocales.topCartelera,
                  titulo: 'Top Cartelera',
                  subtitulo: 'Carousel principal',
                  descripcion:
                      'Máxima visibilidad en el carrusel principal de la cartelera. Ideal para fechas clave o lanzamientos. Boost de hasta 10 días.',
                  costo: '1 crédito · te quedan $_credTop',
                ),
                _filaJerarquiaInfo(
                  icono: IconosFeaturesLocales.topUltra,
                  color: ColoresFeaturesLocales.topUltra,
                  titulo: 'Top Ultra',
                  subtitulo: 'Stories al abrir la app',
                  descripcion:
                      'Tu evento se muestra en las stories fullscreen que ven los usuarios al entrar. El impacto visual más alto de la plataforma.',
                  costo: '1 crédito · te quedan $_credTopUltra',
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      foregroundColor: ColoresLocales.acentoVioletaMarca,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Entendido',
                      style: GoogleFonts.baloo2(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _filaJerarquiaInfo({
    required IconData icono,
    required Color color,
    required String titulo,
    required String subtitulo,
    required String descripcion,
    required String costo,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            child: Icon(icono, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
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
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  descripcion,
                  style: GoogleFonts.baloo2(
                    fontSize: 12.5,
                    height: 1.35,
                    color: ColoresLocales.textoSecundarioOnFondoClaro,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  costo,
                  style: GoogleFonts.baloo2(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: ColoresLocales.textoSecundarioOnFondoClaro,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoCreditoCrear({
    required IconData icono,
    required Color color,
    required String titulo,
    required int valor,
    required int maximo,
    required String descripcion,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: Icon(icono, color: color, size: 32),
              ),
              SizedBox(height: 14),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: GoogleFonts.baloo2(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: ColoresLocales.textoOnFondoClaro,
                ),
              ),
              SizedBox(height: 8),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '$valor',
                      style: GoogleFonts.baloo2(
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                    TextSpan(
                      text: ' / $maximo',
                      style: GoogleFonts.baloo2(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: color.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'cupos disponibles este mes',
                style: GoogleFonts.baloo2(
                  fontSize: 12,
                  color: ColoresLocales.textoSecundarioOnFondoClaro,
                ),
              ),
              SizedBox(height: 14),
              Text(
                descripcion,
                textAlign: TextAlign.center,
                style: GoogleFonts.baloo2(
                  fontSize: 13,
                  color: ColoresLocales.textoSecundarioOnFondoClaro,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: TextButton.styleFrom(
                    backgroundColor: color.withOpacity(0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50),
                    ),
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    'Entendido',
                    style: GoogleFonts.baloo2(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPanelCuentaCreditosCrear() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: ColoresLocales.decoracionCard(sinBorde: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Créditos disponibles',
            style: GoogleFonts.baloo2(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ColoresLocales.textoSecundarioOnFondoClaro,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pillCreditoResumen(
                icono: IconosFeaturesLocales.recomendadoFernecito,
                label: 'Rec.',
                valor: _credRecomendados,
                color: ColoresFeaturesLocales.recomendadoFernecito,
                onTap: () => _mostrarDialogoCreditoCrear(
                  icono: IconosFeaturesLocales.recomendadoFernecito,
                  color: ColoresFeaturesLocales.recomendadoFernecito,
                  titulo: 'Recomendado Fernecito',
                  valor: _credRecomendados,
                  maximo: _maxRecomendados,
                  descripcion:
                      'Destacá tu evento en la sección de recomendados de la cartelera.',
                ),
              ),
              _pillCreditoResumen(
                icono: IconosFeaturesLocales.topCartelera,
                label: 'Top',
                valor: _credTop,
                color: ColoresFeaturesLocales.topCartelera,
                onTap: () => _mostrarDialogoCreditoCrear(
                  icono: IconosFeaturesLocales.topCartelera,
                  color: ColoresFeaturesLocales.topCartelera,
                  titulo: 'Top Cartelera',
                  valor: _credTop,
                  maximo: _maxTop,
                  descripcion:
                      'Posicioná tu evento en el carrusel principal de la cartelera.',
                ),
              ),
              _pillCreditoResumen(
                icono: IconosFeaturesLocales.topUltra,
                label: 'Ultra',
                valor: _credTopUltra,
                color: ColoresFeaturesLocales.topUltra,
                onTap: () => _mostrarDialogoCreditoCrear(
                  icono: IconosFeaturesLocales.topUltra,
                  color: ColoresFeaturesLocales.topUltra,
                  titulo: 'Top Ultra',
                  valor: _credTopUltra,
                  maximo: _maxTopUltra,
                  descripcion:
                      'Stories fullscreen al abrir la app. Máximo impacto visual.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pillCreditoResumen({
    required IconData icono,
    required String label,
    required int valor,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: ColoresLocales.superficie,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.baloo2(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ColoresLocales.textoSecundarioOnFondoClaro,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$valor',
                style: GoogleFonts.baloo2(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: ColoresLocales.textoOnFondoClaro,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _encabezadoPublicarEn() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Publicar en',
            style: GoogleFonts.baloo2(
              color: ColoresLocales.textoOnFondoClaro,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ),
        Material(
          color: ColoresLocales.superficieElevada,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: _mostrarModalJerarquias,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                CupertinoIcons.info_circle,
                size: 20,
                color: ColoresLocales.acentoVioletaMarca,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _botonPublicarEn({
    required _IntencionPublicacion intencion,
    required IconData icono,
    required Color color,
    required String nombreNivel,
    required String detalleCosto,
    required bool habilitado,
    String? motivoDeshabilitado,
    bool filled = false,
  }) {
    final publicando = _guardando && _intencionPublicacion == intencion;
    final onTap = habilitado && !_guardando
        ? () => _publicarEnJerarquia(intencion)
        : null;

    final child = Row(
      children: [
        SizedBox(
          width: 36,
          height: 36,
          child: publicando
              ? Padding(
                  padding: const EdgeInsets.all(9),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: filled ? ColoresLocales.textoEnBoton : color,
                  ),
                )
              : Icon(
                  icono,
                  size: 22,
                  color: filled
                      ? ColoresLocales.textoEnBoton
                      : (habilitado
                            ? color
                            : ColoresLocales.textoSecundarioOnFondoClaro),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Publicar en $nombreNivel',
                style: GoogleFonts.baloo2(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: filled
                      ? ColoresLocales.textoEnBoton
                      : (habilitado
                            ? ColoresLocales.textoOnFondoClaro
                            : ColoresLocales.textoSecundarioOnFondoClaro),
                ),
              ),
              Text(
                motivoDeshabilitado ?? detalleCosto,
                style: GoogleFonts.baloo2(
                  fontSize: 12,
                  height: 1.2,
                  color: filled
                      ? ColoresLocales.textoEnBoton.withValues(alpha: 0.85)
                      : ColoresLocales.textoSecundarioOnFondoClaro,
                ),
              ),
            ],
          ),
        ),
        if (!publicando)
          Icon(
            CupertinoIcons.arrow_up_circle_fill,
            size: 22,
            color: filled
                ? ColoresLocales.textoEnBoton.withValues(alpha: 0.9)
                : (habilitado
                      ? color
                      : ColoresLocales.textoSecundarioOnFondoClaro.withValues(
                          alpha: 0.5,
                        )),
          ),
      ],
    );

    if (filled && habilitado) {
      return Opacity(
        opacity: habilitado ? 1 : 0.42,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color, color.withValues(alpha: 0.82)],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                child: child,
              ),
            ),
          ),
        ),
      );
    }

    return Opacity(
      opacity: habilitado ? 1 : 0.42,
      child: Material(
        color: ColoresLocales.superficie,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: habilitado
                  ? color.withValues(alpha: 0.08)
                  : ColoresLocales.superficieElevada,
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildBotonesPublicarEn() {
    final estandarDetalle = _localVerificado
        ? 'Gratis · incluido en tu plan'
        : 'Gratis';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _botonPublicarEn(
          intencion: _IntencionPublicacion.estandar,
          icono: CupertinoIcons.square_grid_2x2,
          color: ColoresLocales.acentoVioletaMarca,
          nombreNivel: _localVerificado ? 'Estándar' : 'Estándar (Gratis)',
          detalleCosto: estandarDetalle,
          habilitado: true,
        ),
        const SizedBox(height: 10),
        _botonPublicarEn(
          intencion: _IntencionPublicacion.recFernecito,
          icono: IconosFeaturesLocales.recomendadoFernecito,
          color: ColoresFeaturesLocales.recomendadoFernecito,
          nombreNivel: 'Recomendado Fernecito',
          detalleCosto: '1 crédito · te quedan $_credRecomendados',
          habilitado: _credRecomendados > 0,
          motivoDeshabilitado:
              _credRecomendados <= 0 ? 'Sin créditos disponibles' : null,
          filled: true,
        ),
        const SizedBox(height: 10),
        _botonPublicarEn(
          intencion: _IntencionPublicacion.topCartelera,
          icono: IconosFeaturesLocales.topCartelera,
          color: ColoresFeaturesLocales.topCartelera,
          nombreNivel: 'Top Cartelera',
          detalleCosto: '1 crédito · te quedan $_credTop',
          habilitado: _credTop > 0,
          motivoDeshabilitado: _credTop <= 0 ? 'Sin créditos disponibles' : null,
          filled: true,
        ),
        const SizedBox(height: 10),
        _botonPublicarEn(
          intencion: _IntencionPublicacion.topUltra,
          icono: IconosFeaturesLocales.topUltra,
          color: ColoresFeaturesLocales.topUltra,
          nombreNivel: 'Top Ultra',
          detalleCosto: '1 crédito · te quedan $_credTopUltra',
          habilitado: _credTopUltra > 0,
          motivoDeshabilitado:
              _credTopUltra <= 0 ? 'Sin créditos disponibles' : null,
          filled: true,
        ),
        if (_credRecomendados <= 0 &&
            _credTop <= 0 &&
            _credTopUltra <= 0) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: () =>
                Navigator.pushNamed(context, '/administrar_subscripciones'),
            child: Text(
              'Conseguir más créditos',
              style: GoogleFonts.baloo2(
                fontWeight: FontWeight.w800,
                color: ColoresLocales.acentoVioletaMarca,
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _capitalizarChip(String texto) {
    if (texto.isEmpty) return texto;
    return texto[0].toUpperCase() + texto.substring(1);
  }

  Widget _opcionModoPublicacion({
    required String label,
    required String descripcion,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final fondoBoton = selected
        ? ColoresLocales.botonVioletaFondo
        : ColoresLocales.superficieElevada;
    final textoBoton = selected
        ? ColoresLocales.botonVioletaTexto
        : ColoresLocales.textoOnFondoClaro;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fondoBoton,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                label,
                style: GoogleFonts.baloo2(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: textoBoton,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          descripcion,
          textAlign: TextAlign.center,
          style: GoogleFonts.baloo2(
            fontSize: 10.5,
            height: 1.25,
            color: ColoresLocales.textoSecundarioOnFondoClaro,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _chipSeleccionEvento({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    String? subtitle,
    double? height,
    double verticalPadding = 6,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 150),
        height: height,
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: verticalPadding,
        ),
        decoration: BoxDecoration(
          color: selected
              ? ColoresLocales.acentoVioleta
              : ColoresLocales.cardLavanda,
          borderRadius: BorderRadius.circular(50),
        ),
        child: subtitle == null
            ? Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.baloo2(
                  color: selected
                      ? ColoresLocales.textoEnBoton
                      : ColoresLocales.textoOnFondoClaro,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.baloo2(
                      color: selected
                          ? ColoresLocales.textoEnBoton
                          : ColoresLocales.textoOnFondoClaro,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                      height: 1,
                    ),
                  ),
                  SizedBox(height: 1),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.baloo2(
                      fontSize: 9,
                      color: selected
                          ? Colors.white.withOpacity(0.95)
                          : ColoresLocales.textoSecundarioOnFondoClaro,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  static String _normalizarBusquedaUbicacion(String value) {
    return value
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .trim();
  }

  List<String> _filtrarSugerenciasUbicacion(
    String input,
    List<String> opciones,
  ) {
    final q = _normalizarBusquedaUbicacion(input);
    if (q.isEmpty) return const [];
    return opciones
        .where((opcion) => _normalizarBusquedaUbicacion(opcion).contains(q))
        .take(7)
        .toList();
  }

  Widget _campoUbicacionConAutofiltro({
    required TextEditingController controller,
    required String label,
    required List<String> opciones,
    required String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      onChanged: (value) {
        if (_autocompletandoUbicacion) return;
        final sugerencias = _filtrarSugerenciasUbicacion(value, opciones);
        if (sugerencias.isEmpty) {
          setState(() {});
          return;
        }

        final mejor = sugerencias.first;
        final normalizadoValor = _normalizarBusquedaUbicacion(value);
        final normalizadoMejor = _normalizarBusquedaUbicacion(mejor);

        if (normalizadoValor.isEmpty || normalizadoValor == normalizadoMejor) {
          setState(() {});
          return;
        }

        final coincidePrefijo = normalizadoMejor.startsWith(normalizadoValor);
        if (!coincidePrefijo) {
          setState(() {});
          return;
        }

        _autocompletandoUbicacion = true;
        controller.value = TextEditingValue(
          text: mejor,
          selection: TextSelection(
            baseOffset: value.length,
            extentOffset: mejor.length,
          ),
        );
        _autocompletandoUbicacion = false;
        setState(() {});
      },
      style: GoogleFonts.baloo2(color: ColoresLocales.textoOnFondoClaro),
      decoration: _inputUnaLinea(label),
      validator: validator,
    );
  }

  InputDecoration _inputUnaLinea(String hint) {
    const radius = BorderRadius.all(Radius.circular(50));
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.baloo2(
        color: ColoresLocales.textoSecundarioOnFondoClaro,
        fontWeight: FontWeight.w600,
      ),
      filled: true,
      fillColor: ColoresLocales.rellenoInput,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
    );
  }

  InputDecoration _inputMultiLinea(String hint) {
    const radius = BorderRadius.all(Radius.circular(24));
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.baloo2(
        color: ColoresLocales.textoSecundarioOnFondoClaro,
        fontWeight: FontWeight.w600,
      ),
      filled: true,
      fillColor: ColoresLocales.rellenoInput,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      margin: EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.all(16),
      decoration: ColoresLocales.decoracionCard(sinBorde: true),
      child: child,
    );
  }

  Widget _cardOpcionalColapsable({
    required String pregunta,
    required String ayudaColapsada,
    required bool expandido,
    required ValueChanged<bool> onExpandidoChanged,
    String? resumenActivo,
    String? resumenEstado,
    bool resumenEstadoDestacado = false,
    required Widget child,
  }) {
    final colorResumenEstado = resumenEstadoDestacado
        ? ColoresLocales.acentoVioleta
        : (TemaAppLocales.instancia.esOscuro
              ? ColoresLocales.textoOnFondoClaro.withValues(alpha: 0.82)
              : ColoresLocales.textoSecundarioOnFondoClaro);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onExpandidoChanged(!expandido),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pregunta,
                            style: GoogleFonts.baloo2(
                              color: ColoresLocales.textoOnFondoClaro,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              height: 1.25,
                            ),
                          ),
                          if (!expandido) ...[
                            if (ayudaColapsada.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                ayudaColapsada,
                                style: GoogleFonts.baloo2(
                                  color: ColoresLocales
                                      .textoSecundarioOnFondoClaro,
                                  fontSize: 11.5,
                                  height: 1.3,
                                ),
                              ),
                            ],
                            if (resumenEstado != null &&
                                resumenEstado.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                resumenEstado,
                                style: GoogleFonts.baloo2(
                                  color: colorResumenEstado,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                              ),
                            ] else if (resumenActivo != null &&
                                resumenActivo.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                resumenActivo,
                                style: GoogleFonts.baloo2(
                                  color: ColoresLocales.acentoVioletaMarca,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      expandido
                          ? CupertinoIcons.chevron_up
                          : CupertinoIcons.chevron_down,
                      size: 18,
                      color: ColoresLocales.textoSecundarioOnFondoClaro,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expandido) ...[const SizedBox(height: 14), child],
        ],
      ),
    );
  }

  String? get _resumenUbicacionExterna {
    if (_esEnLocal) return null;
    final ciudad = _ciudadEventoCtrl.text.trim();
    if (ciudad.isNotEmpty) return 'Fuera del local · $ciudad';
    return 'Fuera del local';
  }

  String? get _resumenVentaEntradas {
    final url = _urlCompraEntradasCtrl.text.trim();
    if (url.isEmpty) return null;
    return 'Link de entradas agregado';
  }

  String? get _resumenAdvertenciasExtras {
    final txt = _advertenciasCtrl.text.trim();
    if (txt.isEmpty) return null;
    return 'Con advertencias o requisitos';
  }

  bool get _sistemaIngresoPersonalizado =>
      _modoLista != 'auto' || !_permiteSquads || _limitarCupoLista;

  String get _resumenSistemaIngreso {
    final lista = _modoLista == 'auto'
        ? 'Lista auto (todos pueden unirse)'
        : 'Lista manual (aprobación previa)';
    final squads = _permiteSquads ? 'se permiten squads' : 'sin squads';
    final cupo = _limitarCupoLista
        ? () {
            final n = int.tryParse(_cupoListaCtrl.text.trim());
            return n != null ? 'cupo máximo $n' : 'con cupo limitado';
          }()
        : 'sin cupo límite';
    return '$lista, $squads, $cupo.';
  }

  Widget _contenidoSistemaIngreso() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Modo de lista',
          style: GoogleFonts.baloo2(
            color: ColoresLocales.textoSecundarioOnFondoClaro,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _chipSeleccionEvento(
                label: 'Auto',
                subtitle: 'Sin revisión',
                selected: _modoLista == 'auto',
                height: 42,
                onTap: () => setState(() => _modoLista = 'auto'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _chipSeleccionEvento(
                label: 'Manual',
                subtitle: 'Aprobación manual',
                selected: _modoLista == 'manual',
                height: 42,
                onTap: () => setState(() => _modoLista = 'manual'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _switchFilaCompacta(
          label: '¿Permitir squads?',
          valor: _permiteSquads,
          onChanged: (v) => setState(() => _permiteSquads = v),
        ),
        const SizedBox(height: 6),
        _switchFilaCompacta(
          label: '¿Cupo máximo de lista?',
          valor: _limitarCupoLista,
          onChanged: (v) => setState(() => _limitarCupoLista = v),
        ),
        if (_limitarCupoLista)
          TextFormField(
            controller: _cupoListaCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            style: GoogleFonts.baloo2(color: ColoresLocales.textoOnFondoClaro),
            decoration: _inputUnaLinea('Número máximo de personas en lista'),
            validator: (v) {
              if (!_limitarCupoLista) return null;
              final n = int.tryParse((v ?? '').trim());
              return (n == null || n <= 0) ? 'Ingresá un cupo válido' : null;
            },
          ),
      ],
    );
  }

  Widget _contenidoVentaEntradas() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pegá el link para que los usuarios compren directamente.',
          style: GoogleFonts.baloo2(
            color: ColoresLocales.textoSecundarioOnFondoClaro,
            fontSize: 12.5,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _urlCompraEntradasCtrl,
          keyboardType: TextInputType.url,
          onChanged: (_) => setState(() {}),
          style: GoogleFonts.baloo2(color: ColoresLocales.textoOnFondoClaro),
          decoration: _inputUnaLinea(
            'Link de PaseShow, Ticketek u otra plataforma',
          ),
        ),
      ],
    );
  }

  Widget _contenidoUbicacionEvento() {
    if (_esOrganizadorEventos) {
      return _camposUbicacionOtroLugar();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment<bool>(value: true, label: Text('En mi local')),
            ButtonSegment<bool>(value: false, label: Text('En otro lugar')),
          ],
          selected: {_esEnLocal},
          style: ButtonStyle(
            side: WidgetStateProperty.all(BorderSide.none),
            foregroundColor: WidgetStateProperty.resolveWith(
              (_) => ColoresLocales.textoOnFondoClaro,
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected)
                  ? ColoresLocales.acentoVioleta.withOpacity(0.2)
                  : ColoresLocales.chipInactivo,
            ),
          ),
          onSelectionChanged: (set) {
            final v = set.first;
            setState(() {
              _esEnLocal = v;
              if (!v) _expandUbicacionExterna = true;
              if (_esEnLocal) {
                _direccionEventoCtrl.clear();
                _ciudadEventoCtrl.clear();
                _provinciaEventoCtrl.clear();
                _urlMapsEventoCtrl.clear();
              }
            });
          },
        ),
        if (_esEnLocal) ...[
          const SizedBox(height: 8),
          Text(
            'Se usará la ubicación de tu perfil: ${_nombreLocal ?? 'tu local'}',
            style: GoogleFonts.baloo2(
              color: ColoresLocales.textoSecundarioOnFondoClaro,
              fontSize: 12,
            ),
          ),
        ],
        if (!_esEnLocal) ...[
          const SizedBox(height: 10),
          TextFormField(
            controller: _direccionEventoCtrl,
            onChanged: (_) => setState(() {}),
            style: GoogleFonts.baloo2(color: ColoresLocales.textoOnFondoClaro),
            decoration: _inputUnaLinea('Dirección del evento'),
            validator: (v) => !_esEnLocal && (v == null || v.trim().isEmpty)
                ? 'Completá la dirección del evento'
                : null,
          ),
          const SizedBox(height: 10),
          _campoUbicacionConAutofiltro(
            controller: _ciudadEventoCtrl,
            label: 'Ciudad del evento',
            opciones: _ciudadesCordobaEvento,
            validator: (v) => !_esEnLocal && (v == null || v.trim().isEmpty)
                ? 'Completá la ciudad del evento'
                : null,
          ),
          const SizedBox(height: 10),
          _campoUbicacionConAutofiltro(
            controller: _provinciaEventoCtrl,
            label: 'Provincia',
            opciones: _provinciasEvento,
            validator: (v) => !_esEnLocal && (v == null || v.trim().isEmpty)
                ? 'Completá la provincia del evento'
                : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _urlMapsEventoCtrl,
            onChanged: (_) => setState(() {}),
            style: GoogleFonts.baloo2(color: ColoresLocales.textoOnFondoClaro),
            decoration: _inputUnaLinea('URL de Google Maps'),
            validator: (v) => !_esEnLocal && (v == null || v.trim().isEmpty)
                ? 'Completá la URL de Google Maps'
                : null,
          ),
        ],
      ],
    );
  }

  Widget _camposUbicacionOtroLugar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '¿Dónde es el evento?',
          style: GoogleFonts.baloo2(
            color: ColoresLocales.textoOnFondoClaro,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Como organizador no usamos la dirección de un local propio.',
          style: GoogleFonts.baloo2(
            color: ColoresLocales.textoSecundarioOnFondoClaro,
            fontSize: 12.5,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _direccionEventoCtrl,
          onChanged: (_) => setState(() {}),
          style: GoogleFonts.baloo2(color: ColoresLocales.textoOnFondoClaro),
          decoration: _inputUnaLinea('Dirección del evento'),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Completá la dirección del evento'
              : null,
        ),
        const SizedBox(height: 10),
        _campoUbicacionConAutofiltro(
          controller: _ciudadEventoCtrl,
          label: 'Ciudad del evento',
          opciones: _ciudadesCordobaEvento,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Completá la ciudad del evento'
              : null,
        ),
        const SizedBox(height: 10),
        _campoUbicacionConAutofiltro(
          controller: _provinciaEventoCtrl,
          label: 'Provincia',
          opciones: _provinciasEvento,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Completá la provincia del evento'
              : null,
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _urlMapsEventoCtrl,
          onChanged: (_) => setState(() {}),
          style: GoogleFonts.baloo2(color: ColoresLocales.textoOnFondoClaro),
          decoration: _inputUnaLinea('URL de Google Maps'),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Completá la URL de Google Maps'
              : null,
        ),
      ],
    );
  }

  Widget _contenidoAdvertenciasExtras() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _advertenciasCtrl,
          minLines: 3,
          maxLines: 5,
          onChanged: (_) => setState(() {}),
          style: GoogleFonts.baloo2(color: ColoresLocales.textoOnFondoClaro),
          decoration: _inputMultiLinea(
            'Ej: código de vestimenta, llevar DNI, edad mínima...',
          ),
        ),
      ],
    );
  }

  Widget _switchFilaCompacta({
    required String label,
    required bool valor,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.baloo2(
              color: ColoresLocales.textoOnFondoClaro,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(width: 12),
        CupertinoSwitch(
          value: valor,
          onChanged: onChanged,
          activeTrackColor: ColoresLocales.acentoVioleta,
        ),
      ],
    );
  }

  String get _tituloAppBar {
    if (_paso == 1) return 'Crear el evento';
    return _esSimple ? 'Publicar en cartelera' : 'Sumá promos y visibilidad';
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final esPantallaExito = _paso == 3;
    return Scaffold(
      backgroundColor: esPantallaExito
          ? ColoresLocales.acentoVioleta
          : ColoresLocales.fondoClaro,
      appBar: esPantallaExito
          ? null
          : AppBar(
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              backgroundColor: Colors.transparent,
              forceMaterialTransparency: true,
              centerTitle: true,
              leading: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  if (_paso == 2) {
                    setState(() => _paso = 1);
                  } else {
                    Navigator.of(context).pop();
                  }
                },
                child: Icon(
                  CupertinoIcons.chevron_back,
                  color: ColoresLocales.acentoVioleta,
                ),
              ),
              title: Text(
                _tituloAppBar,
                style: GoogleFonts.baloo2(
                  fontWeight: FontWeight.w900,
                  color: ColoresLocales.acentoVioleta,
                ),
              ),
            ),
      body: _cargandoPerfil
          ? Center(
              child: CircularProgressIndicator(
                color: ColoresLocales.acentoVioleta,
              ),
            )
          : esPantallaExito
          ? _buildPasoExito()
          : SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                    child: Center(
                      child: SizedBox(
                        width: 300,
                        child: _IndicadorPasoConectado(actual: _paso),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: _paso == 1 ? _buildPaso1() : _buildPaso2(),
                        ),
                      ),
                    ),
                  ),
                  _buildFooterBotones(),
                ],
              ),
            ),
    );
  }

  Widget _buildPasoExito() {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 88,
                    color: ColoresLocales.textoEnBoton,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Evento publicado',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.baloo2(
                      color: ColoresLocales.textoEnBoton,
                      fontWeight: FontWeight.w800,
                      fontSize: 34,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tu evento ya está en cartelera. ¡Gran trabajo! Ahora solo queda compartirlo y recibir reservas.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.baloo2(
                      color: Colors.white.withOpacity(0.92),
                      fontSize: 16,
                      height: 1.25,
                    ),
                  ),
                  SizedBox(height: 16),
                  if (_flyerBytes != null)
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          width: 150,
                          height: 230,
                          child: Image.memory(_flyerBytes!, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _mensajeVisibilidadExito,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.baloo2(
                        color: ColoresLocales.superficie,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ),
                  SizedBox(height: 18),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/home',
                        (route) => false,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: Size.fromHeight(52),
                      backgroundColor: ColoresLocales.superficie,
                      foregroundColor: ColoresLocales.acentoVioleta,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                    child: Text(
                      'Volver al dashboard',
                      style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
                    ),
                  ),
                  SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/home',
                        (route) => false,
                      );
                      Future.delayed(const Duration(milliseconds: 60), () {
                        if (context.mounted) {
                          Navigator.pushNamed(context, '/mis_eventos');
                        }
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      side: BorderSide.none,
                      backgroundColor: Colors.white.withValues(alpha: 0.14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                    child: Text(
                      'Ir a mis eventos',
                      style: GoogleFonts.baloo2(
                        color: ColoresLocales.textoEnBoton,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_idEventoPublicado != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'ID evento: $_idEventoPublicado',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.baloo2(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaso1() {
    final onlyDigits = [FilteringTextInputFormatter.digitsOnly];
    return Form(
      key: _formPaso1Key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¿Cómo querés publicar?',
                  style: GoogleFonts.baloo2(
                    color: ColoresLocales.textoOnFondoClaro,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _opcionModoPublicacion(
                        label: 'Completo',
                        descripcion: 'Configurá promos, QR, listas y más',
                        selected: _modoEvento == 'completo',
                        onTap: () => setState(() {
                          if (_modoEvento == 'simple') {
                            _modoLista = 'auto';
                            _permiteSquads = true;
                            _limitarCupoLista = false;
                          }
                          _modoEvento = 'completo';
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _opcionModoPublicacion(
                        label: 'Simple',
                        descripcion: 'Solo flyer en cartelera',
                        selected: _modoEvento == 'simple',
                        onTap: () => setState(() {
                          _modoEvento = 'simple';
                          _esEnLocal = !_esOrganizadorEventos;
                          _fechaInicio = null;
                          _fechaFin = null;
                          _agregarPromos = false;
                          _limitarCupoLista = false;
                          _permiteSquads = false;
                          _modoLista = 'auto';
                          _expandUbicacionExterna = false;
                          _expandVentaEntradas = false;
                          _expandSistemaIngreso = false;
                          _expandAdvertenciasExtras = false;
                        }),
                      ),
                    ),
                  ],
                ),
                if (_esSimple) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: ColoresLocales.acentoVioleta.withOpacity(0.08),
                    ),
                    child: Text(
                      _ciudadLocal != null && _ciudadLocal!.trim().isNotEmpty
                          ? 'Modo vidriera: solo título, flyer y tipo. Se publica en $_ciudadLocal (ubicación de tu local) y sale de cartelera automáticamente a los 30 días.'
                          : 'Modo vidriera: solo título, flyer y tipo. Completá ciudad en tu perfil para aparecer en cartelera. El evento sale solo a los 30 días.',
                      style: GoogleFonts.baloo2(
                        color: ColoresLocales.textoSecundarioOnFondoClaro,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!_esSimple) ...[
            const SizedBox(height: 4),
            _BotonAsistenteEventoIa(onTap: _abrirAsistenteEvento),
          ],
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _esSimple
                      ? 'Lo esencial para la cartelera'
                      : 'Completá la información base de tu evento',
                  style: GoogleFonts.baloo2(
                    color: ColoresLocales.textoOnFondoClaro,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                SizedBox(height: 12),
                TextFormField(
                  controller: _tituloEventoCtrl,
                  decoration: _inputUnaLinea('Título del evento'),
                  style: GoogleFonts.baloo2(
                    color: ColoresLocales.textoOnFondoClaro,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Completá el título del evento'
                      : null,
                ),
                const SizedBox(height: 12),
                _buildSubCardSubirFlyer(),
                if (!_esSimple) ...[
                  SizedBox(height: 12),
                  TextFormField(
                    controller: _descripcionEventoCtrl,
                    minLines: 3,
                    maxLines: 5,
                    decoration: _inputMultiLinea(
                      'Descripción breve del evento',
                    ),
                    style: GoogleFonts.baloo2(
                      color: ColoresLocales.textoOnFondoClaro,
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Completá la descripción del evento'
                        : null,
                  ),
                ],
                SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tipo de evento',
                    style: GoogleFonts.baloo2(
                      color: ColoresLocales.textoOnFondoClaro,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      const [
                        'boliche',
                        'bar',
                        'gastro',
                        'cafe',
                        'fiesta',
                        'evento',
                        'sunset',
                        'baile',
                        'concierto',
                        'otro',
                      ].map((tipo) {
                        final seleccionado = _tipoEvento == tipo;
                        return _chipSeleccionEvento(
                          label: _capitalizarChip(tipo),
                          selected: seleccionado,
                          verticalPadding: 3,
                          onTap: () => setState(() => _tipoEvento = tipo),
                        );
                      }).toList(),
                ),
                if (!_esSimple) ...[
                  SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Elegí fecha y hora',
                      style: GoogleFonts.baloo2(
                        color: ColoresLocales.textoOnFondoClaro,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _FechaHoraField(
                    label: 'Inicio',
                    valor: _textoFecha(_fechaInicio),
                    onTap: () async {
                      final d = await _seleccionarFechaHora(
                        context,
                        _fechaInicio,
                      );
                      if (d != null && mounted) {
                        setState(() {
                          _fechaInicio = d;
                          if (_fechaFin == null || !_fechaFin!.isAfter(d)) {
                            _fechaFin = d.add(const Duration(hours: 5));
                          }
                        });
                      }
                    },
                  ),
                  SizedBox(height: 10),
                  _FechaHoraField(
                    label: 'Fin',
                    valor: _textoFecha(_fechaFin),
                    onTap: () async {
                      final d = await _seleccionarFechaHora(context, _fechaFin);
                      if (d != null && mounted) setState(() => _fechaFin = d);
                    },
                  ),
                  SizedBox(height: 12),
                  TextFormField(
                    controller: _edadMinimaCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: onlyDigits,
                    style: GoogleFonts.baloo2(
                      color: ColoresLocales.textoOnFondoClaro,
                    ),
                    decoration: _inputUnaLinea('Edad mínima (opcional)'),
                  ),
                ],
              ],
            ),
          ),
          if (!_esSimple) ...[
            _cardOpcionalColapsable(
              pregunta: '¿Vendés entradas por otra plataforma?',
              ayudaColapsada: 'PaseShow, Ticketek, etc.',
              expandido: _expandVentaEntradas,
              resumenActivo: _resumenVentaEntradas,
              onExpandidoChanged: (v) =>
                  setState(() => _expandVentaEntradas = v),
              child: _contenidoVentaEntradas(),
            ),
            if (_esOrganizadorEventos)
              _card(child: _camposUbicacionOtroLugar())
            else
              _cardOpcionalColapsable(
                pregunta: '¿Realizás el evento fuera de tu local?',
                ayudaColapsada: 'Por defecto usamos la ubicación de tu perfil.',
                expandido: _expandUbicacionExterna,
                resumenActivo: _resumenUbicacionExterna,
                onExpandidoChanged: (v) =>
                    setState(() => _expandUbicacionExterna = v),
                child: _contenidoUbicacionEvento(),
              ),
            _cardOpcionalColapsable(
              pregunta: '¿Querés personalizar la lista de ingreso?',
              ayudaColapsada: '',
              expandido: _expandSistemaIngreso,
              resumenEstado: _resumenSistemaIngreso,
              resumenEstadoDestacado: _sistemaIngresoPersonalizado,
              onExpandidoChanged: (v) =>
                  setState(() => _expandSistemaIngreso = v),
              child: _contenidoSistemaIngreso(),
            ),
            _cardOpcionalColapsable(
              pregunta: '¿Tenés advertencias o requisitos extras?',
              ayudaColapsada: 'Código de vestimenta, edad, DNI, etc.',
              expandido: _expandAdvertenciasExtras,
              resumenActivo: _resumenAdvertenciasExtras,
              onExpandidoChanged: (v) =>
                  setState(() => _expandAdvertenciasExtras = v),
              child: _contenidoAdvertenciasExtras(),
            ),
          ],
          if (_esSimple && _esOrganizadorEventos)
            _card(child: _camposUbicacionOtroLugar()),
        ],
      ),
    );
  }

  Widget _buildPaso2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_esSimple)
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Promos del evento',
                  style: GoogleFonts.baloo2(
                    color: ColoresLocales.textoOnFondoClaro,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                _switchFilaCompacta(
                  label: '¿Querés agregar promociones a este evento?',
                  valor: _agregarPromos,
                  onChanged: (v) {
                    setState(() {
                      _agregarPromos = v;
                      if (_agregarPromos && _promos.isEmpty) {
                        _promos.add(_PromoDraft());
                      }
                      if (!_agregarPromos) {
                        for (final p in _promos) {
                          p.dispose();
                        }
                        _promos.clear();
                      }
                    });
                  },
                ),
                if (_agregarPromos) ...[
                  SizedBox(height: 4),
                  Text(
                    'Creá promos atractivas como 2x1, descuentos importantes o productos a precios llamativos.',
                    style: GoogleFonts.baloo2(
                      color: ColoresLocales.textoSecundarioOnFondoClaro,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._promos.asMap().entries.map((entry) {
                    final i = entry.key;
                    final p = entry.value;
                    return _PromoCard(
                      index: i + 1,
                      promo: p,
                      inputBuilder: _inputUnaLinea,
                      inputMultilineBuilder: _inputMultiLinea,
                      textoInicio: _textoFechaPromoInicio(p),
                      textoFin: _textoFechaPromoFin(p),
                      inicioVinculado: p.inicioEsDelEvento,
                      finVinculado: p.finEsDelEvento,
                      onPickFechaInicio: () async {
                        final d = await _seleccionarFechaHora(
                          context,
                          p.inicioEsDelEvento ? _fechaInicio : p.fechaInicio,
                        );
                        if (d != null && mounted) {
                          setState(() {
                            p.inicioEsDelEvento = false;
                            p.fechaInicio = d;
                          });
                        }
                      },
                      onPickFechaFin: () async {
                        final d = await _seleccionarFechaHora(
                          context,
                          p.finEsDelEvento ? _fechaFin : p.fechaFin,
                        );
                        if (d != null && mounted) {
                          setState(() {
                            p.finEsDelEvento = false;
                            p.fechaFin = d;
                          });
                        }
                      },
                      onRemove: () {
                        setState(() {
                          p.dispose();
                          _promos.removeAt(i);
                        });
                      },
                    );
                  }),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: _agregarPromo,
                      icon: Icon(Icons.add),
                      label: Text(
                        'Agregar otra promo',
                        style: GoogleFonts.baloo2(fontWeight: FontWeight.w700),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: ColoresLocales.acentoVioleta,
                        backgroundColor: ColoresLocales.acentoVioleta
                            .withValues(alpha: 0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Cartelera',
                style: GoogleFonts.baloo2(
                  color: ColoresLocales.textoOnFondoClaro,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Elegí el nivel y publicá en un toque.',
                style: GoogleFonts.baloo2(
                  color: ColoresLocales.textoSecundarioOnFondoClaro,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 16),
              _buildPanelCuentaCreditosCrear(),
              const SizedBox(height: 20),
              _encabezadoPublicarEn(),
              const SizedBox(height: 12),
              _buildBotonesPublicarEn(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFooterBotones() {
    if (_paso == 2) {
      return Container(
        padding: EdgeInsets.fromLTRB(16, 10, 16, 16),
        color: ColoresLocales.fondoClaro,
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 760),
              child: TextButton.icon(
                onPressed: _guardando ? null : () => _irAPaso(1),
                icon: Icon(CupertinoIcons.chevron_left, size: 18),
                style: TextButton.styleFrom(
                  minimumSize: Size.fromHeight(52),
                  foregroundColor: ColoresLocales.acentoVioleta,
                  backgroundColor: ColoresLocales.acentoVioleta.withValues(
                    alpha: 0.1,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50),
                  ),
                ),
                label: Text(
                  'Volver al paso 1',
                  style: GoogleFonts.baloo2(
                    color: ColoresLocales.acentoVioleta,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16),
      color: ColoresLocales.fondoClaro,
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 760),
            child: ElevatedButton(
              onPressed: _guardando
                  ? null
                  : () {
                      if (_validarPaso1()) _irAPaso(2);
                    },
              style: ElevatedButton.styleFrom(
                minimumSize: Size.fromHeight(52),
                backgroundColor: ColoresLocales.acentoVioleta,
                foregroundColor: ColoresLocales.textoEnBoton,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50),
                ),
              ),
              child: _guardando
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ColoresLocales.textoEnBoton,
                      ),
                    )
                  : Text(
                      _esSimple ? 'Elegir visibilidad' : 'Siguiente',
                      style: GoogleFonts.baloo2(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PromoDraft {
  final tituloCtrl = TextEditingController();
  final descripcionCtrl = TextEditingController();
  final cuposCtrl = TextEditingController();
  final minMiembrosCtrl = TextEditingController();
  final maxMiembrosCtrl = TextEditingController();

  DateTime? fechaInicio;
  DateTime? fechaFin;
  bool inicioEsDelEvento = true;
  bool finEsDelEvento = true;
  bool limitarCantidad = false;
  String modoUso = 'individual';

  DateTime? inicioEfectivo(DateTime? eventoInicio) =>
      inicioEsDelEvento ? eventoInicio : fechaInicio;

  DateTime? finEfectivo(DateTime? eventoFin) =>
      finEsDelEvento ? eventoFin : fechaFin;

  void dispose() {
    tituloCtrl.dispose();
    descripcionCtrl.dispose();
    cuposCtrl.dispose();
    minMiembrosCtrl.dispose();
    maxMiembrosCtrl.dispose();
  }
}

class _PromoCard extends StatefulWidget {
  final int index;
  final _PromoDraft promo;
  final InputDecoration Function(String) inputBuilder;
  final InputDecoration Function(String) inputMultilineBuilder;
  final String textoInicio;
  final String textoFin;
  final bool inicioVinculado;
  final bool finVinculado;
  final VoidCallback onPickFechaInicio;
  final VoidCallback onPickFechaFin;
  final VoidCallback onRemove;

  const _PromoCard({
    required this.index,
    required this.promo,
    required this.inputBuilder,
    required this.inputMultilineBuilder,
    required this.textoInicio,
    required this.textoFin,
    required this.inicioVinculado,
    required this.finVinculado,
    required this.onPickFechaInicio,
    required this.onPickFechaFin,
    required this.onRemove,
  });

  @override
  State<_PromoCard> createState() => _PromoCardState();
}

class _PromoCardState extends State<_PromoCard> {
  Widget _chipModoPromo({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 150),
        height: 42,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? ColoresLocales.acentoVioleta
              : ColoresLocales.cardLavanda,
          borderRadius: BorderRadius.circular(50),
        ),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.baloo2(
              color: selected ? Colors.white : ColoresLocales.textoOnFondoClaro,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final p = widget.promo;
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(12),
      decoration: ColoresLocales.decoracionCard(radius: 18, sinBorde: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Promo ${widget.index}',
                style: GoogleFonts.baloo2(
                  color: ColoresLocales.textoOnFondoClaro,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Spacer(),
              IconButton(
                onPressed: widget.onRemove,
                icon: Icon(
                  Icons.delete_outline,
                  color: ColoresLocales.textoSecundarioOnFondoClaro,
                ),
              ),
            ],
          ),
          TextField(
            controller: p.tituloCtrl,
            style: GoogleFonts.baloo2(color: ColoresLocales.textoOnFondoClaro),
            decoration: widget.inputBuilder('Título de la promo'),
          ),
          SizedBox(height: 8),
          TextField(
            controller: p.descripcionCtrl,
            minLines: 2,
            maxLines: 4,
            style: GoogleFonts.baloo2(color: ColoresLocales.textoOnFondoClaro),
            decoration: widget.inputMultilineBuilder('Descripción de la promo'),
          ),
          SizedBox(height: 8),
          _FechaHoraField(
            label: 'Inicio de promo',
            valor: widget.textoInicio,
            esReferenciaEvento: widget.inicioVinculado,
            onTap: widget.onPickFechaInicio,
          ),
          SizedBox(height: 8),
          _FechaHoraField(
            label: 'Fin de promo',
            valor: widget.textoFin,
            esReferenciaEvento: widget.finVinculado,
            onTap: widget.onPickFechaFin,
          ),
          SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '¿Limitar cantidad?',
                  style: GoogleFonts.baloo2(
                    color: ColoresLocales.textoOnFondoClaro,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(width: 12),
              CupertinoSwitch(
                value: p.limitarCantidad,
                onChanged: (v) => setState(() => p.limitarCantidad = v),
                activeTrackColor: ColoresLocales.acentoVioleta,
              ),
            ],
          ),
          if (p.limitarCantidad)
            TextField(
              controller: p.cuposCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: GoogleFonts.baloo2(
                color: ColoresLocales.textoOnFondoClaro,
              ),
              decoration: widget.inputBuilder('Cantidad máxima'),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _chipModoPromo(
                  label: 'Individual',
                  selected: p.modoUso == 'individual',
                  onTap: () => setState(() => p.modoUso = 'individual'),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _chipModoPromo(
                  label: 'Squad',
                  selected: p.modoUso == 'squad',
                  onTap: () => setState(() => p.modoUso = 'squad'),
                ),
              ),
            ],
          ),
          if (p.modoUso == 'squad') ...[
            SizedBox(height: 8),
            TextField(
              controller: p.minMiembrosCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: GoogleFonts.baloo2(
                color: ColoresLocales.textoOnFondoClaro,
              ),
              decoration: widget.inputBuilder('Mínimo de miembros'),
            ),
            SizedBox(height: 8),
            TextField(
              controller: p.maxMiembrosCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: GoogleFonts.baloo2(
                color: ColoresLocales.textoOnFondoClaro,
              ),
              decoration: widget.inputBuilder('Máximo de miembros'),
            ),
          ],
        ],
      ),
    );
  }
}

class _FechaHoraField extends StatelessWidget {
  final String label;
  final String valor;
  final VoidCallback onTap;
  final bool esReferenciaEvento;

  const _FechaHoraField({
    required this.label,
    required this.valor,
    required this.onTap,
    this.esReferenciaEvento = false,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final sinFecha =
        valor == 'Seleccionar fecha y hora' ||
        valor.startsWith('Se usará la fecha');
    final vinculado = esReferenciaEvento && !sinFecha;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: ColoresLocales.cardLavanda,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$label: $valor',
                style: GoogleFonts.baloo2(
                  color: sinFecha
                      ? ColoresLocales.textoSecundarioOnFondoClaro
                      : vinculado
                      ? ColoresLocales.acentoVioleta
                      : ColoresLocales.textoOnFondoClaro,
                  fontWeight: vinculado ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
            ),
            Icon(
              CupertinoIcons.calendar,
              color: ColoresLocales.acentoVioleta,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _IndicadorPasoConectado extends StatelessWidget {
  final int actual;

  const _IndicadorPasoConectado({required this.actual});

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    Widget nodo({
      required int paso,
      required String label,
      required bool activo,
    }) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: Duration(milliseconds: 220),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: activo
                  ? ColoresLocales.acentoVioleta
                  : ColoresLocales.chipInactivo,
            ),
            child: Center(
              child: Text(
                '$paso',
                style: GoogleFonts.baloo2(
                  fontSize: 12,
                  fontWeight: activo ? FontWeight.w900 : FontWeight.w700,
                  color: activo
                      ? ColoresLocales.textoEnBoton
                      : ColoresLocales.textoSecundarioOnFondoClaro,
                ),
              ),
            ),
          ),
          SizedBox(height: 5),
          SizedBox(
            width: 110,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.baloo2(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: ColoresLocales.textoSecundarioOnFondoClaro,
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        nodo(paso: 1, label: 'Datos del evento', activo: actual >= 1),
        Expanded(
          child: Container(
            height: 2.5,
            margin: EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: actual > 1
                  ? ColoresLocales.acentoVioleta
                  : ColoresLocales.acentoVioleta.withOpacity(0.2),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        nodo(paso: 2, label: 'Promos y visibilidad', activo: actual >= 2),
      ],
    );
  }
}

/// Botón "Hacelo más rápido con IA" (abre el chatbot asistente de evento).
/// Solo visible en modo completo.
class _BotonAsistenteEventoIa extends StatelessWidget {
  const _BotonAsistenteEventoIa({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [Color(0xFFF3EDFF), Color(0xFFFFF3D6)],
              ),
              border: Border.all(
                color: ColoresLocales.acentoVioletaMarca.withValues(
                  alpha: 0.35,
                ),
                width: 1.4,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: ColoresLocales.acentoVioletaMarca,
                    ),
                    child: const Icon(
                      CupertinoIcons.sparkles,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hacelo más rápido con IA',
                          style: GoogleFonts.baloo2(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF1A1A1A),
                          ),
                        ),
                        Text(
                          'Creá tu evento charlando, en menos pasos',
                          style: GoogleFonts.baloo2(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF555555),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    CupertinoIcons.chevron_right,
                    size: 18,
                    color: Color(0xFF7C3AED),
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
