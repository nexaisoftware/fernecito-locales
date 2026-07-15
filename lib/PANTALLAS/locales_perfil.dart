/// Perfil del local (Mi local): mismo formato que pantalla_local_perfil pero editable.
/// Imágenes: ícono lápiz, al tocar abren picker/cámara. Textos y URLs: bottom sheet para editar.
library;

import 'dart:async';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../widgets/icono_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/comprimir_imagen_storage.dart';
import '../core/constants.dart';
import '../widgets/feedback_locales.dart';
import '../core/servicio_edges_eventos.dart';
import '../core/supabase_client.dart';
import '../core/navegacion_locales.dart';
import '../core/suscripcion_locales.dart';
import '../core/programa_pioneros.dart';
import '../widgets/programa_pioneros_ui.dart';
import '../widgets/badge_megusta_local.dart';
import '../widgets/badge_plan_suscripcion.dart';
import 'locales_calificaciones.dart';

class LocalesPerfil extends StatefulWidget {
  const LocalesPerfil({super.key});

  @override
  State<LocalesPerfil> createState() => _LocalesPerfilState();
}

class _LocalesPerfilState extends State<LocalesPerfil> {
  bool _cargando = true;
  String? _nombreLocal;
  String? _fotoPerfilUrl;
  String? _urlBanner;
  String? _descripcion;
  String? _direccion;
  String? _urlMaps;
  String? _urlInstagram;
  String? _urlTiktok;
  String? _urlWebsite;
  final List<String?> _fotosLocal = List<String?>.filled(5, null);
  double? _calificacion;
  int _calificacionCantidad = 0;
  int _cantidadMegusta = 0;
  bool _localVerificado = false;
  String? _ciudad;
  String? _provincia;
  List<String> _rubros = [];
  bool _infoExpandida =
      true; // info del lugar desplegada por defecto (como app usuarios)
  EstadoSuscripcionLocal? _estadoSuscripcion;
  final ImagePicker _picker = ImagePicker();

  static const _rubrosDisponibles = <String>[
    'Bar',
    'Boliche',
    'Cerveceria',
    'Restaurante',
    'Pub',
    'Cafe',
    'Eventos',
    'After',
  ];

  /// Versiones para cache-bust: Android/navegador cachean por URL; al subir nueva foto la URL no cambia.
  int _versionAvatar = 0;
  int _versionBanner = 0;
  int _versionFotosLocal = 0;

  static const Set<String> _camposUrl = {
    'url_maps',
    'url_instagram',
    'url_tiktok',
    'url_website',
    'foto_perfil_url',
    'url_foto_banner',
    'foto_local_1',
    'foto_local_2',
    'foto_local_3',
    'foto_local_4',
    'foto_local_5',
  };

  String _urlConCacheBust(String? url, int version) {
    if (url == null || url.isEmpty) return '';
    return '$url${url.contains('?') ? '&' : '?'}v=$version';
  }

  String? _normalizarUrlOpcional(String? raw) {
    final v = raw?.trim() ?? '';
    if (v.isEmpty) return null;
    final conEsquema = v.contains('://') ? v : 'https://$v';
    final uri = Uri.tryParse(conEsquema);
    if (uri == null) return null;
    final esquemaValido = uri.scheme == 'http' || uri.scheme == 'https';
    if (!esquemaValido || uri.host.isEmpty) return null;
    return uri.toString();
  }

  bool _esCampoUrlEditable(String campoDb) => campoDb.startsWith('url_');

  Future<void> _pegarTextoEnControlador(
    TextEditingController controller,
  ) async {
    final data = await Clipboard.getData('text/plain');
    final pegado = data?.text?.trim() ?? '';
    if (pegado.isEmpty) return;

    final textoActual = controller.text;
    final sel = controller.selection;
    final inicio = sel.start >= 0 ? sel.start : textoActual.length;
    final fin = sel.end >= 0 ? sel.end : textoActual.length;
    final nuevoTexto = textoActual.replaceRange(inicio, fin, pegado);

    controller.value = TextEditingValue(
      text: nuevoTexto,
      selection: TextSelection.collapsed(offset: inicio + pegado.length),
    );
  }

  @override
  void initState() {
    super.initState();
    _cargarPerfil();
  }

  Future<void> _cargarPerfil() async {
    final uid = ServicioSupabase().usuarioActual?.id;
    if (uid == null) {
      setState(() => _cargando = false);
      return;
    }
    try {
      final row = await ServicioSupabase().cliente
          .from('perfiles_locales')
          .select(
            'nombre_local, direccion, foto_perfil_url, url_foto_banner, descripcion_local, '
            'url_maps, url_instagram, url_tiktok, url_website, '
            'foto_local_1, foto_local_2, foto_local_3, foto_local_4, foto_local_5, '
            'calificacion_promedio, calificacion_cantidad, cantidad_megusta, local_verificado, plan_suscripcion, '
            'ciudad, provincia, rubro',
          )
          .eq('id', uid)
          .maybeSingle();
      final estadoSuscripcion = await SuscripcionLocales.cargarEstadoCompleto(
        uid,
      );
      if (!mounted) return;
      setState(() {
        _nombreLocal = row?['nombre_local'] as String?;
        _direccion = row?['direccion'] as String?;
        _fotoPerfilUrl = row?['foto_perfil_url'] as String?;
        _urlBanner = row?['url_foto_banner'] as String?;
        _descripcion = row?['descripcion_local'] as String?;
        _urlMaps = row?['url_maps'] as String?;
        _urlInstagram = row?['url_instagram'] as String?;
        _urlTiktok = row?['url_tiktok'] as String?;
        _urlWebsite = row?['url_website'] as String?;
        for (var i = 0; i < 5; i++) {
          _fotosLocal[i] = row?['foto_local_${i + 1}'] as String?;
        }
        final prom = row?['calificacion_promedio'];
        _calificacion = prom != null ? (prom as num).toDouble() : null;
        final cant = row?['calificacion_cantidad'];
        _calificacionCantidad = cant is int
            ? cant
            : (cant != null ? int.tryParse(cant.toString()) ?? 0 : 0);
        final mg = row?['cantidad_megusta'];
        _cantidadMegusta = mg is int
            ? mg
            : (mg != null ? int.tryParse(mg.toString()) ?? 0 : 0);
        if (_calificacion != null && _calificacion! <= 0) _calificacion = null;
        _localVerificado = row?['local_verificado'] as bool? ?? false;
        _ciudad = row?['ciudad'] as String?;
        _provincia = row?['provincia'] as String?;
        final rubroRaw = row?['rubro'];
        _rubros = rubroRaw is List
            ? rubroRaw
                  .map((r) => r.toString())
                  .where((s) => s.trim().isNotEmpty)
                  .toList()
            : <String>[];
        _estadoSuscripcion = estadoSuscripcion;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _cargando = false);
        _mostrarError('No se pudo cargar el perfil: $e');
      }
    }
  }

  Future<bool> _actualizarCampo(String key, dynamic value) async {
    if (ServicioSupabase().usuarioActual?.id == null) return false;
    dynamic valorFinal = value;

    if (key == 'rubro') {
      if (value is! List) return false;
      valorFinal = value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .take(10)
          .toList();
    } else if (_camposUrl.contains(key)) {
      if (value == null) {
        valorFinal = null;
      } else {
        final normalizada = _normalizarUrlOpcional(value.toString());
        if (normalizada == null) {
          if (mounted) {
            _mostrarError(
              'URL inválida. Usá un formato como https://tu-url.com.\n\n'
              'Tip: podés pegar sin https y la app lo completa automáticamente.',
            );
          }
          return false;
        }
        valorFinal = normalizada;
      }
    }

    try {
      await ServicioEdgesEventos().guardarPerfilLocal(
        perfil: {key: valorFinal},
        modo: 'basico',
      );
      if (!mounted) return true;
      await _cargarPerfil();
      if (!mounted) return true;
      _mostrarExito('Guardado correctamente');
      return true;
    } catch (e) {
      if (mounted) _mostrarError('No se pudo guardar: $e');
      return false;
    }
  }

