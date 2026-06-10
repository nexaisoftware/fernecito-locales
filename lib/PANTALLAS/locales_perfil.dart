/// Perfil del local (Mi local): mismo formato que pantalla_local_perfil pero editable.
/// Imágenes: ícono lápiz, al tocar abren picker/cámara. Textos y URLs: bottom sheet para editar.
library;

import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
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
import '../widgets/tema_locales_scope.dart';
import '../core/servicio_edges_eventos.dart';
import '../core/supabase_client.dart';
import '../core/navegacion_locales.dart';
import '../core/suscripcion_locales.dart';
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
  bool _localVerificado = false;
  EstadoSuscripcionLocal? _estadoSuscripcion;
  final ImagePicker _picker = ImagePicker();

  /// Versiones para cache-bust: Android/navegador cachean por URL; al subir nueva foto la URL no cambia.
  int _versionAvatar = 0;
  int _versionBanner = 0;
  int _versionFotosLocal = 0;

  static const Color _colorMostaza = ColoresLocales.mostazaBadge;
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

  Future<void> _pegarTextoEnControlador(TextEditingController controller) async {
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
            'calificacion_promedio, calificacion_cantidad, local_verificado, plan_suscripcion',
          )
          .eq('id', uid)
          .maybeSingle();
      final estadoSuscripcion = await SuscripcionLocales.cargarEstadoCompleto(uid);
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
        _localVerificado = row?['local_verificado'] as bool? ?? false;
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

    if (_camposUrl.contains(key)) {
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
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.baloo2(color: ColoresLocales.textoPrincipal)),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
    await ServicioSupabase().cliente.storage.from(bucket).uploadBinary(
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
          } else if (campoDb == 'url_foto_banner') _versionBanner++;
          else if (campoDb.startsWith('foto_local_')) _versionFotosLocal++;
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
        title: Text('Error', style: GoogleFonts.baloo2(color: ColoresLocales.textoPrincipal)),
        content: Text(msg, style: GoogleFonts.baloo2(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text('OK', style: GoogleFonts.baloo2(color: ColoresLocales.acentoVioleta)),
          ),
        ],
      ),
    );
  }

  Future<void> _eliminarCuenta() async {
    final confirmado = await Navigator.of(context, rootNavigator: true).push<bool>(
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
                  style: GoogleFonts.baloo2(color: ColoresLocales.textoOnFondoClaro),
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
            child: Text('Por ahora no', style: GoogleFonts.baloo2(color: ColoresLocales.textoSecundarioOnFondoClaro)),
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
            child: Text('Agregar URL de Maps', style: GoogleFonts.baloo2(color: ColoresLocales.acentoVioleta)),
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
  }) {
    final c = TextEditingController(text: valorActual);
    final inputRadius = maxLines > 1 ? 25.0 : 50.0;
    final violetBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(inputRadius),
      borderSide: BorderSide(color: ColoresLocales.acentoVioleta, width: 1.5),
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: ColoresLocales.superficie,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(titulo, style: GoogleFonts.baloo2(fontSize: 18, fontWeight: FontWeight.w700, color: ColoresLocales.acentoVioleta)),
              SizedBox(height: 12),
              TextField(
                controller: c,
                maxLines: maxLines,
                keyboardType: _esCampoUrlEditable(campoDb) ? TextInputType.url : TextInputType.text,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: GoogleFonts.baloo2(color: ColoresLocales.textoSecundarioOnFondoClaro, fontSize: 14),
                  enabledBorder: violetBorder,
                  focusedBorder: violetBorder,
                  border: violetBorder,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  suffixIcon: _esCampoUrlEditable(campoDb)
                      ? IconButton(
                          tooltip: 'Pegar',
                          onPressed: () => _pegarTextoEnControlador(c),
                          icon: Icon(Icons.paste_rounded),
                          color: ColoresLocales.acentoVioleta,
                        )
                      : null,
                ),
                style: GoogleFonts.baloo2(color: ColoresLocales.textoOnFondoClaro),
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancelar', style: GoogleFonts.baloo2(color: ColoresLocales.textoSecundarioOnFondoClaro))),
                  SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final v = c.text.trim();
                        Navigator.pop(ctx);
                        final ok = await _actualizarCampo(campoDb, v.isEmpty ? null : v);
                        if (ok && campoDb == 'direccion' && v.isNotEmpty) {
                          await _mostrarRecordatorioMaps();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ColoresLocales.acentoVioleta,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                      ),
                      child: Text('Guardar', style: GoogleFonts.baloo2(color: ColoresLocales.chipInactivo, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
                      ? Image.network(urlBust, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _placeholderVisor())
                      : _placeholderVisor(),
                );
              },
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 16,
              child: IconButton(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: Icon(Icons.close, color: ColoresLocales.textoEnBoton, size: 28),
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
              Icon(CupertinoIcons.photo, size: 64, color: ColoresLocales.textoSecundario),
              SizedBox(height: 12),
              Text('Sin foto', style: GoogleFonts.baloo2(fontSize: 16, color: ColoresLocales.textoSecundario)),
            ],
          ),
        ),
      );

  Future<void> _irASuscripciones() async {
    await NavegacionLocales.irASuscripciones();
    if (mounted) await _cargarPerfil();
  }

  String _etiquetaPlanBanner() {
    final estado = _estadoSuscripcion;
    if (estado == null) {
      return _localVerificado ? 'Verificado' : 'Gratuita';
    }
    final plan = SuscripcionLocales.etiquetaPlanUi(
      rawDb: estado.planRaw,
      localVerificado: estado.localVerificado,
    );
    if (!estado.localVerificado) return 'Gratuita';
    return plan;
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    if (_cargando) {
      return Scaffold(
        backgroundColor: ColoresLocales.fondoClaro,
        body: Center(child: CircularProgressIndicator(color: ColoresLocales.acentoVioleta)),
      );
    }

    final size = MediaQuery.of(context).size;
    final screenHeight = size.height;
    final screenWidth = size.width;
    final padding = MediaQuery.of(context).padding;
    final bannerHeight = (screenHeight * 0.48).clamp(340.0, 480.0);
    final isNarrow = screenWidth < 400;
    final avatarSize = isNarrow ? 112.0 : 136.0;
    final horizontalPadding = isNarrow ? 16.0 : 24.0;
    const carouselAlto = 220.0;
    final nombre = _nombreLocal?.trim().isEmpty != false ? 'Mi local' : _nombreLocal!.trim();
    final etiquetaPlan = _etiquetaPlanBanner();

    return Scaffold(
      backgroundColor: ColoresLocales.fondoPrincipal,
      body: CustomScrollView(
        slivers: [
          // Banner con todo el contenido encima (avatar, nombre, reseñas, botones)
          SliverToBoxAdapter(
            child: SizedBox(
              height: bannerHeight,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: ShaderMask(
                      shaderCallback: (b) => LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.55, 0.85, 1.0],
                        colors: [
                          Colors.white,
                          Colors.white.withOpacity(0.65),
                          Colors.white.withOpacity(0.15),
                          Colors.transparent,
                        ],
                      ).createShader(b),
                      blendMode: BlendMode.dstIn,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_urlBanner != null && _urlBanner!.isNotEmpty)
                            Image.network(
                              _urlConCacheBust(_urlBanner, _versionBanner),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _placeholderBanner(),
                            )
                          else
                            _placeholderBanner(),
                          Container(color: Colors.black.withOpacity(0.45)),
                        ],
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(horizontalPadding, padding.top + 12, horizontalPadding, 20),
                      child: Center(
                        child: SingleChildScrollView(
                          physics: BouncingScrollPhysics(),
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
                                        border: Border.all(color: ColoresLocales.acentoVioleta.withOpacity(0.85), width: 3),
                                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 12, offset: Offset(0, 4))],
                                      ),
                                      child: ClipOval(
                                        child: _fotoPerfilUrl != null && _fotoPerfilUrl!.isNotEmpty
                                            ? Image.network(_urlConCacheBust(_fotoPerfilUrl, _versionAvatar), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _avatarPlaceholder(avatarSize))
                                            : _avatarPlaceholder(avatarSize),
                                      ),
                                    ),
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: _BotonLapizMini(onTap: () => _elegirImagen(
                                        bucket: 'avatars_locales',
                                        pathSuffix: 'foto_perfil',
                                        campoDb: 'foto_perfil_url',
                                        minWidth: 900,
                                        onSuccess: () => setState(() {}),
                                      )),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 12),
                              GestureDetector(
                                onTap: () => _showEditSheet(
                                  titulo: 'Editar nombre del local',
                                  valorActual: _nombreLocal ?? '',
                                  hint: 'Nombre del local',
                                  campoDb: 'nombre_local',
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        nombre,
                                        style: GoogleFonts.baloo2(
                                          fontSize: isNarrow ? 20 : 24,
                                          fontWeight: FontWeight.w800,
                                          color: ColoresLocales.textoPrincipal,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      if (_localVerificado) ...[
                                        const SizedBox(width: 8),
                                        Icon(
                                          CupertinoIcons.checkmark_seal_fill,
                                          size: 20,
                                          color: ColoresLocales.acentoVioleta,
                                        ),
                                      ],
                                      const SizedBox(width: 8),
                                      _BotonLapizMini(
                                        onTap: () => _showEditSheet(
                                          titulo: 'Editar nombre del local',
                                          valorActual: _nombreLocal ?? '',
                                          hint: 'Nombre del local',
                                          campoDb: 'nombre_local',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(height: 10),
                              _LineaResenasHero(
                                calificacion: _calificacion,
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const LocalesCalificaciones(),
                                    ),
                                  );
                                },
                              ),
                              SizedBox(height: isNarrow ? 14 : 18),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                padding: EdgeInsets.symmetric(horizontal: isNarrow ? 4 : 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _IconoEnlaceEditable(
                                      icon: CupertinoIcons.location_solid,
                                      size: isNarrow ? 24 : 28,
                                      onTap: () => _showEditSheet(
                                        titulo: 'URL de Google Maps',
                                        valorActual: _urlMaps ?? '',
                                        hint: 'Pegá la URL de Google Maps aquí',
                                        campoDb: 'url_maps',
                                      ),
                                    ),
                                    SizedBox(width: isNarrow ? 22 : 28),
                                    _IconoEnlaceEditable(
                                      icon: FontAwesomeIcons.instagram,
                                      useFontAwesome: true,
                                      size: isNarrow ? 24 : 28,
                                      onTap: () => _showEditSheet(
                                        titulo: 'URL de Instagram',
                                        valorActual: _urlInstagram ?? '',
                                        hint: 'Pegá tu URL de Instagram aquí',
                                        campoDb: 'url_instagram',
                                      ),
                                    ),
                                    SizedBox(width: isNarrow ? 22 : 28),
                                    _IconoEnlaceEditable(
                                      icon: FontAwesomeIcons.tiktok,
                                      useFontAwesome: true,
                                      size: isNarrow ? 24 : 28,
                                      onTap: () => _showEditSheet(
                                        titulo: 'URL de TikTok',
                                        valorActual: _urlTiktok ?? '',
                                        hint: 'Pegá tu URL de TikTok aquí',
                                        campoDb: 'url_tiktok',
                                      ),
                                    ),
                                    SizedBox(width: isNarrow ? 22 : 28),
                                    _IconoEnlaceEditable(
                                      icon: CupertinoIcons.globe,
                                      size: isNarrow ? 24 : 28,
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
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _localVerificado ? _colorMostaza : Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: _localVerificado
                                ? ColoresLocales.acentoVioletaMarca
                                : Colors.white.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _localVerificado
                                  ? CupertinoIcons.checkmark_seal_fill
                                  : CupertinoIcons.person_crop_circle,
                              size: 13,
                              color: _localVerificado
                                  ? ColoresLocales.acentoVioletaMarca
                                  : Colors.white,
                            ),
                            SizedBox(width: 4),
                            Text(
                              etiquetaPlan,
                              style: GoogleFonts.baloo2(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: _localVerificado
                                    ? ColoresLocales.acentoVioletaMarca
                                    : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Info + dirección (grupo estilo iOS)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: ColoresLocales.superficie,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: ColoresLocales.separador.withValues(alpha: 0.55),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Info del lugar',
                                style: GoogleFonts.baloo2(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: ColoresLocales.tituloAcento,
                                ),
                              ),
                              const SizedBox(width: 6),
                              _BotonLapizMini(
                                onTap: _editarDescripcion,
                                size: 13,
                                sobreOscuro: false,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: _editarDescripcion,
                            behavior: HitTestBehavior.opaque,
                            child: Text(
                              _descripcion?.trim().isEmpty != false
                                  ? 'Contanos qué hace especial a tu local…'
                                  : _descripcion!,
                              style: GoogleFonts.baloo2(
                                fontSize: 14,
                                height: 1.45,
                                color: _descripcion?.trim().isEmpty != false
                                    ? ColoresLocales.textoSecundarioOnFondoClaro
                                    : ColoresLocales.textoOnFondoClaro,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      thickness: 0.6,
                      color: ColoresLocales.separador.withValues(alpha: 0.7),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      child: GestureDetector(
                        onTap: _editarDireccion,
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              CupertinoIcons.location_solid,
                              size: 17,
                              color: ColoresLocales.tituloAcento,
                            ),
                            const SizedBox(width: 4),
                            _BotonLapizMini(
                              onTap: _editarDireccion,
                              size: 13,
                              sobreOscuro: false,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _direccion?.trim().isEmpty != false
                                    ? 'Agregar dirección'
                                    : _direccion!,
                                style: GoogleFonts.baloo2(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                  color: _direccion?.trim().isEmpty != false
                                      ? ColoresLocales.textoSecundarioOnFondoClaro
                                      : ColoresLocales.textoOnFondoClaro,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
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
          // Fotos del lugar
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(horizontalPadding, 22, horizontalPadding, 10),
                  child: Text(
                    'Fotos del lugar',
                    style: GoogleFonts.baloo2(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: ColoresLocales.textoSecundarioOnFondoClaro,
                    ),
                  ),
                ),
                SizedBox(
                  height: carouselAlto,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                    itemCount: 5,
                    itemBuilder: (context, index) {
                      final url = _fotosLocal[index];
                      final urlBust = _urlConCacheBust(url, _versionFotosLocal);
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
              padding: EdgeInsets.fromLTRB(horizontalPadding, 28, horizontalPadding, 0),
              child: _ResumenSuscripcionPerfil(
                estado: _estadoSuscripcion,
                localVerificado: _localVerificado,
                onAdministrar: _irASuscripciones,
              ),
            ),
          ),
          // Cambiar contraseña
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(horizontalPadding, 14, horizontalPadding, 0),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.pushNamed(context, '/cambiar_contrasena');
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: ColoresLocales.bordeSuave),
                      color: ColoresLocales.superficie,
                    ),
                    child: Row(
                      children: [
                        Icon(CupertinoIcons.lock_rotation, color: ColoresLocales.tituloAcento, size: 24),
                        SizedBox(width: 14),
                        Text('Cambiar contraseña', style: GoogleFonts.baloo2(fontSize: 16, fontWeight: FontWeight.w700, color: ColoresLocales.textoOnFondoClaro)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Ayuda y soporte
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(horizontalPadding, 14, horizontalPadding, 0),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.pushNamed(context, '/soporte');
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: ColoresLocales.bordeSuave),
                      color: ColoresLocales.superficie,
                    ),
                    child: Row(
                      children: [
                        Icon(CupertinoIcons.question_circle, color: ColoresLocales.tituloAcento, size: 24),
                        SizedBox(width: 14),
                        Text('Ayuda y soporte', style: GoogleFonts.baloo2(fontSize: 16, fontWeight: FontWeight.w700, color: ColoresLocales.textoOnFondoClaro)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Cerrar sesión
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(horizontalPadding, 28, horizontalPadding, 0),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
                    await Supabase.instance.client.auth.signOut();
                    // AuthGate escucha signedOut y navega a LocalesLogin
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: ColoresLocales.bordeSuave),
                      color: ColoresLocales.superficie,
                    ),
                    child: Row(
                      children: [
                        Icon(CupertinoIcons.square_arrow_right, color: ColoresLocales.tituloAcento, size: 24),
                        SizedBox(width: 14),
                        Text('Cerrar sesión', style: GoogleFonts.baloo2(fontSize: 16, fontWeight: FontWeight.w700, color: ColoresLocales.textoOnFondoClaro)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Danger zone: eliminar cuenta (más pequeña, menos llamativa)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 0),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _eliminarCuenta,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.4)),
                      color: Colors.red.withOpacity(0.06),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 18, color: Colors.red.shade700),
                        SizedBox(width: 10),
                        Text('Eliminar cuenta', style: GoogleFonts.baloo2(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.red.shade700)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: MediaQuery.of(context).padding.bottom + 24)),
        ],
      ),
    );
  }

  Widget _placeholderBanner() => Container(
        color: ColoresLocales.fondoSuperficie,
        child: Icon(CupertinoIcons.photo, size: 64, color: ColoresLocales.textoSecundario),
      );

  Widget _avatarPlaceholder(double size) => IconoLocal(size: size * 0.5, color: ColoresLocales.textoSecundario);

  Widget _fotoPlaceholder(double w) => Container(
        width: w,
        color: ColoresLocales.fondoSuperficie,
        child: Icon(
          CupertinoIcons.camera_fill,
          size: 36,
          color: ColoresLocales.acentoVioleta.withValues(alpha: 0.55),
        ),
      );
}

/// Violeta claro unificado para iconos sociales sobre el banner.
const _kVioletaSocialClaro = Color(0xFFC4B5FD);
const _kVioletaSocialGlow = Color(0xFFA78BFA);

/// Reseñas en el hero — emoji + nota en una sola línea.
class _LineaResenasHero extends StatelessWidget {
  final double? calificacion;
  final VoidCallback onTap;

  const _LineaResenasHero({
    required this.calificacion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tieneNota = calificacion != null;
    final texto = tieneNota
        ? '⭐ ${calificacion!.toStringAsFixed(1)}'
        : '⭐';

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Text(
        texto,
        style: GoogleFonts.baloo2(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1.1,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.7),
              blurRadius: 8,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
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
                const Icon(CupertinoIcons.pencil, size: 12, color: Colors.white),
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
        : ColoresLocales.tituloAcento;
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

  const _IconoEnlaceEditable({
    required this.icon,
    required this.onTap,
    this.useFontAwesome = false,
    this.size = 28,
  });

  @override
  State<_IconoEnlaceEditable> createState() => _IconoEnlaceEditableState();
}

class _IconoEnlaceEditableState extends State<_IconoEnlaceEditable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onTap();
          },
          child: AnimatedScale(
            duration: const Duration(milliseconds: 120),
            scale: _pressed ? 0.88 : 1.0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _kVioletaSocialGlow
                        .withValues(alpha: _pressed ? 0.75 : 0.55),
                    blurRadius: _pressed ? 18 : 14,
                    spreadRadius: _pressed ? 2 : 1,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: widget.useFontAwesome
                  ? FaIcon(widget.icon, size: widget.size, color: _kVioletaSocialClaro)
                  : Icon(widget.icon, size: widget.size, color: _kVioletaSocialClaro),
            ),
          ),
        ),
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

  Color _colorPlan(String plan) {
    switch (plan) {
      case 'Premium':
        return ColoresLocales.mostazaDestacado;
      case 'Plus':
        return const Color(0xFF0891B2);
      case 'Pionero':
        return const Color(0xFF16A34A);
      case 'Standard':
        return ColoresLocales.acentoVioleta;
      default:
        return ColoresLocales.textoSecundarioOnFondoClaro;
    }
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final e = estado;
    final plan = e?.tipoPlan ??
        SuscripcionLocales.tipoPlanPago(rawDb: null, localVerificado: localVerificado);
    final planUi = SuscripcionLocales.etiquetaPlanUi(
      rawDb: e?.planRaw,
      localVerificado: localVerificado,
    );
    final colorPlan = _colorPlan(plan);
    final esGratis = !localVerificado || plan == 'Gratuita';

    final lineas = <_LineaResumenPerfil>[];
    if (localVerificado) {
      lineas.add(_LineaResumenPerfil(
        icono: CupertinoIcons.checkmark_seal_fill,
        color: const Color(0xFF059669),
        texto: 'Perfil verificado',
      ));
    } else {
      lineas.add(_LineaResumenPerfil(
        icono: CupertinoIcons.person_crop_circle,
        color: ColoresLocales.textoSecundarioOnFondoClaro,
        texto: 'Sin verificación',
      ));
    }

    if (e?.planActivo == true && e?.fechaVencimiento != null) {
      final dias = e!.diasHastaVencimiento;
      final vence = SuscripcionLocales.formatearFecha(e.fechaVencimiento!);
      lineas.add(_LineaResumenPerfil(
        icono: CupertinoIcons.calendar,
        color: (dias != null && dias <= 7)
            ? ColoresLocales.mostazaDestacado
            : ColoresLocales.acentoVioleta,
        texto: dias != null && dias <= 1
            ? (dias == 0 ? 'Vence hoy · $vence' : 'Vence mañana · $vence')
            : 'Vence el $vence',
      ));
    } else if (e?.fechaVencimiento != null && localVerificado) {
      lineas.add(_LineaResumenPerfil(
        icono: CupertinoIcons.exclamationmark_circle,
        color: const Color(0xFFDC2626),
        texto: 'Plan vencido · ${SuscripcionLocales.formatearFecha(e!.fechaVencimiento!)}',
      ));
    } else if (esGratis) {
      lineas.add(_LineaResumenPerfil(
        icono: CupertinoIcons.sparkles,
        color: ColoresLocales.acentoVioleta,
        texto: 'Sin créditos premium activos',
      ));
    }

    if (e?.tienePagoPendiente == true) {
      final p = e!.pagoPendiente!;
      lineas.add(_LineaResumenPerfil(
        icono: CupertinoIcons.hourglass,
        color: const Color(0xFFD97706),
        texto:
            'Pago en revisión · ${p.planSolicitado ?? ''} (${SuscripcionLocales.etiquetaTipoSolicitud(p.tipoSolicitud)})',
      ));
    } else if (e?.tienePagoAgendado == true) {
      final p = e!.pagoAgendado!;
      final fecha = p.aplicaDesde != null
          ? SuscripcionLocales.formatearFechaCorta(p.aplicaDesde!)
          : 'al vencer';
      lineas.add(_LineaResumenPerfil(
        icono: CupertinoIcons.clock_fill,
        color: const Color(0xFF059669),
        texto: 'Renovación agendada · ${p.planSolicitado ?? ''} · $fecha',
      ));
    } else if (e != null && localVerificado && e.cupos.flyersIa > 0) {
      lineas.add(_LineaResumenPerfil(
        icono: CupertinoIcons.sparkles,
        color: ColoresFeaturesLocales.flyersIa,
        texto:
            '${e.cupos.flyersIa} flyers IA · ${e.cupos.recomendadosFernecito} recomendados',
      ));
    }

    final pendiente = e?.tienePagoPendiente == true;
    final String boton;
    final bool botonPrimario;
    if (esGratis) {
      boton = pendiente ? 'Pago en revisión' : 'Ver planes y verificarme';
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
        color: ColoresLocales.superficie,
        border: Border.all(color: colorPlan.withValues(alpha: 0.28), width: 1.4),
        boxShadow: ColoresLocales.sombrasCard(),
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
                decoration: BoxDecoration(
                  color: colorPlan.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(CupertinoIcons.creditcard_fill, color: colorPlan, size: 20),
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
                        color: ColoresLocales.textoSecundarioOnFondoClaro,
                      ),
                    ),
                    Text(
                      planUi,
                      style: GoogleFonts.baloo2(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                        color: ColoresLocales.textoOnFondoClaro,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
          ...lineas.take(3).map(
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
                        color: ColoresLocales.textoOnFondoClaro.withValues(alpha: 0.92),
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
                    onPressed: pendiente && esGratis ? null : () => onAdministrar(),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: esGratis
                          ? ColoresLocales.mostazaDestacado
                          : ColoresLocales.acentoVioleta,
                      foregroundColor: esGratis
                          ? ColoresLocales.acentoVioletaMarca
                          : ColoresLocales.textoEnBoton,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                    child: Text(
                      boton,
                      style: GoogleFonts.baloo2(fontWeight: FontWeight.w900, fontSize: 14.5),
                    ),
                  )
                : OutlinedButton(
                    onPressed: () => onAdministrar(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ColoresLocales.acentoVioleta,
                      side: BorderSide(
                        color: ColoresLocales.acentoVioleta.withValues(alpha: 0.45),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                    child: Text(
                      boton,
                      style: GoogleFonts.baloo2(fontWeight: FontWeight.w900, fontSize: 14.5),
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

/// Pantalla completa: advertencias + escribir "eliminar" para confirmar.
class _PantallaConfirmarEliminarCuenta extends StatefulWidget {
  const _PantallaConfirmarEliminarCuenta();

  static const String palabraConfirmacion = 'eliminar';

  @override
  State<_PantallaConfirmarEliminarCuenta> createState() => _PantallaConfirmarEliminarCuentaState();
}

class _PantallaConfirmarEliminarCuentaState extends State<_PantallaConfirmarEliminarCuenta> {
  final TextEditingController _confirmacion = TextEditingController();
  bool _puedeEliminar = false;

  @override
  void dispose() {
    _confirmacion.dispose();
    super.dispose();
  }

  void _revisarConfirmacion(String valor) {
    final ok = valor.trim().toLowerCase() == _PantallaConfirmarEliminarCuenta.palabraConfirmacion;
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
            color: ColoresLocales.textoOnFondoClaro,
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
                        border: Border.all(color: Colors.red.withOpacity(0.45)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded, color: rojo, size: 28),
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
                        color: ColoresLocales.textoOnFondoClaro,
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
                                  color: ColoresLocales.textoOnFondoClaro,
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
                        color: ColoresLocales.textoSecundarioOnFondoClaro,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: ColoresLocales.superficie,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _puedeEliminar ? rojo : Colors.red.withOpacity(0.35),
                          width: _puedeEliminar ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Para continuar, escribí la palabra:',
                            style: GoogleFonts.baloo2(
                              color: ColoresLocales.textoOnFondoClaro,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _PantallaConfirmarEliminarCuenta.palabraConfirmacion,
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
                            onSubmitted: _puedeEliminar ? (_) => Navigator.pop(context, true) : null,
                            decoration: InputDecoration(
                              hintText: 'Escribí: eliminar',
                              hintStyle: GoogleFonts.baloo2(
                                color: ColoresLocales.textoSecundarioOnFondoClaro,
                              ),
                              filled: true,
                              fillColor: ColoresLocales.fondoPrincipal.withOpacity(0.6),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: Colors.red.withOpacity(0.4)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: rojo, width: 2),
                              ),
                            ),
                            style: GoogleFonts.baloo2(
                              color: ColoresLocales.textoOnFondoClaro,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (!_puedeEliminar && _confirmacion.text.isNotEmpty) ...[
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
              decoration: BoxDecoration(
                color: ColoresLocales.superficie,
                border: Border(top: BorderSide(color: ColoresLocales.separador.withOpacity(0.5))),
              ),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _puedeEliminar ? () => Navigator.pop(context, true) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: rojo,
                        disabledBackgroundColor: Colors.red.withOpacity(0.22),
                        disabledForegroundColor: Colors.white54,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                          color: ColoresLocales.textoSecundarioOnFondoClaro,
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

