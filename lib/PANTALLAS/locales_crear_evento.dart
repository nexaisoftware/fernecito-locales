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
import '../core/supabase_client.dart';
import '../core/servicio_edges_eventos.dart';
import '../core/suscripcion_locales.dart';

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
  String? _tipoSuscripcionRaw;

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
  int _credFlyersAI = 0;
  static const int _maxRecomendados = 16;
  static const int _maxTop = 6;
  static const int _maxTopUltra = 2;
  static const int _maxFlyersAI = 20;

  String? _idEventoPublicado;

  static const Color _mostaza = Color(0xFFD9B44A);
  static const Color _violetRec = Color(0xFF7C3AED);
  static const Color _amberTop = Color(0xFFD97706);
  static const Color _rosaUltra = ColoresLocales.jerarquiaUltra;
  static const Color _cyanFlyers = Color(0xFF0891B2);

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
      _fechaFin = args.fechaFin ?? args.fechaInicio!.add(const Duration(hours: 5));
    }

    if (args.activarPromos && args.nombrePromo != null && args.nombrePromo!.trim().isNotEmpty) {
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
    if (raw == null && args.rutaFlyerLocal != null && args.rutaFlyerLocal!.isNotEmpty) {
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
      _flyerNombre = 'flyer_ia.${args.rutaFlyerLocal?.split('.').last ?? 'jpg'}';
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
      final row = await ServicioSupabase().cliente
          .from('perfiles_locales')
          .select(
            'id, local_verificado, direccion, url_maps, nombre_local, cupos_recomendado, cupos_top_cartelera, cupos_top_ultra, cupos_flyers_ia',
          )
          .eq('id', uid)
          .maybeSingle();
      final tipoRaw = await SuscripcionLocales.leerTipoRawDesdePerfil(uid);
      if (!mounted) return;
      setState(() {
        _idLocal = uid;
        _localVerificado = row?['local_verificado'] as bool? ?? false;
        _nombreLocal = row?['nombre_local'] as String?;
        _tipoSuscripcionRaw = tipoRaw;
        _credRecomendados = (row?['cupos_recomendado'] as num?)?.toInt() ?? 0;
        _credTop = (row?['cupos_top_cartelera'] as num?)?.toInt() ?? 0;
        _credTopUltra = (row?['cupos_top_ultra'] as num?)?.toInt() ?? 0;
        _credFlyersAI = (row?['cupos_flyers_ia'] as num?)?.toInt() ?? 0;
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
                          border: Border.all(
                            color: ColoresLocales.acentoVioleta.withOpacity(
                              0.2,
                            ),
                          ),
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
      _mostrarError('Error al procesar el flyer: $e');
    }
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
      if (_descripcionEventoCtrl.text.trim().isEmpty) {
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
    if (_fechaInicio == null || _fechaFin == null) {
      _mostrarError('Seleccioná fecha y hora de inicio y fin.');
      return false;
    }
    if (!_fechaFin!.isAfter(_fechaInicio!)) {
      _mostrarError('La fecha de fin debe ser posterior al inicio.');
      return false;
    }
    if (!_esEnLocal) {
      if (_direccionEventoCtrl.text.trim().isEmpty) {
        _mostrarError('Completá la dirección del evento.');
        return false;
      }
      if (_ciudadEventoCtrl.text.trim().isEmpty) {
        _mostrarError('Completá la ciudad del evento.');
        return false;
      }
      if (_provinciaEventoCtrl.text.trim().isEmpty) {
        _mostrarError('Completá la provincia del evento.');
        return false;
      }
      if (_urlMapsEventoCtrl.text.trim().isEmpty) {
        _mostrarError('Completá la URL de Google Maps del evento.');
        return false;
      }
    }
    // Cupo es opcional (null = sin límite). Si se ingresa, debe ser >= 1.
    if (_limitarCupoLista) {
      final cupo = int.tryParse(_cupoListaCtrl.text.trim());
      if (cupo == null || cupo <= 0) {
        _mostrarError('Si limitás el cupo, ingresá un número válido (>= 1).');
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
        if (min == null || max == null || min <= 0 || max < min) {
          _mostrarError(
            'Completá mínimo/máximo de squad válidos en la promo ${i + 1}.',
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
    const dias = [
      'lunes',
      'martes',
      'miercoles',
      'jueves',
      'viernes',
      'sabado',
      'domingo',
    ];
    return dias[d.weekday - 1]; // weekday: 1=lunes ... 7=domingo
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

    return {
      // --- Modo del evento (la edge neutraliza los campos funcionales si simple) ---
      'modo_evento': _modoEvento,
      // --- Datos básicos ---
      'titulo_evento': _tituloEventoCtrl.text.trim(),
      'descripcion_evento': _descripcionEventoCtrl.text.trim(),
      'url_flyer': _urlFlyerSubido ?? '',
      // Campos funcionales: en modo simple se mandan neutralizados.
      'url_compra_entradas': _esSimple ? null : (urlCompra.isEmpty ? null : urlCompra),
      'tipo_evento': _tipoEvento,
      'edad_minima': _esSimple ? null : edad,
      'fecha_inicio': _fechaInicio!.toUtc().toIso8601String(),
      'fecha_fin': _fechaFin!.toUtc().toIso8601String(),
      'dia_semana': _fechaInicio != null ? _diaSemana(_fechaInicio!) : null,
      // --- Lista (irrelevante en modo simple, la edge la fuerza a 'auto') ---
      'modo_lista': _esSimple ? 'auto' : _modoLista,
      'cupo_lista_max': _esSimple ? null : cupoLista, // null = sin límite
      'permite_squads': _esSimple ? false : _permiteSquads,
      // --- Ubicación ---
      'es_en_local': _esEnLocal,
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
      if (mounted) _mostrarError('No se pudo publicar el evento: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _mostrarError(String mensaje) {
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

  String get _textoBotonDoradoPublicar {
    if (_intencionPublicacion == _IntencionPublicacion.recFernecito &&
        _credRecomendados <= 0) {
      return '¡Comprar más créditos!';
    }
    if (_intencionPublicacion == _IntencionPublicacion.topCartelera &&
        _credTop <= 0) {
      return '¡Comprar más créditos!';
    }
    if (_intencionPublicacion == _IntencionPublicacion.topUltra &&
        _credTopUltra <= 0) {
      return '¡Comprar más créditos!';
    }
    return 'Publicar';
  }

  String get _estadoCuentaEtiqueta =>
      _localVerificado ? 'Verificado' : 'Gratuita';

  Color get _colorEstadoCuenta => _localVerificado
      ? ColoresLocales.acentoVioleta
      : ColoresLocales.textoSecundarioOnFondoClaro;

  IconData get _iconEstadoCuenta => _localVerificado
      ? CupertinoIcons.checkmark_seal_fill
      : CupertinoIcons.lock_open_fill;

  void _onBotonDoradoPublicar() {
    // Sin verificación: solo puede publicar gratis/normal (la edge lo fuerza igual)
    if (!_localVerificado &&
        (_intencionPublicacion == _IntencionPublicacion.recFernecito ||
            _intencionPublicacion == _IntencionPublicacion.topCartelera ||
            _intencionPublicacion == _IntencionPublicacion.topUltra)) {
      return;
    }
    if (_intencionPublicacion == _IntencionPublicacion.recFernecito &&
        _credRecomendados <= 0) {
      Navigator.pushNamed(context, '/administrar_subscripciones');
      return;
    }
    if (_intencionPublicacion == _IntencionPublicacion.topCartelera &&
        _credTop <= 0) {
      Navigator.pushNamed(context, '/administrar_subscripciones');
      return;
    }
    if (_intencionPublicacion == _IntencionPublicacion.topUltra &&
        _credTopUltra <= 0) {
      Navigator.pushNamed(context, '/administrar_subscripciones');
      return;
    }
    _publicarEvento();
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
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icono, color: color, size: 28),
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
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ColoresLocales.superficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ColoresLocales.acentoVioleta.withOpacity(0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: ColoresLocales.acentoVioleta.withOpacity(0.06),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconEstadoCuenta, size: 14, color: _colorEstadoCuenta),
              SizedBox(width: 5),
              Text(
                'Cuenta: ',
                style: GoogleFonts.baloo2(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ColoresLocales.textoSecundarioOnFondoClaro,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _colorEstadoCuenta.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                    color: _colorEstadoCuenta.withOpacity(0.3),
                  ),
                ),
                child: Text(
                  _estadoCuentaEtiqueta,
                  style: GoogleFonts.baloo2(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _colorEstadoCuenta,
                  ),
                ),
              ),
            ],
          ),
          if (_localVerificado) ...[
            SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Subscripción: ',
                  style: GoogleFonts.baloo2(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ColoresLocales.textoSecundarioOnFondoClaro,
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: ColoresLocales.acentoVioleta.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(
                      color: ColoresLocales.acentoVioleta.withOpacity(0.28),
                    ),
                  ),
                  child: Text(
                    SuscripcionLocales.tipoPlanPago(
                      rawDb: _tipoSuscripcionRaw,
                      localVerificado: true,
                    ),
                    style: GoogleFonts.baloo2(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: ColoresLocales.acentoVioleta,
                    ),
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Te quedan:',
                style: GoogleFonts.baloo2(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: ColoresLocales.textoSecundarioOnFondoClaro,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    _CreditoTextoCrear(
                      icono: CupertinoIcons.hand_thumbsup_fill,
                      label: 'Rec.Fernecito:',
                      valor: _credRecomendados,
                      color: _violetRec,
                      onTap: () => _mostrarDialogoCreditoCrear(
                        icono: CupertinoIcons.hand_thumbsup_fill,
                        color: _violetRec,
                        titulo: 'Recomendaciones Fernecito',
                        valor: _credRecomendados,
                        maximo: _maxRecomendados,
                        descripcion:
                            'Tus eventos aparecen destacados en la sección de recomendaciones de Fernecito, con mayor visibilidad frente a usuarios afines a tu propuesta.',
                      ),
                    ),
                    _CreditoTextoCrear(
                      icono: CupertinoIcons.star_fill,
                      label: 'Top:',
                      valor: _credTop,
                      color: _amberTop,
                      onTap: () => _mostrarDialogoCreditoCrear(
                        icono: CupertinoIcons.star_fill,
                        color: _amberTop,
                        titulo: 'Top Cartelera',
                        valor: _credTop,
                        maximo: _maxTop,
                        descripcion:
                            'Posicionás tu evento en el top de la cartelera principal de Fernecito. Máxima visibilidad para todos los usuarios que navegan la app.',
                      ),
                    ),
                    _CreditoTextoCrear(
                      icono: CupertinoIcons.flame_fill,
                      label: 'Ultra:',
                      valor: _credTopUltra,
                      color: _rosaUltra,
                      onTap: () => _mostrarDialogoCreditoCrear(
                        icono: CupertinoIcons.flame_fill,
                        color: _rosaUltra,
                        titulo: 'Top Ultra',
                        valor: _credTopUltra,
                        maximo: _maxTopUltra,
                        descripcion:
                            'El nivel más alto. Tu evento aparece en las stories que se muestran al abrir la app. Máximo impacto visual garantizado.',
                      ),
                    ),
                    _CreditoTextoCrear(
                      icono: Icons.auto_awesome,
                      label: 'Flyers AI:',
                      valor: _credFlyersAI,
                      color: _cyanFlyers,
                      onTap: () => _mostrarDialogoCreditoCrear(
                        icono: Icons.auto_awesome,
                        color: _cyanFlyers,
                        titulo: 'Generación de Flyers con IA',
                        valor: _credFlyersAI,
                        maximo: _maxFlyersAI,
                        descripcion:
                            'Usá inteligencia artificial para generar flyers profesionales y atractivos para tus eventos en segundos, sin necesidad de diseñador.',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _botonZonaEstandar() {
    final sel = _intencionPublicacion == _IntencionPublicacion.estandar;
    return AnimatedScale(
      scale: sel ? 1.04 : 1.0,
      duration: Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(50),
          boxShadow: sel
              ? [
                  BoxShadow(
                    color: ColoresLocales.acentoVioleta.withOpacity(0.42),
                    blurRadius: 18,
                    spreadRadius: 0,
                    offset: Offset(0, 4),
                  ),
                  BoxShadow(
                    color: ColoresLocales.acentoVioleta.withOpacity(0.18),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: OutlinedButton(
          onPressed: () => setState(
            () => _intencionPublicacion = _IntencionPublicacion.estandar,
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: Size.fromHeight(sel ? 52 : 48),
            side: BorderSide(
              color: ColoresLocales.acentoVioleta,
              width: sel ? 2.4 : 1.45,
            ),
            foregroundColor: ColoresLocales.acentoVioleta,
            backgroundColor: ColoresLocales.superficie,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(50),
            ),
          ),
          child: Text(
            'Zona estándar',
            style: GoogleFonts.baloo2(
              fontWeight: FontWeight.w900,
              fontSize: sel ? 16 : 15,
              color: ColoresLocales.acentoVioleta,
            ),
          ),
        ),
      ),
    );
  }

  Widget _botonOpcionRecTop({
    required IconData icono,
    required String titulo,
    required String costoLabel,
    required Color color,
    required bool seleccionado,
    required VoidCallback onTap,
  }) {
    final sombras = <BoxShadow>[
      if (seleccionado) ...[
        BoxShadow(
          color: ColoresLocales.acentoVioleta.withOpacity(0.38),
          blurRadius: 16,
          spreadRadius: 0,
          offset: Offset(0, 4),
        ),
        BoxShadow(
          color: ColoresLocales.acentoVioleta.withOpacity(0.16),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
      BoxShadow(
        color: color.withOpacity(seleccionado ? 0.4 : 0.22),
        blurRadius: seleccionado ? 14 : 8,
        offset: const Offset(0, 3),
      ),
    ];

    return AnimatedScale(
      scale: seleccionado ? 1.04 : 1.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 200),
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: seleccionado ? 13 : 11,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withOpacity(0.78)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(50),
            boxShadow: sombras,
            border: Border.all(
              color: seleccionado
                  ? Colors.white.withOpacity(0.95)
                  : Colors.transparent,
              width: seleccionado ? 2.2 : 0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icono, size: 16, color: ColoresLocales.textoEnBoton),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  titulo,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.baloo2(
                    fontSize: seleccionado ? 14 : 13,
                    fontWeight: FontWeight.w900,
                    color: ColoresLocales.textoEnBoton,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      costoLabel,
                      style: GoogleFonts.baloo2(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: ColoresLocales.textoEnBoton,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(icono, size: 11, color: ColoresLocales.textoEnBoton),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _capitalizarChip(String texto) {
    if (texto.isEmpty) return texto;
    return texto[0].toUpperCase() + texto.substring(1);
  }

  Widget _chipSeleccionEvento({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    String? subtitle,
    double? height,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 150),
        height: height,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? ColoresLocales.acentoVioleta
              : ColoresLocales.cardLavanda,
          borderRadius: BorderRadius.circular(50),
          border: selected
              ? null
              : Border.all(
                  color: ColoresLocales.acentoVioleta.withOpacity(0.25),
                ),
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
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.baloo2(
        color: ColoresLocales.textoSecundarioOnFondoClaro,
        fontWeight: FontWeight.w600,
      ),
      filled: true,
      fillColor: ColoresLocales.rellenoInput,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(50),
        borderSide: BorderSide(
          color: ColoresLocales.acentoVioleta.withOpacity(0.25),
          width: 1.3,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(50),
        borderSide: BorderSide(
          color: ColoresLocales.acentoVioleta.withOpacity(0.25),
          width: 1.3,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(50),
        borderSide: BorderSide(
          color: ColoresLocales.acentoVioleta,
          width: 1.8,
        ),
      ),
    );
  }

  InputDecoration _inputMultiLinea(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.baloo2(
        color: ColoresLocales.textoSecundarioOnFondoClaro,
        fontWeight: FontWeight.w600,
      ),
      filled: true,
      fillColor: ColoresLocales.rellenoInput,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(
          color: ColoresLocales.acentoVioleta.withOpacity(0.25),
          width: 1.3,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(
          color: ColoresLocales.acentoVioleta.withOpacity(0.25),
          width: 1.3,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(
          color: ColoresLocales.acentoVioleta,
          width: 1.8,
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      margin: EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ColoresLocales.superficie.withOpacity(0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: ColoresLocales.acentoVioleta.withOpacity(0.18),
        ),
      ),
      child: child,
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

  String get _tituloAppBar =>
      _paso == 1 ? 'Crear el evento' : 'Sumá promos y visibilidad';

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
              backgroundColor: ColoresLocales.superficie,
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
                      side: BorderSide(color: Colors.white.withOpacity(0.8)),
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
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _chipSeleccionEvento(
                        label: 'Completo',
                        subtitle: 'Lista, cupos y promos',
                        selected: _modoEvento == 'completo',
                        height: 56,
                        onTap: () => setState(() => _modoEvento = 'completo'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _chipSeleccionEvento(
                        label: 'Simple',
                        subtitle: 'Solo mostrar el evento',
                        selected: _modoEvento == 'simple',
                        height: 56,
                        onTap: () => setState(() {
                          _modoEvento = 'simple';
                          // Apagar lo funcional para que no quede colgado.
                          _agregarPromos = false;
                          _limitarCupoLista = false;
                          _permiteSquads = false;
                          _modoLista = 'auto';
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
                      'Modo vidriera: el evento aparece en la cartelera con su flyer y recibe jerarquía, pero no tendrá reservas, lista ni promos.',
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
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Completá la información base de tu evento',
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
                SizedBox(height: 12),
                GestureDetector(
                  onTap: _procesandoFlyer ? null : _seleccionarFlyer,
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: ColoresLocales.acentoVioleta.withOpacity(0.25),
                      ),
                      color: ColoresLocales.superficie,
                    ),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 170,
                                height: 260,
                                color: ColoresLocales.acentoVioleta.withOpacity(
                                  0.08,
                                ),
                                child: _flyerBytes != null
                                    ? Image.memory(
                                        _flyerBytes!,
                                        fit: BoxFit.cover,
                                      )
                                    : _urlFlyerSubido != null
                                    ? Image.network(
                                        _urlFlyerSubido!,
                                        fit: BoxFit.cover,
                                      )
                                    : CustomPaint(
                                        painter: _DashedRoundedRectPainter(
                                          color: ColoresLocales.acentoVioleta
                                              .withOpacity(0.4),
                                        ),
                                        child: Container(
                                          width: 170,
                                          height: 260,
                                          color: ColoresLocales.acentoVioleta
                                              .withOpacity(0.04),
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 14,
                                          ),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                CupertinoIcons.camera_fill,
                                                color: ColoresLocales
                                                    .acentoVioleta
                                                    .withOpacity(0.7),
                                                size: 36,
                                              ),
                                              SizedBox(height: 10),
                                              Text(
                                                'Tocá para subir tu flyer',
                                                textAlign: TextAlign.center,
                                                style: GoogleFonts.baloo2(
                                                  color: ColoresLocales
                                                      .textoSecundarioOnFondoClaro,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              SizedBox(height: 4),
                                              Text(
                                                'Formato vertical · máx 10MB',
                                                textAlign: TextAlign.center,
                                                style: GoogleFonts.baloo2(
                                                  color: ColoresLocales
                                                      .textoSecundarioOnFondoClaro,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                              ),
                              if (_procesandoFlyer)
                                Container(
                                  width: 170,
                                  height: 260,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CircularProgressIndicator(
                                        color: ColoresLocales.superficie,
                                        strokeWidth: 2,
                                      ),
                                      SizedBox(height: 10),
                                      Text(
                                        'Subiendo flyer...',
                                        style: GoogleFonts.baloo2(
                                          color: ColoresLocales.textoEnBoton,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (_errorFlyer != null) ...[
                          SizedBox(height: 6),
                          Text(
                            _errorFlyer!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.baloo2(
                              color: Colors.red.shade700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        SizedBox(height: 8),
                        Text(
                          _procesandoFlyer
                              ? 'Procesando flyer...'
                              : _flyerBytesComprimidos != null
                              ? 'Flyer listo. Se subirá al publicar. Tocá para reemplazar.'
                              : _flyerNombre ??
                                    'Usá flyers en formato vertical.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.baloo2(
                            color: ColoresLocales.textoSecundarioOnFondoClaro,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 12),
                TextFormField(
                  controller: _descripcionEventoCtrl,
                  minLines: 3,
                  maxLines: 5,
                  decoration: _inputMultiLinea('Descripción breve del evento'),
                  style: GoogleFonts.baloo2(
                    color: ColoresLocales.textoOnFondoClaro,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Completá la descripción del evento'
                      : null,
                ),
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
                          onTap: () => setState(() => _tipoEvento = tipo),
                        );
                      }).toList(),
                ),
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
                if (!_esSimple) ...[
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
          if (!_esSimple)
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Venta de entradas (opcional)',
                  style: GoogleFonts.baloo2(
                    color: ColoresLocales.textoOnFondoClaro,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Si ya vendés entradas en otra plataforma, podés pegar el link acá para que los usuarios compren directamente.',
                  style: GoogleFonts.baloo2(
                    color: ColoresLocales.textoSecundarioOnFondoClaro,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 10),
                TextFormField(
                  controller: _urlCompraEntradasCtrl,
                  keyboardType: TextInputType.url,
                  style: GoogleFonts.baloo2(
                    color: ColoresLocales.textoOnFondoClaro,
                  ),
                  decoration: _inputUnaLinea(
                    'Pegá acá tu link de PaseShow, Ticketek u otra plataforma',
                  ),
                ),
              ],
            ),
          ),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¿Dónde se realiza el evento?',
                  style: GoogleFonts.baloo2(
                    color: ColoresLocales.textoOnFondoClaro,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 10),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('En mi local'),
                    ),
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('En otro lugar'),
                    ),
                  ],
                  selected: {_esEnLocal},
                  style: ButtonStyle(
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
                  SizedBox(height: 8),
                  Text(
                    'Se usará la ubicación de tu perfil: ${_nombreLocal ?? 'tu local'}',
                    style: GoogleFonts.baloo2(
                      color: ColoresLocales.textoSecundarioOnFondoClaro,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (!_esEnLocal) ...[
                  SizedBox(height: 10),
                  TextFormField(
                    controller: _direccionEventoCtrl,
                    style: GoogleFonts.baloo2(
                      color: ColoresLocales.textoOnFondoClaro,
                    ),
                    decoration: _inputUnaLinea('Dirección del evento'),
                    validator: (v) =>
                        !_esEnLocal && (v == null || v.trim().isEmpty)
                        ? 'Completá la dirección del evento'
                        : null,
                  ),
                  SizedBox(height: 10),
                  _campoUbicacionConAutofiltro(
                    controller: _ciudadEventoCtrl,
                    label: 'Ciudad del evento',
                    opciones: _ciudadesCordobaEvento,
                    validator: (v) =>
                        !_esEnLocal && (v == null || v.trim().isEmpty)
                        ? 'Completá la ciudad del evento'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  _campoUbicacionConAutofiltro(
                    controller: _provinciaEventoCtrl,
                    label: 'Provincia',
                    opciones: _provinciasEvento,
                    validator: (v) =>
                        !_esEnLocal && (v == null || v.trim().isEmpty)
                        ? 'Completá la provincia del evento'
                        : null,
                  ),
                  SizedBox(height: 10),
                  TextFormField(
                    controller: _urlMapsEventoCtrl,
                    style: GoogleFonts.baloo2(
                      color: ColoresLocales.textoOnFondoClaro,
                    ),
                    decoration: _inputUnaLinea('URL de Google Maps'),
                    validator: (v) =>
                        !_esEnLocal && (v == null || v.trim().isEmpty)
                        ? 'Completá la URL de Google Maps'
                        : null,
                  ),
                ],
              ],
            ),
          ),
          if (!_esSimple)
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sistema de ingreso / lista',
                  style: GoogleFonts.baloo2(
                    color: ColoresLocales.textoOnFondoClaro,
                    fontWeight: FontWeight.w800,
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
                SizedBox(height: 8),
                _switchFilaCompacta(
                  label: '¿Permitir squads?',
                  valor: _permiteSquads,
                  onChanged: (v) => setState(() => _permiteSquads = v),
                ),
                SizedBox(height: 6),
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
                    style: GoogleFonts.baloo2(
                      color: ColoresLocales.textoOnFondoClaro,
                    ),
                    decoration: _inputUnaLinea(
                      'Número máximo de personas en lista',
                    ),
                    validator: (v) {
                      if (!_limitarCupoLista) return null;
                      final n = int.tryParse((v ?? '').trim());
                      return (n == null || n <= 0)
                          ? 'Ingresá un cupo válido'
                          : null;
                    },
                  ),
              ],
            ),
          ),
          if (!_esSimple)
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Advertencias extra (opcional)',
                  style: GoogleFonts.baloo2(
                    color: ColoresLocales.textoOnFondoClaro,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8),
                TextFormField(
                  controller: _advertenciasCtrl,
                  minLines: 3,
                  maxLines: 5,
                  style: GoogleFonts.baloo2(
                    color: ColoresLocales.textoOnFondoClaro,
                  ),
                  decoration: _inputMultiLinea(
                    'Ej: código de vestimenta, llevar DNI, comportamiento esperado...',
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Agregá aquí anotaciones extra como código de vestimenta, restricciones, obligatoriedad de llevar documento o cualquier aclaración importante.',
                  style: GoogleFonts.baloo2(
                    color: ColoresLocales.textoSecundarioOnFondoClaro,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
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
                  child: OutlinedButton.icon(
                    onPressed: _agregarPromo,
                    icon: Icon(Icons.add),
                    label: Text(
                      'Agregar promo',
                      style: GoogleFonts.baloo2(fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
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
                'Visibilidad',
                style: GoogleFonts.baloo2(
                  color: ColoresLocales.textoOnFondoClaro,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Elegí tu posicionamiento en cartelera.',
                textAlign: TextAlign.center,
                style: GoogleFonts.baloo2(
                  color: ColoresLocales.textoSecundarioOnFondoClaro,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
              SizedBox(height: 14),
              _buildPanelCuentaCreditosCrear(),
              SizedBox(height: 18),
              Text(
                'Publicar en:',
                textAlign: TextAlign.center,
                style: GoogleFonts.baloo2(
                  color: ColoresLocales.textoOnFondoClaro,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              _botonZonaEstandar(),
              const SizedBox(height: 10),
              Opacity(
                opacity: _localVerificado ? 1 : 0.45,
                child: IgnorePointer(
                  ignoring: !_localVerificado,
                  child: Column(
                    children: [
                      _botonOpcionRecTop(
                        icono: CupertinoIcons.hand_thumbsup_fill,
                        titulo: 'Recomendado Fernecito',
                        costoLabel: '-1 rec.',
                        color: _violetRec,
                        seleccionado:
                            _intencionPublicacion ==
                            _IntencionPublicacion.recFernecito,
                        onTap: () => setState(
                          () => _intencionPublicacion =
                              _IntencionPublicacion.recFernecito,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _botonOpcionRecTop(
                        icono: CupertinoIcons.star_fill,
                        titulo: 'Top Cartelera',
                        costoLabel: '-1 top',
                        color: _amberTop,
                        seleccionado:
                            _intencionPublicacion ==
                            _IntencionPublicacion.topCartelera,
                        onTap: () => setState(
                          () => _intencionPublicacion =
                              _IntencionPublicacion.topCartelera,
                        ),
                      ),
                      SizedBox(height: 10),
                      _botonOpcionRecTop(
                        icono: CupertinoIcons.flame_fill,
                        titulo: 'Top Ultra — Stories',
                        costoLabel: '-1 ultra',
                        color: _rosaUltra,
                        seleccionado:
                            _intencionPublicacion ==
                            _IntencionPublicacion.topUltra,
                        onTap: () => setState(
                          () => _intencionPublicacion =
                              _IntencionPublicacion.topUltra,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!_localVerificado)
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Verificá tu cuenta para desbloquear Recomendado Fernecito, Top Cartelera y Top Ultra.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.baloo2(
                      color: ColoresLocales.textoSecundarioOnFondoClaro,
                      fontSize: 12,
                    ),
                  ),
                ),
              SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _guardando ? null : _onBotonDoradoPublicar,
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size.fromHeight(58),
                    backgroundColor: _mostaza,
                    foregroundColor: ColoresLocales.acentoVioleta,
                    elevation: 4,
                    shadowColor: _mostaza.withOpacity(0.5),
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
                          _textoBotonDoradoPublicar,
                          style: GoogleFonts.baloo2(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                ),
              ),
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
        decoration: BoxDecoration(
          color: ColoresLocales.fondoClaro,
          border: Border(
            top: BorderSide(
              color: ColoresLocales.acentoVioleta.withOpacity(0.12),
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 760),
              child: OutlinedButton.icon(
                onPressed: _guardando ? null : () => _irAPaso(1),
                icon: Icon(CupertinoIcons.chevron_left, size: 18),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size.fromHeight(52),
                  side: BorderSide(
                    color: ColoresLocales.acentoVioleta.withOpacity(0.35),
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
      decoration: BoxDecoration(
        color: ColoresLocales.fondoClaro,
        border: Border(
          top: BorderSide(
            color: ColoresLocales.acentoVioleta.withOpacity(0.12),
          ),
        ),
      ),
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
                      'Siguiente',
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

class _CreditoTextoCrear extends StatelessWidget {
  final IconData icono;
  final String label;
  final int valor;
  final Color color;
  final VoidCallback onTap;

  const _CreditoTextoCrear({
    required this.icono,
    required this.label,
    required this.valor,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 12, color: color),
          const SizedBox(width: 4),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$label ',
                  style: GoogleFonts.baloo2(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                TextSpan(
                  text: '$valor',
                  style: GoogleFonts.baloo2(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: color,
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
          border: selected
              ? null
              : Border.all(
                  color: ColoresLocales.acentoVioleta.withOpacity(0.25),
                ),
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
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: ColoresLocales.superficie,
        border: Border.all(
          color: ColoresLocales.acentoVioleta.withOpacity(0.2),
        ),
      ),
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
    final sinFecha = valor == 'Seleccionar fecha y hora' ||
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
          border: Border.all(
            color: ColoresLocales.acentoVioleta.withOpacity(0.35),
            width: 1.1,
          ),
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
              color: activo ? ColoresLocales.acentoVioleta : ColoresLocales.chipInactivo,
              border: Border.all(
                color: activo
                    ? ColoresLocales.acentoVioleta
                    : ColoresLocales.acentoVioleta.withOpacity(0.3),
                width: 1.5,
              ),
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

class _DashedRoundedRectPainter extends CustomPainter {
  final Color color;

  const _DashedRoundedRectPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(16));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      const dash = 4.5;
      const gap = 4.5;
      while (distance < metric.length) {
        final next = distance + dash;
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedRectPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