  void _mostrarExito(String msg) {
    FeedbackLocales.mostrarExito(context, msg);
  }

  PerfilImagenStorage _perfilBucket(String bucket) {
    switch (bucket) {
      case 'avatars_locales':
        return PerfilImagenStorage.avatarLocal;
      case 'banners_locales':
        return PerfilImagenStorage.bannerLocal;
      case 'fotos_locales':
      default:
        return PerfilImagenStorage.fotoLocal;
    }
  }

  Future<String> _subirImagen(
    String bucket,
    String pathBase,
    Uint8List bytes,
  ) async {
    final comprimida = await comprimirImagenStorage(
      bytes,
      perfil: _perfilBucket(bucket),
    );
    final path = pathBase.contains('.')
        ? pathBase
        : '$pathBase${comprimida.pathSuffix}';
    await ServicioSupabase().cliente.storage
        .from(bucket)
        .uploadBinary(
          path,
          comprimida.bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: comprimida.contentType,
          ),
        );
    return ServicioSupabase().cliente.storage.from(bucket).getPublicUrl(path);
  }

  Future<void> _elegirImagen({
    required String bucket,
    required String pathSuffix,
    required String campoDb,
    required int minWidth,
    required VoidCallback onSuccess,
  }) async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 88,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final uid = ServicioSupabase().usuarioActual?.id;
    if (uid == null) return;
    try {
      final path = '$uid/$pathSuffix';
      final url = await _subirImagen(bucket, path, bytes);
      final ok = await _actualizarCampo(campoDb, url);
      if (mounted && ok) {
        setState(() {
          if (campoDb == 'foto_perfil_url') {
            _versionAvatar++;
          } else if (campoDb == 'url_foto_banner')
            _versionBanner++;
          else if (campoDb.startsWith('foto_local_'))
            _versionFotosLocal++;
        });
        onSuccess();
      }
    } catch (e) {
      if (mounted) _mostrarError('No se pudo subir la imagen: $e');
    }
  }

  void _mostrarError(String msg) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: ColoresLocales.fondoSuperficie,
        title: Text(
          'Error',
          style: GoogleFonts.baloo2(color: ColoresLocales.textoPrincipal),
        ),
        content: Text(msg, style: GoogleFonts.baloo2(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(
              'OK',
              style: GoogleFonts.baloo2(color: ColoresLocales.acentoVioleta),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _eliminarCuenta() async {
    final confirmado = await Navigator.of(context, rootNavigator: true)
        .push<bool>(
          MaterialPageRoute<bool>(
            fullscreenDialog: true,
            builder: (_) => const _PantallaConfirmarEliminarCuenta(),
          ),
        );

    if (confirmado != true || !mounted) return;

    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (c) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CupertinoActivityIndicator(),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Eliminando tu cuenta…',
                  style: GoogleFonts.baloo2(
                    color: ColoresLocales.textoOnFondoClaro,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      await ServicioEdgesEventos().eliminarCuentaLocal();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _mostrarError('No se pudo eliminar tu cuenta: $e');
    }
  }

  Future<void> _mostrarRecordatorioMaps() async {
    await showCupertinoDialog(
      context: context,
      builder: (c) => CupertinoAlertDialog(
        title: Text('Ubicación en Google Maps', style: GoogleFonts.baloo2()),
        content: Padding(
          padding: EdgeInsets.only(top: 8.0),
          child: Text(
            'Recordá agregar la URL de tu ubicación exacta en Google Maps. ¡Así los usuarios pueden llegar a tu local con un solo click!',
            style: GoogleFonts.baloo2(),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(c).pop(),
            child: Text(
              'Por ahora no',
              style: GoogleFonts.baloo2(
                color: ColoresLocales.textoSecundarioOnFondoClaro,
              ),
            ),
          ),
          CupertinoDialogAction(
            onPressed: () {
              Navigator.of(c).pop();
              _showEditSheet(
                titulo: 'URL de Google Maps',
                valorActual: _urlMaps ?? '',
                hint: 'Pegá la URL de Google Maps aquí',
                campoDb: 'url_maps',
              );
            },
            child: Text(
              'Agregar URL de Maps',
              style: GoogleFonts.baloo2(color: ColoresLocales.acentoVioleta),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditSheet({
    required String titulo,
    required String valorActual,
    required String hint,
    required String campoDb,
    int maxLines = 1,
    int? maxLength,
  }) {
    final c = TextEditingController(text: valorActual);
    final inputRadius = maxLines > 1 ? 25.0 : 50.0;
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(inputRadius),
      borderSide: BorderSide.none,
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        var guardando = false;
        return StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: ColoresMiLocalPerfil.superficie,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    titulo,
                    style: GoogleFonts.baloo2(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: ColoresMiLocalPerfil.acentoVioleta,
                    ),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: c,
                    enabled: !guardando,
                    maxLines: maxLines,
                    maxLength: maxLength,
                    keyboardType: _esCampoUrlEditable(campoDb)
                        ? TextInputType.url
                        : TextInputType.text,
                    decoration: InputDecoration(
                      hintText: hint,
                      counterText: maxLength != null ? null : '',
                      hintStyle: GoogleFonts.baloo2(
                        color: ColoresMiLocalPerfil.textoSecundario,
                        fontSize: 14,
                      ),
                      filled: true,
                      fillColor: ColoresMiLocalPerfil.rellenoInput,
                      enabledBorder: inputBorder,
                      focusedBorder: inputBorder,
                      border: inputBorder,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      suffixIcon: _esCampoUrlEditable(campoDb)
                          ? IconButton(
                              tooltip: 'Pegar',
                              onPressed: guardando
                                  ? null
                                  : () => _pegarTextoEnControlador(c),
                              icon: Icon(Icons.paste_rounded),
                              color: ColoresMiLocalPerfil.acentoVioleta,
                            )
                          : null,
                    ),
                    style: GoogleFonts.baloo2(
                      color: ColoresMiLocalPerfil.textoPrincipal,
                    ),
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton(
                        onPressed: guardando ? null : () => Navigator.pop(ctx),
                        child: Text(
                          'Cancelar',
                          style: GoogleFonts.baloo2(
                            color: ColoresMiLocalPerfil.textoSecundario,
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: guardando
                              ? null
                              : () async {
                                  setSheetState(() => guardando = true);
                                  final v = c.text.trim();
                                  final ok = await _actualizarCampo(
                                    campoDb,
                                    v.isEmpty ? null : v,
                                  );
                                  if (!ctx.mounted) return;
                                  if (ok) {
                                    Navigator.pop(ctx);
                                    if (campoDb == 'direccion' &&
                                        v.isNotEmpty) {
                                      await _mostrarRecordatorioMaps();
                                    }
                                  } else {
                                    setSheetState(() => guardando = false);
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                ColoresMiLocalPerfil.principalMarca,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(50),
                            ),
                          ),
                          child: guardando
                              ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Guardar',
                                  style: GoogleFonts.baloo2(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _editarBanner() {
    HapticFeedback.lightImpact();
    _elegirImagen(
      bucket: 'banners_locales',
      pathSuffix: 'foto_banner',
      campoDb: 'url_foto_banner',
      minWidth: 1600,
      onSuccess: () => setState(() {}),
    );
  }

  void _editarDescripcion() {
    HapticFeedback.lightImpact();
    _showEditSheet(
      titulo: 'Descripción del local',
      valorActual: _descripcion ?? '',
      hint: 'Contanos qué hace especial a tu local',
      campoDb: 'descripcion_local',
      maxLines: 4,
    );
  }

  String get _ubicacionTextoComputed {
    final c = (_ciudad ?? '').trim();
    final p = (_provincia ?? '').trim();
    if (c.isNotEmpty && p.isNotEmpty) return '$c, $p';
    if (c.isNotEmpty) return c;
    if (p.isNotEmpty) return p;
    return '';
  }

  void _editarRubros() {
    HapticFeedback.lightImpact();
    final seleccion = Set<String>.from(_rubros);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        var guardando = false;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                decoration: BoxDecoration(
                  color: ColoresMiLocalPerfil.superficie,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(22),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Tipo de local',
                      style: GoogleFonts.baloo2(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: ColoresMiLocalPerfil.acentoVioleta,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Elegí uno o más rubros. Así te ven los usuarios en el perfil.',
                      style: GoogleFonts.baloo2(
                        fontSize: 13,
                        color: ColoresMiLocalPerfil.textoSecundario,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final rubro in _rubrosDisponibles)
                          FilterChip(
                            label: Text(
                              rubro,
                              style: GoogleFonts.baloo2(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            selected: seleccion.contains(rubro),
                            onSelected: guardando
                                ? null
                                : (v) {
                                    setSheetState(() {
                                      if (v) {
                                        seleccion.add(rubro);
                                      } else {
                                        seleccion.remove(rubro);
                                      }
                                    });
                                  },
                            selectedColor: ColoresMiLocalPerfil.principalMarca
                                .withValues(alpha: 0.28),
                            checkmarkColor: ColoresMiLocalPerfil.textoPrincipal,
                            backgroundColor:
                                ColoresMiLocalPerfil.superficieElevada,
                            labelStyle: GoogleFonts.baloo2(
                              color: seleccion.contains(rubro)
                                  ? ColoresMiLocalPerfil.textoPrincipal
                                  : ColoresMiLocalPerfil.textoSecundario,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        TextButton(
                          onPressed: guardando
                              ? null
                              : () => Navigator.pop(ctx),
                          child: Text(
                            'Cancelar',
                            style: GoogleFonts.baloo2(
                              color: ColoresMiLocalPerfil.textoSecundario,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: guardando
                                ? null
                                : () async {
                                    setSheetState(() => guardando = true);
                                    final ok = await _actualizarCampo(
                                      'rubro',
                                      seleccion.toList(),
                                    );
                                    if (!ctx.mounted) return;
                                    if (ok) Navigator.pop(ctx);
                                    setSheetState(() => guardando = false);
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  ColoresMiLocalPerfil.principalMarca,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(50),
                              ),
                            ),
                            child: guardando
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    'Guardar',
                                    style: GoogleFonts.baloo2(
                                      fontWeight: FontWeight.w800,
                                    ),
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
  }

  void _editarDireccion() {
    HapticFeedback.lightImpact();
    _showEditSheet(
      titulo: 'Editar dirección',
      valorActual: _direccion ?? '',
      hint: 'Dirección del local',
      campoDb: 'direccion',
    );
  }

  void _showVisorFotos(int initialIndex) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: PageController(initialPage: initialIndex.clamp(0, 4)),
              itemCount: 5,
              itemBuilder: (context, index) {
                final url = _fotosLocal[index];
                final urlBust = _urlConCacheBust(url, _versionFotosLocal);
                return InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4,
                  child: urlBust.isNotEmpty
                      ? Image.network(
                          urlBust,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => _placeholderVisor(),
                        )
                      : _placeholderVisor(),
                );
              },
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 16,
              child: IconButton(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: Icon(
                  Icons.close,
                  color: ColoresLocales.textoEnBoton,
                  size: 28,
                ),
                style: IconButton.styleFrom(backgroundColor: Colors.black45),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholderVisor() => Container(
    color: ColoresLocales.fondoSuperficie,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.photo,
            size: 64,
            color: ColoresLocales.textoSecundario,
          ),
          SizedBox(height: 12),
          Text(
            'Sin foto',
            style: GoogleFonts.baloo2(
              fontSize: 16,
              color: ColoresLocales.textoSecundario,
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _irASuscripciones() async {
    await NavegacionLocales.irASuscripciones();
    if (mounted) await _cargarPerfil();
  }

  String _tipoPlanBanner() {
    final estado = _estadoSuscripcion;
    if (estado == null) {
      return (!_localVerificado) ? 'Gratuita' : 'Standard';
    }
    return estado.tipoPlan;
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return Scaffold(
        backgroundColor: ColoresMiLocalPerfil.fondo,
        body: Center(
          child: CircularProgressIndicator(
            color: ColoresMiLocalPerfil.acentoVioleta,
          ),
        ),
      );
    }

    final size = MediaQuery.of(context).size;
    final screenHeight = size.height;
    final screenWidth = size.width;
    final padding = MediaQuery.of(context).padding;
    // ~15% más alto que el hero base (0.43) para evitar scroll interno en iPhone.
    final bannerHeight = (screenHeight * 0.4945).clamp(368.0, 529.0);
    final isNarrow = screenWidth < 400;
    final avatarSize = isNarrow ? 72.0 : 100.0;
    final horizontalPadding = isNarrow ? 16.0 : 24.0;
    const carouselAlto = 280.0;
    final nombre = _nombreLocal?.trim().isEmpty != false
        ? 'Mi local'
        : _nombreLocal!.trim();
    final tipoPlanBanner = _tipoPlanBanner();
    final esPionero = _estadoSuscripcion?.esPionero ?? false;
    final ubiOk =
        _ubicacionTextoComputed.isNotEmpty ||
        (_direccion ?? '').trim().isNotEmpty ||
        (_urlMaps ?? '').trim().isNotEmpty;
    final igOk = _urlInstagram?.trim().isNotEmpty == true;
    final ttOk = _urlTiktok?.trim().isNotEmpty == true;
    final webOk = _urlWebsite?.trim().isNotEmpty == true;
    final szSocial = isNarrow ? 24.0 : 28.0;
    final sepSocial = SizedBox(width: isNarrow ? 20 : 25);

    return Scaffold(
      backgroundColor: ColoresMiLocalPerfil.fondo,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: ColoresMiLocalPerfil.decoracionFondo,
            ),
          ),
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: bannerHeight,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.0, 0.55, 0.85, 1.0],
                            colors: [
                              Colors.white,
                              Colors.white.withValues(alpha: 0.65),
                              Colors.white.withValues(alpha: 0.15),
                              Colors.transparent,
                            ],
                          ).createShader(bounds),
                          blendMode: BlendMode.dstIn,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (_urlBanner != null && _urlBanner!.isNotEmpty)
                                Image.network(
                                  _urlConCacheBust(_urlBanner, _versionBanner),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _placeholderBanner(),
                                )
                              else if (_fotoPerfilUrl != null &&
                                  _fotoPerfilUrl!.isNotEmpty)
                                Image.network(
                                  _urlConCacheBust(
                                    _fotoPerfilUrl,
                                    _versionAvatar,
                                  ),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _placeholderBanner(),
                                )
                              else
                                _placeholderBanner(),
                              Container(
                                color: Colors.black.withValues(alpha: 0.45),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            padding.top + 14,
                            horizontalPadding,
                            8,
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: () => _elegirImagen(
                                    bucket: 'avatars_locales',
                                    pathSuffix: 'foto_perfil',
                                    campoDb: 'foto_perfil_url',
                                    minWidth: 900,
                                    onSuccess: () => setState(() {}),
                                  ),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Container(
                                        width: avatarSize,
                                        height: avatarSize,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: esPionero
                                                ? ProgramaPioneros.dorado
                                                : ColoresMiLocalPerfil
                                                      .principalMarca
                                                      .withValues(alpha: 0.8),
                                            width: 3,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.4,
                                              ),
                                              blurRadius: 12,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: ClipOval(
                                          child:
                                              _fotoPerfilUrl != null &&
                                                  _fotoPerfilUrl!.isNotEmpty
                                              ? Image.network(
                                                  _urlConCacheBust(
                                                    _fotoPerfilUrl,
                                                    _versionAvatar,
                                                  ),
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      _avatarPlaceholder(
                                                        avatarSize,
                                                      ),
                                                )
                                              : _avatarPlaceholder(avatarSize),
                                        ),
                                      ),
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: _BotonLapizMini(
                                          onTap: () => _elegirImagen(
                                            bucket: 'avatars_locales',
                                            pathSuffix: 'foto_perfil',
                                            campoDb: 'foto_perfil_url',
                                            minWidth: 900,
                                            onSuccess: () => setState(() {}),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 11),
                                _NombreLocalHero(
                                  nombre: nombre,
                                  maxWidth: screenWidth - horizontalPadding * 2,
                                  fontSize: isNarrow ? 21 : 26,
                                  lapizSize: isNarrow ? 12 : 14,
                                  onEditarNombre: () => _showEditSheet(
                                    titulo: 'Editar nombre del local',
                                    valorActual: _nombreLocal ?? '',
                                    hint: 'Nombre del local',
                                    campoDb: 'nombre_local',
                                    maxLength: LimitesMiLocalPerfil
                                        .maxCaracteresNombre,
                                  ),
                                  insignia: esPionero
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: ProgramaPioneros.dorado
                                                .withValues(alpha: 0.16),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                CupertinoIcons
                                                    .checkmark_seal_fill,
                                                size: isNarrow ? 14 : 16,
                                                color: ProgramaPioneros.dorado,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Pionero',
                                                style: GoogleFonts.baloo2(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w800,
                                                  color:
                                                      ProgramaPioneros.dorado,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : (_localVerificado &&
                                            tipoPlanBanner != 'Gratuita')
                                      ? Icon(
                                          CupertinoIcons.checkmark_seal_fill,
                                          size: isNarrow ? 20 : 24,
                                          color: ColoresMiLocalPerfil
                                              .principalMarca,
                                        )
                                      : null,
                                  espacioInsignia: isNarrow ? 4 : 6,
                                  esInsigniaPionero: esPionero,
                                ),
                                const SizedBox(height: 7),
                                _ResenasHeroEstiloUsuarios(
                                  calificacion: _calificacion,
                                  cantidad: _calificacionCantidad,
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const LocalesCalificaciones(),
                                      ),
                                    );
                                  },
                                ),
                                SizedBox(height: isNarrow ? 13 : 16),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isNarrow ? 4 : 8,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _IconoEnlaceEditable(
                                        icon: CupertinoIcons.location_solid,
                                        size: szSocial,
                                        activo: ubiOk,
                                        onTap: () => _showEditSheet(
                                          titulo: 'URL de Google Maps',
                                          valorActual: _urlMaps ?? '',
                                          hint:
                                              'Pegá la URL de Google Maps aquí',
                                          campoDb: 'url_maps',
                                        ),
                                      ),
                                      sepSocial,
                                      _IconoEnlaceEditable(
                                        icon: FontAwesomeIcons.instagram,
                                        useFontAwesome: true,
                                        size: szSocial,
                                        activo: igOk,
                                        onTap: () => _showEditSheet(
                                          titulo: 'URL de Instagram',
                                          valorActual: _urlInstagram ?? '',
                                          hint: 'Pegá tu URL de Instagram aquí',
                                          campoDb: 'url_instagram',
                                        ),
                                      ),
                                      sepSocial,
                                      _IconoEnlaceEditable(
                                        icon: FontAwesomeIcons.tiktok,
                                        useFontAwesome: true,
                                        size: szSocial,
                                        activo: ttOk,
                                        onTap: () => _showEditSheet(
                                          titulo: 'URL de TikTok',
                                          valorActual: _urlTiktok ?? '',
                                          hint: 'Pegá tu URL de TikTok aquí',
                                          campoDb: 'url_tiktok',
                                        ),
                                      ),
                                      sepSocial,
                                      _IconoEnlaceEditable(
                                        icon: CupertinoIcons.globe,
                                        size: szSocial,
                                        activo: webOk,
                                        onTap: () => _showEditSheet(
                                          titulo: 'Sitio web',
                                          valorActual: _urlWebsite ?? '',
                                          hint: 'Pegá la URL de tu web aquí',
                                          campoDb: 'url_website',
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
                      Positioned(
                        left: 14,
                        top: padding.top + 10,
                        child: _AccionEditarBanner(onTap: _editarBanner),
                      ),
                      Positioned(
                        top: padding.top + 10,
                        right: 14,
                        child: GestureDetector(
                          onTap: _irASuscripciones,
                          child: BadgePlanSuscripcion(
                            tipoPlan: tipoPlanBanner,
                            etiquetaLarga: tipoPlanBanner == 'Gratuita',
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: BadgeMegustaLocalLectura(
                            cantidad: _cantidadMegusta,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    6,
                    horizontalPadding,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () =>
                            setState(() => _infoExpandida = !_infoExpandida),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'Info del lugar',
                              style: GoogleFonts.baloo2(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: ColoresMiLocalPerfil.principalMarca,
                              ),
                            ),
                            const SizedBox(width: 6),
                            AnimatedRotation(
                              turns: _infoExpandida ? 0.5 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(
                                CupertinoIcons.chevron_down,
                                size: 20,
                                color: ColoresMiLocalPerfil.principalMarca,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AnimatedCrossFade(
                        firstChild: const SizedBox.shrink(),
                        secondChild: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: _editarDescripcion,
                                      behavior: HitTestBehavior.opaque,
                                      child: Text(
                                        _descripcion?.trim().isNotEmpty == true
                                            ? _descripcion!
                                            : 'El local todavía no escribió una descripción.',
                                        style: GoogleFonts.baloo2(
                                          fontSize: 14,
                                          height: 1.4,
                                          fontStyle:
                                              _descripcion?.trim().isNotEmpty ==
                                                  true
                                              ? FontStyle.normal
                                              : FontStyle.italic,
                                          color:
                                              _descripcion?.trim().isNotEmpty ==
                                                  true
                                              ? ColoresMiLocalPerfil
                                                    .textoPrincipal
                                                    .withValues(alpha: 0.95)
                                              : ColoresMiLocalPerfil
                                                    .textoSecundario,
                                        ),
                                      ),
                                    ),
                                  ),
                                  _BotonLapizMini(
                                    onTap: _editarDescripcion,
                                    size: 13,
                                    sobreOscuro: false,
                                  ),
                                ],
                              ),
                              if (_ubicacionTextoComputed.isNotEmpty ||
                                  (_direccion ?? '').trim().isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      CupertinoIcons.location_solid,
                                      size: 14,
                                      color:
                                          ColoresMiLocalPerfil.principalMarca,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: _editarDireccion,
                                        behavior: HitTestBehavior.opaque,
                                        child: Text(
                                          [
                                            if ((_direccion ?? '')
                                                .trim()
                                                .isNotEmpty)
                                              _direccion!.trim(),
                                            if (_ubicacionTextoComputed
                                                .isNotEmpty)
                                              _ubicacionTextoComputed,
                                          ].join(' · '),
                                          style: GoogleFonts.baloo2(
                                            fontSize: 13,
                                            color: ColoresMiLocalPerfil
                                                .textoSecundario,
                                          ),
                                        ),
                                      ),
                                    ),
                                    _BotonLapizMini(
                                      onTap: _editarDireccion,
                                      size: 13,
                                      sobreOscuro: false,
                                    ),
                                  ],
                                ),
                              ] else ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: _editarDireccion,
                                        child: Text(
                                          'Agregar dirección',
                                          style: GoogleFonts.baloo2(
                                            fontSize: 13,
                                            fontStyle: FontStyle.italic,
                                            color: ColoresMiLocalPerfil
                                                .textoSecundario,
                                          ),
                                        ),
                                      ),
                                    ),
                                    _BotonLapizMini(
                                      onTap: _editarDireccion,
                                      size: 13,
                                      sobreOscuro: false,
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: _editarRubros,
                                      child: Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          if (_rubros.isEmpty)
                                            Text(
                                              'Agregá rubros para que te encuentren mejor',
                                              style: GoogleFonts.baloo2(
                                                fontSize: 12,
                                                fontStyle: FontStyle.italic,
                                                color: ColoresMiLocalPerfil
                                                    .textoSecundario,
                                              ),
                                            )
                                          else
                                            for (final r in _rubros)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 9,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: ColoresMiLocalPerfil
                                                      .principalMarca
                                                      .withValues(alpha: 0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: ColoresMiLocalPerfil
                                                        .principalMarca
                                                        .withValues(
                                                          alpha: 0.35,
                                                        ),
                                                  ),
                                                ),
                                                child: Text(
                                                  r,
                                                  style: GoogleFonts.baloo2(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: ColoresMiLocalPerfil
                                                        .principalMarca,
                                                  ),
                                                ),
                                              ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  _BotonLapizMini(
                                    onTap: _editarRubros,
                                    size: 13,
                                    sobreOscuro: false,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        crossFadeState: _infoExpandida
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        duration: const Duration(milliseconds: 220),
                      ),
                    ],
                  ),
                ),
              ),
              // Fotos del lugar
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        16,
                        horizontalPadding,
                        10,
                      ),
                      child: Text(
                        'Fotos del lugar',
                        style: GoogleFonts.baloo2(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: ColoresMiLocalPerfil.textoPrincipal,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: carouselAlto,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                        ),
                        itemCount: 5,
                        itemBuilder: (context, index) {
                          final url = _fotosLocal[index];
                          final urlBust = _urlConCacheBust(
                            url,
                            _versionFotosLocal,
                          );
                          return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: _FotoLocalCarouselItem(
                              urlBust: urlBust,
                              altoFijo: carouselAlto,
                              onVer: () => _showVisorFotos(index),
                              onEditar: () => _elegirImagen(
                                bucket: 'fotos_locales',
                                pathSuffix: 'foto_local_${index + 1}',
                                campoDb: 'foto_local_${index + 1}',
                                minWidth: 1400,
                                onSuccess: () => setState(() {}),
                              ),
                              placeholder: () => _fotoPlaceholder(130),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              // Resumen de suscripción
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    28,
                    horizontalPadding,
                    0,
                  ),
                  child: _ResumenSuscripcionPerfil(
                    estado: _estadoSuscripcion,
                    localVerificado: _localVerificado,
                    onAdministrar: _irASuscripciones,
                  ),
                ),
              ),
              // Ayuda y soporte
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    14,
                    horizontalPadding,
                    0,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.pushNamed(context, '/soporte');
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        decoration: ColoresLocales.decoracionCardOscuraMiLocal(
                          radius: 16,
                          sinBorde: true,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              CupertinoIcons.question_circle,
                              color: ColoresMiLocalPerfil.principalMarca,
                              size: 24,
                            ),
                            SizedBox(width: 14),
                            Text(
                              'Ayuda y soporte',
                              style: GoogleFonts.baloo2(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: ColoresMiLocalPerfil.textoPrincipal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Zona de peligro: contraseña → eliminar (pequeño) → cerrar sesión (principal)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    28,
                    horizontalPadding,
                    0,
                  ),
                  child: _ZonaPeligroPerfil(
                    onCambiarContrasena: () =>
                        Navigator.pushNamed(context, '/cambiar_contrasena'),
                    onEliminarCuenta: _eliminarCuenta,
                    onCerrarSesion: () async {
                      await Supabase.instance.client.auth.signOut();
                    },
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.of(context).padding.bottom + 24,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _placeholderBanner() => Container(
    color: ColoresMiLocalPerfil.fondoSuperficie,
    child: Icon(
      CupertinoIcons.photo,
      size: 64,
      color: ColoresMiLocalPerfil.textoSecundario,
    ),
  );

  Widget _avatarPlaceholder(double size) =>
      IconoLocal(size: size * 0.5, color: ColoresMiLocalPerfil.textoSecundario);

  Widget _fotoPlaceholder(double w) => Container(
    width: w,
    color: ColoresMiLocalPerfil.fondoSuperficie,
    child: Icon(
      CupertinoIcons.camera_fill,
      size: 36,
      color: ColoresMiLocalPerfil.acentoVioleta.withValues(alpha: 0.55),
    ),
  );
}

/// Reseñas en el hero — mismo formato que app usuarios (número grande + estrellas).
class _ResenasHeroEstiloUsuarios extends StatelessWidget {
  final double? calificacion;
  final int cantidad;
  final VoidCallback onTap;

  const _ResenasHeroEstiloUsuarios({
    required this.calificacion,
    required this.cantidad,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: calificacion == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _EstrellasRatingPerfil(valor: null, size: 16),
                  const SizedBox(height: 5),
                  Text(
                    'Sin calificaciones aún',
                    style: GoogleFonts.baloo2(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: ColoresMiLocalPerfil.textoSecundario,
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    calificacion!.toStringAsFixed(1),
                    style: GoogleFonts.baloo2(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      height: 0.95,
                      letterSpacing: -0.5,
                      color: ColoresMiLocalPerfil.textoPrincipal,
                    ),
                  ),
                  _EstrellasRatingPerfil(valor: calificacion, size: 15),
                  const SizedBox(height: 4),
                  Text(
                    '$cantidad ${cantidad == 1 ? 'calificación' : 'calificaciones'}',
                    style: GoogleFonts.baloo2(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: ColoresMiLocalPerfil.textoSecundario,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _EstrellasRatingPerfil extends StatelessWidget {
  final double? valor;
  final double size;

  const _EstrellasRatingPerfil({required this.valor, this.size = 15});

  @override
  Widget build(BuildContext context) {
    const dorado = Color(0xFFFFC107);
    final apagado = ColoresMiLocalPerfil.textoSecundario.withValues(
      alpha: 0.45,
    );
    final v = valor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final pos = i + 1;
        late IconData icono;
        late Color color;
        if (v == null || v < pos - 0.5) {
          icono = CupertinoIcons.star;
          color = apagado;
        } else if (v >= pos) {
          icono = CupertinoIcons.star_fill;
          color = dorado;
        } else {
          icono = CupertinoIcons.star_lefthalf_fill;
          color = dorado;
        }
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: size * 0.07),
          child: Icon(icono, size: size, color: color),
        );
      }),
    );
  }
}

/// Pill «Editar banner» sobre la imagen de portada.
class _AccionEditarBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _AccionEditarBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.pencil,
                  size: 12,
                  color: Colors.white,
                ),
                const SizedBox(width: 5),
                Text(
                  'Editar banner',
                  style: GoogleFonts.baloo2(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
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

/// Lápiz sobre fotos del carrusel — contenedor blanco + sombra negra.
class _LapizEnFoto extends StatelessWidget {
  final VoidCallback onTap;

  const _LapizEnFoto({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.38),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          CupertinoIcons.pencil,
          size: 15,
          color: ColoresLocales.acentoVioletaMarca,
        ),
      ),
    );
  }
}

/// Nombre multilínea centrado; lápiz e insignia inline tras el último carácter.
class _NombreLocalHero extends StatelessWidget {
  const _NombreLocalHero({
    required this.nombre,
    required this.maxWidth,
    required this.fontSize,
    required this.lapizSize,
    required this.onEditarNombre,
    this.insignia,
    this.esInsigniaPionero = false,
    this.espacioInsignia = 5,
  });

  final String nombre;
  final double maxWidth;
  final double fontSize;
  final double lapizSize;
  final VoidCallback onEditarNombre;
  final Widget? insignia;
  final bool esInsigniaPionero;
  final double espacioInsignia;

  @override
  Widget build(BuildContext context) {
    final textStyle = GoogleFonts.baloo2(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      color: ColoresMiLocalPerfil.textoPrincipal,
      height: 1.2,
    );
    final textDirection = Directionality.of(context);
    final reservaTrailing = FormatoNombreLocalHero.reservaTrailing(
      tieneInsignia: insignia != null,
      esInsigniaPionero: esInsigniaPionero,
      fontSize: fontSize,
    );
    final nombreMostrado = FormatoNombreLocalHero.paraDisplay(
      nombre: nombre,
      maxWidth: maxWidth,
      textStyle: textStyle,
      textDirection: textDirection,
      reservaTrailing: reservaTrailing,
    );

    final trailing = <InlineSpan>[
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.only(left: 2),
          child: _BotonLapizMini(onTap: onEditarNombre, size: lapizSize),
        ),
      ),
      if (insignia != null)
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: EdgeInsets.only(left: espacioInsignia),
            child: insignia!,
          ),
        ),
    ];

    return SizedBox(
      width: maxWidth,
      child: GestureDetector(
        onTap: onEditarNombre,
        behavior: HitTestBehavior.deferToChild,
        child: Text.rich(
          TextSpan(
            style: textStyle,
            children: [
              TextSpan(text: nombreMostrado),
              ...trailing,
            ],
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Lápiz solo (sin contenedor) — legible sobre banner oscuro o fondo claro.
class _BotonLapizMini extends StatelessWidget {
  final VoidCallback onTap;
  final double size;
  final bool sobreOscuro;

  const _BotonLapizMini({
    required this.onTap,
    this.size = 14,
    this.sobreOscuro = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = sobreOscuro
        ? Colors.white
        : ColoresMiLocalPerfil.principalMarca;
    final shadows = sobreOscuro
        ? [
            Shadow(
              color: Colors.black.withValues(alpha: 0.9),
              blurRadius: 8,
              offset: const Offset(0, 1),
            ),
            Shadow(
              color: ColoresLocales.acentoVioleta.withValues(alpha: 0.65),
              blurRadius: 10,
            ),
          ]
        : [
            Shadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ];

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          CupertinoIcons.pencil,
          size: size,
          color: color,
          shadows: shadows,
        ),
      ),
    );
  }
}

/// Icono con glow (como app usuarios) + lápiz mini para editar enlace.
class _IconoEnlaceEditable extends StatefulWidget {
  final IconData icon;
  final bool useFontAwesome;
  final VoidCallback onTap;
  final double size;
  final bool activo;

  const _IconoEnlaceEditable({
    required this.icon,
    required this.onTap,
    this.useFontAwesome = false,
    this.size = 28,
    this.activo = true,
  });

  @override
  State<_IconoEnlaceEditable> createState() => _IconoEnlaceEditableState();
}

class _IconoEnlaceEditableState extends State<_IconoEnlaceEditable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final icono = widget.useFontAwesome
        ? FaIcon(widget.icon, size: widget.size, color: Colors.white)
        : Icon(widget.icon, size: widget.size, color: Colors.white);

    final contenido = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.activo ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: widget.activo
          ? () => setState(() => _pressed = false)
          : null,
      onTapUp: widget.activo ? (_) => setState(() => _pressed = false) : null,
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: widget.activo && _pressed ? 0.88 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: widget.activo
                ? [
                    BoxShadow(
                      color: ColoresMiLocalPerfil.principalMarca.withValues(
                        alpha: _pressed ? 0.65 : 0.45,
                      ),
                      blurRadius: _pressed ? 16 : 12,
                      spreadRadius: _pressed ? 1.5 : 0.8,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Opacity(opacity: widget.activo ? 1 : 0.25, child: icono),
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        contenido,
        Positioned(
          right: -2,
          bottom: -6,
          child: _BotonLapizMini(onTap: widget.onTap, size: 11),
        ),
      ],
    );
  }
}

/// Carrusel: alto fijo, ancho según aspect ratio de cada foto.
class _FotoLocalCarouselItem extends StatefulWidget {
  final String urlBust;
  final double altoFijo;
  final VoidCallback onVer;
  final VoidCallback onEditar;
  final Widget Function() placeholder;

  const _FotoLocalCarouselItem({
    required this.urlBust,
    required this.altoFijo,
    required this.onVer,
    required this.onEditar,
    required this.placeholder,
  });

  @override
  State<_FotoLocalCarouselItem> createState() => _FotoLocalCarouselItemState();
}

class _FotoLocalCarouselItemState extends State<_FotoLocalCarouselItem> {
  double _aspect = 1.0;

  @override
  void initState() {
    super.initState();
    _resolverAspecto();
  }

  @override
  void didUpdateWidget(covariant _FotoLocalCarouselItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urlBust != widget.urlBust) _resolverAspecto();
  }

  Future<void> _resolverAspecto() async {
    if (widget.urlBust.isEmpty) {
      if (mounted) setState(() => _aspect = 1.0);
      return;
    }
    try {
      final provider = NetworkImage(widget.urlBust);
      final stream = provider.resolve(const ImageConfiguration());
      final completer = Completer<void>();
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          final w = info.image.width.toDouble();
          final h = info.image.height.toDouble();
          if (mounted && h > 0) {
            setState(() => _aspect = (w / h).clamp(0.52, 1.25));
          }
          stream.removeListener(listener);
          if (!completer.isCompleted) completer.complete();
        },
        onError: (_, __) {
          stream.removeListener(listener);
          if (!completer.isCompleted) completer.complete();
        },
      );
      stream.addListener(listener);
      await completer.future.timeout(
        const Duration(seconds: 6),
        onTimeout: () {},
      );
    } catch (_) {}
  }

  double get _ancho => (widget.altoFijo * _aspect).clamp(108.0, 200.0);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _ancho,
      height: widget.altoFijo,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: widget.onVer,
            child: Container(
              width: _ancho,
              height: widget.altoFijo,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: widget.urlBust.isNotEmpty
                    ? Image.network(
                        widget.urlBust,
                        width: _ancho,
                        height: widget.altoFijo,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => widget.placeholder(),
                      )
                    : widget.placeholder(),
              ),
            ),
          ),
          Positioned(
            right: 6,
            bottom: 6,
            child: _LapizEnFoto(onTap: widget.onEditar),
          ),
        ],
      ),
    );
  }
}

class _ResumenSuscripcionPerfil extends StatelessWidget {
  final EstadoSuscripcionLocal? estado;
  final bool localVerificado;
  final Future<void> Function() onAdministrar;

  const _ResumenSuscripcionPerfil({
    required this.estado,
    required this.localVerificado,
    required this.onAdministrar,
  });

  Color _colorPlan(String plan) => colorPlanSuscripcionUi(plan);

  @override
  Widget build(BuildContext context) {
    final e = estado;
    final esPionero = e?.esPionero ?? false;
    final plan =
        e?.tipoPlan ??
        SuscripcionLocales.tipoPlanPago(
          rawDb: null,
          localVerificado: localVerificado || esPionero,
        );
    final colorPlan = _colorPlan(plan);
    final esGratis = !localVerificado && !esPionero;

    if (esPionero && e != null) {
      return _buildCardPionero(context, e, colorPlan, esGratis);
    }

    final planUi = e != null
        ? etiquetaSuscripcionCorta(e.tipoPlan)
        : SuscripcionLocales.etiquetaPlanUi(
            rawDb: null,
            localVerificado: localVerificado,
          );

    final lineas = <_LineaResumenPerfil>[];
    if (localVerificado) {
      lineas.add(
        const _LineaResumenPerfil(
          icono: CupertinoIcons.checkmark_seal_fill,
          color: Color(0xFF059669),
          texto: 'Perfil verificado',
        ),
      );
    } else {
      lineas.add(
        _LineaResumenPerfil(
          icono: CupertinoIcons.person_crop_circle,
          color: ColoresMiLocalPerfil.textoSecundario,
          texto: 'Sin verificación',
        ),
      );
    }

    if (e?.planActivo == true && e?.fechaVencimiento != null) {
      final dias = e!.diasHastaVencimiento;
      final vence = SuscripcionLocales.formatearFecha(e.fechaVencimiento!);
      lineas.add(
        _LineaResumenPerfil(
          icono: CupertinoIcons.calendar,
          color: (dias != null && dias <= 7)
              ? ColoresMiLocalPerfil.acentoVioleta
              : ColoresMiLocalPerfil.principalMarca,
          texto: dias != null && dias <= 1
              ? (dias == 0 ? 'Vence hoy · $vence' : 'Vence mañana · $vence')
              : 'Vence el $vence',
        ),
      );
    } else if (e?.fechaVencimiento != null && localVerificado) {
      lineas.add(
        _LineaResumenPerfil(
          icono: CupertinoIcons.exclamationmark_circle,
          color: const Color(0xFFDC2626),
          texto:
              'Plan vencido · ${SuscripcionLocales.formatearFecha(e!.fechaVencimiento!)}',
        ),
      );
    } else if (esGratis) {
      lineas.add(
        _LineaResumenPerfil(
          icono: CupertinoIcons.sparkles,
          color: ColoresMiLocalPerfil.acentoVioleta,
          texto: 'Sin créditos premium activos',
        ),
      );
    }

    if (e?.tienePagoPendiente == true) {
      final p = e!.pagoPendiente!;
      lineas.add(
        _LineaResumenPerfil(
          icono: CupertinoIcons.hourglass,
          color: const Color(0xFFD97706),
          texto:
              'Pago en revisión · ${p.planSolicitado ?? ''} (${SuscripcionLocales.etiquetaTipoSolicitud(p.tipoSolicitud)})',
        ),
      );
    } else if (e?.tienePagoAgendado == true) {
      final p = e!.pagoAgendado!;
      final fecha = p.aplicaDesde != null
          ? SuscripcionLocales.formatearFechaCorta(p.aplicaDesde!)
          : 'al vencer';
      lineas.add(
        _LineaResumenPerfil(
          icono: CupertinoIcons.clock_fill,
          color: const Color(0xFF059669),
          texto: 'Renovación agendada · ${p.planSolicitado ?? ''} · $fecha',
        ),
      );
    } else if (e != null && localVerificado && e.cupos.flyersIa > 0) {
      lineas.add(
        _LineaResumenPerfil(
          icono: CupertinoIcons.sparkles,
          color: ColoresFeaturesLocales.flyersIa,
          texto:
              '${e.cupos.flyersIa} flyers IA · ${e.cupos.recomendadosFernecito} recomendados',
        ),
      );
    }

    final pendiente = e?.tienePagoPendiente == true;
    final String boton;
    final bool botonPrimario;
    if (esGratis) {
      boton = pendiente ? 'Pago en revisión' : 'Administrar suscripción';
      botonPrimario = true;
    } else if (pendiente) {
      boton = 'Ver estado del pago';
      botonPrimario = false;
    } else if (e?.planActivo == true && e!.proximoAVencer) {
      boton = 'Renovar suscripción';
      botonPrimario = true;
    } else if (e?.planActivo != true && localVerificado) {
      boton = 'Renovar suscripción';
      botonPrimario = true;
    } else {
      boton = 'Administrar suscripción';
      botonPrimario = false;
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: ColoresMiLocalPerfil.superficie,
        border: Border.all(
          color: colorPlan.withValues(alpha: 0.28),
          width: 1.4,
        ),
        boxShadow: const [],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                child: Icon(
                  CupertinoIcons.creditcard_fill,
                  color: colorPlan,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mi suscripción',
                      style: GoogleFonts.baloo2(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: ColoresMiLocalPerfil.textoSecundario,
                      ),
                    ),
                    Text(
                      planUi,
                      style: GoogleFonts.baloo2(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                        color: ColoresMiLocalPerfil.textoPrincipal,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: colorPlan.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  SuscripcionLocales.precioMesEtiqueta(
                    esGratis ? 'Standard' : plan,
                  ).replaceAll(' / mes', '/mes'),
                  style: GoogleFonts.baloo2(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: colorPlan,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...lineas
              .take(3)
              .map(
                (l) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    children: [
                      Icon(l.icono, size: 16, color: l.color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l.texto,
                          style: GoogleFonts.baloo2(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: ColoresMiLocalPerfil.textoPrincipal
                                .withValues(alpha: 0.92),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 8),
          SizedBox(
            height: 46,
            child: botonPrimario
                ? ElevatedButton(
                    onPressed: pendiente && esGratis
                        ? null
                        : () => onAdministrar(),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: esGratis
                          ? ColoresMiLocalPerfil.principalMarca
                          : ColoresMiLocalPerfil.acentoVioleta,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                    child: Text(
                      boton,
                      style: GoogleFonts.baloo2(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: () => onAdministrar(),
                    style: TextButton.styleFrom(
                      foregroundColor: ColoresMiLocalPerfil.acentoVioleta,
                      backgroundColor: ColoresMiLocalPerfil.acentoVioleta
                          .withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                    child: Text(
                      boton,
                      style: GoogleFonts.baloo2(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardPionero(
    BuildContext context,
    EstadoSuscripcionLocal e,
    Color colorPlan,
    bool esGratis,
  ) {
    final pendiente = e.tienePagoPendiente;
    final reglas = e.reglasPionero;
    final bloquearRenov = e.pioneroBloqueaRenovacionManual;
    final String boton;
    final bool botonPrimario;

    if (pendiente) {
      boton = 'Ver estado del pago';
      botonPrimario = false;
    } else if (e.pioneroPremiumPagoActivo && e.planActivo && e.proximoAVencer) {
      boton = 'Renovar Premium';
      botonPrimario = true;
    } else if (e.pioneroPremiumPagoActivo) {
      boton = 'Administrar suscripción';
      botonPrimario = false;
    } else if (reglas.permiteUpgradePremium && !pendiente) {
      boton = 'Upgrade a Premium';
      botonPrimario = true;
    } else if (!bloquearRenov && e.planActivo && e.proximoAVencer) {
      boton = 'Renovar suscripción';
      botonPrimario = true;
    } else if (!bloquearRenov &&
        !e.planActivo &&
        (e.localVerificado || e.esPionero)) {
      boton = 'Renovar suscripción';
      botonPrimario = true;
    } else {
      boton = 'Administrar suscripción';
      botonPrimario = false;
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: ColoresMiLocalPerfil.superficie,
        border: Border.all(
          color: ProgramaPioneros.dorado.withValues(alpha: 0.35),
          width: 1.4,
        ),
        boxShadow: const [],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CabeceraResumenPionero(estado: e),
          if (e.pioneroBeneficiosActivo)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: BannerInfoPioneroSuscripcion(reglas: reglas),
            ),
          if (e.tienePagoPendiente) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  CupertinoIcons.hourglass,
                  size: 16,
                  color: Color(0xFFD97706),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pago en revisión · ${e.pagoPendiente!.planSolicitado ?? ''}',
                    style: GoogleFonts.baloo2(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ColoresLocales.textoOnFondoClaro.withValues(
                        alpha: 0.92,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 46,
            child: botonPrimario
                ? ElevatedButton(
                    onPressed: pendiente && esGratis
                        ? null
                        : () => onAdministrar(),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: ColoresMiLocalPerfil.principalMarca,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                    child: Text(
                      boton,
                      style: GoogleFonts.baloo2(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: () => onAdministrar(),
                    style: TextButton.styleFrom(
                      foregroundColor: ColoresLocales.acentoVioleta,
                      backgroundColor: ColoresLocales.acentoVioleta.withValues(
                        alpha: 0.1,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                    child: Text(
                      boton,
                      style: GoogleFonts.baloo2(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LineaResumenPerfil {
  final IconData icono;
  final Color color;
  final String texto;

  const _LineaResumenPerfil({
    required this.icono,
    required this.color,
    required this.texto,
  });
}

/// Zona de peligro al pie del perfil — misma jerarquía que app usuarios.
class _ZonaPeligroPerfil extends StatelessWidget {
  final VoidCallback onCambiarContrasena;
  final VoidCallback onEliminarCuenta;
  final VoidCallback onCerrarSesion;

  const _ZonaPeligroPerfil({
    required this.onCambiarContrasena,
    required this.onEliminarCuenta,
    required this.onCerrarSesion,
  });

  @override
  Widget build(BuildContext context) {
    final rojo = Colors.red.shade700;
    const fondoCerrarSesion = Color(0xFFE8E8E8);
    const textoCerrarSesion = Color(0xFF1A1A1A);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: rojo.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Zona de peligro',
            textAlign: TextAlign.center,
            style: GoogleFonts.baloo2(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: rojo,
            ),
          ),
          const SizedBox(height: 16),
          _BotonGrandeZonaPeligro(
            label: 'Cambiar contraseña',
            onTap: onCambiarContrasena,
            backgroundColor: ColoresMiLocalPerfil.superficieElevada,
            textColor: ColoresMiLocalPerfil.principalMarca,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onEliminarCuenta,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Eliminar cuenta',
              style: GoogleFonts.baloo2(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: rojo.withValues(alpha: 0.7),
                decoration: TextDecoration.underline,
                decorationColor: rojo.withValues(alpha: 0.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _BotonGrandeZonaPeligro(
            label: 'Cerrar sesión',
            onTap: onCerrarSesion,
            backgroundColor: fondoCerrarSesion,
            textColor: textoCerrarSesion,
          ),
        ],
      ),
    );
  }
}

class _BotonGrandeZonaPeligro extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color backgroundColor;
  final Color textColor;

  const _BotonGrandeZonaPeligro({
    required this.label,
    required this.onTap,
    required this.backgroundColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.baloo2(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pantalla completa: advertencias + escribir "eliminar" para confirmar.
class _PantallaConfirmarEliminarCuenta extends StatefulWidget {
  const _PantallaConfirmarEliminarCuenta();

  static const String palabraConfirmacion = 'eliminar';

  @override
  State<_PantallaConfirmarEliminarCuenta> createState() =>
      _PantallaConfirmarEliminarCuentaState();
}

class _PantallaConfirmarEliminarCuentaState
    extends State<_PantallaConfirmarEliminarCuenta> {
  final TextEditingController _confirmacion = TextEditingController();
  bool _puedeEliminar = false;

  @override
  void dispose() {
    _confirmacion.dispose();
    super.dispose();
  }

  void _revisarConfirmacion(String valor) {
    final ok =
        valor.trim().toLowerCase() ==
        _PantallaConfirmarEliminarCuenta.palabraConfirmacion;
    if (ok != _puedeEliminar) setState(() => _puedeEliminar = ok);
  }

  @override
  Widget build(BuildContext context) {
    final rojo = Colors.red.shade700;
    final padding = MediaQuery.paddingOf(context);

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: ColoresLocales.fondoPrincipal,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close),
            color: ColoresMiLocalPerfil.textoPrincipal,
            onPressed: () => Navigator.pop(context, false),
          ),
          title: Text(
            'Eliminar cuenta',
            style: GoogleFonts.baloo2(
              color: rojo,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: rojo,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Esta acción es permanente.\nNo vas a poder recuperar ningún dato.',
                              style: GoogleFonts.baloo2(
                                color: rojo,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Se borrará para siempre:',
                      style: GoogleFonts.baloo2(
                        color: ColoresMiLocalPerfil.textoPrincipal,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...[
                      'Tu perfil y datos del local',
                      'Fotos, banner y flyers generados',
                      'Eventos, promociones y listas',
                      'Staff vinculado y toda la configuración',
                      'Tu cuenta de acceso (email o Google)',
                    ].map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.close, size: 18, color: rojo),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item,
                                style: GoogleFonts.baloo2(
                                  color: ColoresMiLocalPerfil.textoPrincipal,
                                  fontSize: 14,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Fernecito no guarda copias de respaldo. Si eliminás la cuenta, perdés todo el historial de tu local.',
                      style: GoogleFonts.baloo2(
                        color: ColoresMiLocalPerfil.textoSecundario,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _puedeEliminar
                            ? Colors.red.withOpacity(0.08)
                            : ColoresLocales.superficie,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Para continuar, escribí la palabra:',
                            style: GoogleFonts.baloo2(
                              color: ColoresMiLocalPerfil.textoPrincipal,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _PantallaConfirmarEliminarCuenta
                                .palabraConfirmacion,
                            style: GoogleFonts.baloo2(
                              color: rojo,
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _confirmacion,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.done,
                            textCapitalization: TextCapitalization.none,
                            onChanged: _revisarConfirmacion,
                            onSubmitted: _puedeEliminar
                                ? (_) => Navigator.pop(context, true)
                                : null,
                            decoration: InputDecoration(
                              hintText: 'Escribí: eliminar',
                              hintStyle: GoogleFonts.baloo2(
                                color: ColoresMiLocalPerfil.textoSecundario,
                              ),
                              filled: true,
                              fillColor: ColoresLocales.rellenoInput,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            style: GoogleFonts.baloo2(
                              color: ColoresMiLocalPerfil.textoPrincipal,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (!_puedeEliminar &&
                              _confirmacion.text.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'La palabra no coincide. Tiene que ser exactamente "eliminar".',
                              style: GoogleFonts.baloo2(
                                color: rojo,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(20, 12, 20, padding.bottom + 16),
              color: ColoresMiLocalPerfil.superficie,
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _puedeEliminar
                          ? () => Navigator.pop(context, true)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: rojo,
                        disabledBackgroundColor: Colors.red.withOpacity(0.22),
                        disabledForegroundColor: Colors.white54,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _puedeEliminar
                            ? 'Eliminar definitivamente'
                            : 'Escribí "eliminar" para habilitar',
                        style: GoogleFonts.baloo2(
                          color: ColoresLocales.textoPrincipal,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(
                        'Cancelar y volver',
                        style: GoogleFonts.baloo2(
                          color: ColoresMiLocalPerfil.textoSecundario,
                          fontWeight: FontWeight.w700,
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
