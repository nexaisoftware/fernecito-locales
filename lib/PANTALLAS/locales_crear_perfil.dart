/// Flujo de creacion de perfil local en 6 subpantallas:
/// intro (violeta), pasos 1-4 (blanco), final (violeta).
library;

import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:profile_image_cropper/profile_image_cropper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/colores_onboarding_locales.dart';
import '../core/comprimir_imagen_storage.dart';
import '../core/constants.dart';
import '../core/supabase_client.dart';
import '../widgets/onboarding_locales_ui.dart';
import '../core/auth_gate_locales.dart';
import '../core/servicio_edges_eventos.dart';
import '../core/ubicaciones_data.dart';
import 'locales_home.dart';

const String _assetLogo = ColoresLocales.assetLogoMarca;

class _ImagenLocal {
  final XFile file;
  final Uint8List bytes;

  _ImagenLocal({required this.file, required this.bytes});

  factory _ImagenLocal.fromBytes(Uint8List bytes) => _ImagenLocal(
        file: XFile.fromData(bytes, mimeType: 'image/png', name: 'cropped.png'),
        bytes: bytes,
      );
}

class LocalesCrearPerfil extends StatefulWidget {
  const LocalesCrearPerfil({super.key});

  @override
  State<LocalesCrearPerfil> createState() => _LocalesCrearPerfilState();
}

class _LocalesCrearPerfilState extends State<LocalesCrearPerfil> {
  final TextEditingController _nombreLocal = TextEditingController();
  final TextEditingController _localUsername = TextEditingController();
  final TextEditingController _direccion = TextEditingController();
  final TextEditingController _urlMaps = TextEditingController();
  final TextEditingController _urlWebsite = TextEditingController();
  final TextEditingController _urlTiktok = TextEditingController();
  final TextEditingController _urlInstagram = TextEditingController();
  final TextEditingController _descripcion = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  final List<String> _rubrosDisponibles = <String>[
    'Bar',
    'Boliche',
    'Cerveceria',
    'Restaurante',
    'Pub',
    'Cafe',
    'Eventos',
    'After',
  ];
  final Set<String> _rubrosSeleccionados = <String>{};

  static String get _provinciaDefault => UbicacionesData.provinciaPorDefecto;
  static List<String> get _ciudadesCordoba =>
      UbicacionesData.ciudadesDe(UbicacionesData.provinciaPorDefecto);
  String _provincia = UbicacionesData.provinciaPorDefecto;
  String _ciudad = UbicacionesData.ciudadPorDefecto;

  Timer? _debounceUsername;
  int _paso = 0; // 0=intro, 1-3 pasos, 4=final
  bool _guardando = false;
  bool _verificandoUsername = false;
  bool? _usernameDisponible;
  String _usernameMensaje = '';

  _ImagenLocal? _fotoPerfil;
  _ImagenLocal? _fotoBanner;
  final List<_ImagenLocal?> _fotosLocales = List<_ImagenLocal?>.filled(5, null);

  @override
  void initState() {
    super.initState();
    _localUsername.addListener(_onUsernameChanged);
  }

  @override
  void dispose() {
    _debounceUsername?.cancel();
    _localUsername.removeListener(_onUsernameChanged);
    _nombreLocal.dispose();
    _localUsername.dispose();
    _direccion.dispose();
    _urlMaps.dispose();
    _urlWebsite.dispose();
    _urlTiktok.dispose();
    _urlInstagram.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  void _onUsernameChanged() {
    final raw = _normalizarUsername(_localUsername.text);
    if (_localUsername.text != raw) {
      _localUsername.value = _localUsername.value.copyWith(
        text: raw,
        selection: TextSelection.collapsed(offset: raw.length),
      );
    }

    _debounceUsername?.cancel();
    if (raw.length < 3) {
      setState(() {
        _usernameDisponible = null;
        _usernameMensaje = raw.isEmpty ? '' : 'Minimo 3 caracteres.';
      });
      return;
    }

    _debounceUsername = Timer(const Duration(milliseconds: 550), () async {
      await _verificarUsername(raw);
    });
  }

  String _normalizarUsername(String value) {
    final clean = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    return clean;
  }

  Future<void> _verificarUsername(String username) async {
    final uid = ServicioSupabase().usuarioActual?.id;
    if (uid == null) return;

    setState(() {
      _verificandoUsername = true;
    });

    try {
      final row = await ServicioSupabase()
          .cliente
          .from('perfiles_locales')
          .select('id')
          .eq('local_username', username)
          .neq('id', uid)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _usernameDisponible = row == null;
        _usernameMensaje = row == null ? 'Username disponible.' : 'Ese username ya existe.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _usernameDisponible = null;
        _usernameMensaje = 'No se pudo validar ahora. Probá de nuevo.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _verificandoUsername = false;
        });
      }
    }
  }

  bool get _paso1Valido {
    final nombre = _nombreLocal.text.trim();
    final username = _localUsername.text.trim();
    final direccion = _direccion.text.trim();
    final urlMaps = _urlMaps.text.trim();
    return nombre.isNotEmpty &&
        username.length >= 3 &&
        _usernameDisponible == true &&
        direccion.isNotEmpty &&
        _provincia.isNotEmpty &&
        _ciudad.isNotEmpty &&
        urlMaps.isNotEmpty;
  }

  int get _cantidadFotosLocales =>
      _fotosLocales.where((e) => e != null).length;

  bool get _paso2Valido =>
      _fotoPerfil != null && _cantidadFotosLocales >= 1;

  bool get _paso3Valido => _rubrosSeleccionados.isNotEmpty;

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

  /// URL completa o @usuario → link válido de Instagram / TikTok.
  String? _normalizarPerfilRedSocial(String? raw, {required bool esTiktok}) {
    final v = raw?.trim() ?? '';
    if (v.isEmpty) return null;

    final comoUrl = _normalizarUrlOpcional(v);
    if (comoUrl != null) return comoUrl;

    final handle = v.startsWith('@') ? v.substring(1).trim() : v;
    if (handle.isEmpty || handle.contains(' ') || handle.contains('/')) return null;

    return esTiktok
        ? 'https://www.tiktok.com/@$handle'
        : 'https://www.instagram.com/$handle';
  }

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
    if (mounted) setState(() {});
  }

  bool get _puedeContinuar {
    switch (_paso) {
      case 1:
        return _paso1Valido;
      case 2:
        return _paso2Valido;
      case 3:
        return _paso3Valido;
      default:
        return true;
    }
  }

  Future<_ImagenLocal?> _procesarImagenElegida(
    XFile file, {
    required PerfilImagenStorage perfil,
  }) async {
    final comprimida = await comprimirDesdeXFile(file, perfil: perfil);
    return _ImagenLocal(
      file: XFile.fromData(
        comprimida.bytes,
        mimeType: comprimida.contentType,
        name: 'img${comprimida.pathSuffix}',
      ),
      bytes: comprimida.bytes,
    );
  }

  Future<void> _pickSingleImage({
    required void Function(_ImagenLocal?) onSet,
    required PerfilImagenStorage perfil,
  }) async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final procesada = await _procesarImagenElegida(file, perfil: perfil);
      if (!mounted || procesada == null) return;
      onSet(procesada);
      setState(() {});
    } catch (e) {
      _mostrarError('No se pudo seleccionar imagen: $e');
    }
  }

  Future<void> _pickAndCropProfileImage() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;

      final cropperKey = GlobalKey();
      bool isCropping = false;
      final croppedBytes = await showModalBottomSheet<Uint8List>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.75,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              builder: (_, scrollController) => Container(
                decoration: const BoxDecoration(
                  color: ColoresOnboardingLocales.violeta,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Recortá para que se vea bien en tu avatar',
                              style: GoogleFonts.baloo2(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: ColoresOnboardingLocales.texto,
                              ),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: isCropping ? null : () => Navigator.pop(ctx),
                                child: Text('Cancelar', style: GoogleFonts.baloo2(fontSize: 14, color: Colors.grey)),
                              ),
                              ElevatedButton(
                                onPressed: isCropping
                                    ? null
                                    : () async {
                                        setModalState(() => isCropping = true);
                                        try {
                                          final result = await ProfileImageCropper.crop(imageCropperKey: cropperKey);
                                          if (!ctx.mounted) return;
                                          Navigator.pop(ctx, result);
                                        } catch (_) {
                                          if (ctx.mounted) setModalState(() => isCropping = false);
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: ColoresOnboardingLocales.violetaOscuro,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                                ),
                                child: isCropping
                                    ? SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: ColoresOnboardingLocales.violetaOscuro,
                                        ),
                                      )
                                    : Text(
                                        'Listo',
                                        style: GoogleFonts.baloo2(
                                          fontSize: 15,
                                          color: ColoresOnboardingLocales.violetaOscuro,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        child: ProfileImageCropper(
                          imageCropperKey: cropperKey,
                          image: Image.memory(bytes, fit: BoxFit.contain),
                          aspectRatio: 1,
                          overlayType: OverlayType.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

      if (croppedBytes != null && mounted) {
        final comprimida = await comprimirImagenStorage(
          croppedBytes,
          perfil: PerfilImagenStorage.avatarLocal,
        );
        if (!mounted) return;
        setState(
          () => _fotoPerfil = _ImagenLocal(
            file: XFile.fromData(
              comprimida.bytes,
              mimeType: comprimida.contentType,
              name: 'avatar${comprimida.pathSuffix}',
            ),
            bytes: comprimida.bytes,
          ),
        );
      }
    } catch (e) {
      if (e.toString().contains('multiple_requests') || e.toString().contains('canceled')) {
        _mostrarError(
          'No se pudo recortar. Intentá de nuevo y tocá "Listo" una sola vez. '
          'Si persiste, probá con otra imagen.',
        );
      } else {
        _mostrarError('No se pudo procesar la imagen: $e');
      }
    }
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

  Future<String> _subirImagen({
    required String bucket,
    required String userId,
    required String fileNameBase,
    required _ImagenLocal imagen,
    required int minWidth,
  }) async {
    final comprimida = await comprimirImagenStorage(
      imagen.bytes,
      perfil: _perfilBucket(bucket),
    );
    final path = '$userId/$fileNameBase${comprimida.pathSuffix}';
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

  Future<void> _guardarPerfil({required bool quiereVerificacion}) async {
    final userId = ServicioSupabase().usuarioActual?.id;
    if (userId == null) {
      _mostrarError('No encontramos tu sesion. Volve a iniciar sesion.');
      return;
    }
    if (!_paso1Valido || !_paso2Valido) {
      _mostrarError('Completá los datos obligatorios antes de continuar.');
      return;
    }

    setState(() => _guardando = true);

    try {
      final urlMaps = _normalizarUrlOpcional(_urlMaps.text);
      if (urlMaps == null) {
        _mostrarError(
          'La URL de Google Maps no es válida.\n\n'
          'Tip: podés pegar sin https y la app lo completa automáticamente.',
        );
        return;
      }
      final urlWebsite = _normalizarUrlOpcional(_urlWebsite.text);
      if (_urlWebsite.text.trim().isNotEmpty && urlWebsite == null) {
        _mostrarError('La URL del sitio web no es válida.');
        return;
      }
      final urlTiktok = _normalizarPerfilRedSocial(_urlTiktok.text, esTiktok: true);
      if (_urlTiktok.text.trim().isNotEmpty && urlTiktok == null) {
        _mostrarError(
          'La URL de TikTok no es válida.\n\n'
          'Pegá el link completo de tu perfil (desde Compartir en la app). '
          'No uses solo el nombre de usuario.',
        );
        return;
      }
      final urlInstagram = _normalizarPerfilRedSocial(_urlInstagram.text, esTiktok: false);
      if (_urlInstagram.text.trim().isNotEmpty && urlInstagram == null) {
        _mostrarError(
          'La URL de Instagram no es válida.\n\n'
          'Pegá el link completo de tu perfil (desde Compartir en la app). '
          'No uses solo el @.',
        );
        return;
      }

      final fotoPerfilUrl = await _subirImagen(
        bucket: 'avatars_locales',
        userId: userId,
        fileNameBase: 'foto_perfil',
        imagen: _fotoPerfil!,
        minWidth: 900,
      );

      String? bannerUrl;
      if (_fotoBanner != null) {
        bannerUrl = await _subirImagen(
          bucket: 'banners_locales',
          userId: userId,
          fileNameBase: 'foto_banner',
          imagen: _fotoBanner!,
          minWidth: 1600,
        );
      }

      final List<String?> fotosLocalesUrl = List<String?>.filled(5, null);
      for (var i = 0; i < _fotosLocales.length; i++) {
        final img = _fotosLocales[i];
        if (img == null) continue;
        fotosLocalesUrl[i] = await _subirImagen(
          bucket: 'fotos_locales',
          userId: userId,
          fileNameBase: 'foto_local_${i + 1}',
          imagen: img,
          minWidth: 1400,
        );
      }

      await ServicioEdgesEventos().guardarPerfilLocal(
        perfil: {
          'nombre_local': _nombreLocal.text.trim(),
          'local_username': _localUsername.text.trim(),
          'direccion': _direccion.text.trim(),
          'provincia': _provincia,
          'ciudad': _ciudad,
          'rubro': _rubrosSeleccionados.toList(),
          'foto_perfil_url': fotoPerfilUrl,
          'url_foto_banner': bannerUrl,
          'foto_local_1': fotosLocalesUrl[0],
          'foto_local_2': fotosLocalesUrl[1],
          'foto_local_3': fotosLocalesUrl[2],
          'foto_local_4': fotosLocalesUrl[3],
          'foto_local_5': fotosLocalesUrl[4],
          'url_maps': urlMaps,
          'url_website': urlWebsite,
          'url_tiktok': urlTiktok,
          'url_instagram': urlInstagram,
          'descripcion_local':
              _descripcion.text.trim().isEmpty ? null : _descripcion.text.trim(),
        },
        modo: 'completo',
        solicitarVerificacion: quiereVerificacion,
      );

      if (!mounted) return;
      navigatorKeyLocales.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => LocalesHome()),
        (_) => false,
      );
    } catch (e) {
      _mostrarError(_mensajeErrorGuardar(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  String _mensajeErrorGuardar(Object e) {
    if (e is EdgeException) return e.mensaje;
    return 'No pudimos guardar tu perfil. Revisá los datos e intentá de nuevo.';
  }

  void _mostrarDialogo({
    required String titulo,
    required String mensaje,
    bool esError = true,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ColoresOnboardingLocales.violetaOscuro,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          titulo,
          style: GoogleFonts.baloo2(
            color: esError ? const Color(0xFFFF8A80) : ColoresOnboardingLocales.texto,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          mensaje,
          style: GoogleFonts.baloo2(
            color: ColoresOnboardingLocales.textoSecundario,
            height: 1.35,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Entendido',
              style: GoogleFonts.baloo2(
                color: ColoresOnboardingLocales.mostaza,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarError(String mensaje) =>
      _mostrarDialogo(titulo: 'No se pudo guardar', mensaje: mensaje);

  void _siguientePaso() {
    if (!_puedeContinuar) return;
    setState(() {
      _paso = (_paso + 1).clamp(0, 4);
    });
  }

  void _pasoAnterior() {
    if (_paso == 0) return;
    setState(() => _paso -= 1);
  }

  /// Intro: volver = cerrar sesión (AuthGate redirige al login).
  Future<void> _salirYCerrarSesion() async {
    if (_guardando) return;
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      if (mounted) _mostrarError('No se pudo cerrar sesión: $e');
    }
  }

  Widget _buildProgressBar() {
    if (_paso < 1 || _paso > 3) return const SizedBox.shrink();
    return OnbProgreso(pasoActual: _paso);
  }

  InputDecoration _decorationDropdown(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.baloo2(
          color: ColoresOnboardingLocales.textoSuave,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: ColoresOnboardingLocales.inputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ColoresOnboardingLocales.inputBorde),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ColoresOnboardingLocales.inputBorde),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white, width: 1.5),
        ),
      );

  Widget _introScreen() {
    final frases = <({IconData icon, String text, Color? color})>[
      (
        icon: CupertinoIcons.person_3_fill,
        text: 'Llená tu local con gente real.',
        color: ColoresOnboardingLocales.mostaza,
      ),
      (
        icon: CupertinoIcons.star_circle_fill,
        text: 'Destacate en cartelera y búsquedas.',
        color: const Color(0xFF60A5FA),
      ),
      (
        icon: CupertinoIcons.sparkles,
        text: 'Generá flyers con IA para tus eventos.',
        color: const Color(0xFF4ADE80),
      ),
      (
        icon: CupertinoIcons.qrcode_viewfinder,
        text: 'QR, pases, promos y herramientas para tu RRPP.',
        color: const Color(0xFFF472B6),
      ),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Image.asset(
              _assetLogo,
              height: 88,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                CupertinoIcons.building_2_fill,
                size: 72,
                color: ColoresOnboardingLocales.texto,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Configurá tu local',
            textAlign: TextAlign.center,
            style: GoogleFonts.baloo2(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: ColoresOnboardingLocales.texto,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'En pocos pasos dejás listo el perfil que ven tus clientes en Fernecito.',
            textAlign: TextAlign.center,
            style: GoogleFonts.baloo2(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: ColoresOnboardingLocales.textoSecundario,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 28),
          ...frases.map(
            (f) => OnbBeneficioIntro(
              icono: f.icon,
              texto: f.text,
              colorIcono: f.color,
            ),
          ),
          const SizedBox(height: 20),
          OnbBotonPrimario(
            label: 'Empezar mi perfil',
            icono: CupertinoIcons.arrow_right_circle_fill,
            onPressed: _siguientePaso,
          ),
        ],
      ),
    );
  }

  Widget _pasoBasico() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
      child: OnbSeccionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const OnbTituloSeccion(
              icono: CupertinoIcons.building_2_fill,
              titulo: 'Datos del local',
              subtitulo: 'Nombre, ubicación y link de Maps para que te encuentren.',
            ),
            const SizedBox(height: 16),
            OnbCampo(
              controller: _nombreLocal,
              hint: 'Nombre del local o empresa',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            OnbCampo(controller: _localUsername, hint: 'Username (sin espacios)'),
            const SizedBox(height: 6),
            Row(
              children: [
                if (_verificandoUsername)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                if (_verificandoUsername) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _usernameMensaje,
                    style: GoogleFonts.baloo2(
                      fontSize: 13,
                      color: _usernameDisponible == false
                          ? const Color(0xFFFFB4B4)
                          : ColoresOnboardingLocales.textoSecundario,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OnbCampo(
              controller: _direccion,
              hint: 'Dirección física',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _provincia,
              isExpanded: true,
              dropdownColor: ColoresOnboardingLocales.violetaOscuro,
              decoration: _decorationDropdown('Provincia'),
              style: GoogleFonts.baloo2(
                color: ColoresOnboardingLocales.texto,
                fontWeight: FontWeight.w600,
              ),
              items: const [
                DropdownMenuItem(value: 'Córdoba', child: Text('Córdoba')),
              ],
              onChanged: (v) => setState(() => _provincia = v ?? _provinciaDefault),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _ciudad,
              isExpanded: true,
              dropdownColor: ColoresOnboardingLocales.violetaOscuro,
              decoration: _decorationDropdown('Ciudad'),
              style: GoogleFonts.baloo2(
                color: ColoresOnboardingLocales.texto,
                fontWeight: FontWeight.w600,
              ),
              items: _ciudadesCordoba
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _ciudad = v ?? _ciudadesCordoba.first),
            ),
            const SizedBox(height: 14),
            Text(
              'Google Maps',
              style: GoogleFonts.baloo2(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: ColoresOnboardingLocales.texto,
              ),
            ),
            const SizedBox(height: 8),
            OnbCampo(
              controller: _urlMaps,
              hint: 'Pegá el link de tu local en Maps',
              keyboardType: TextInputType.url,
              suffix: IconButton(
                tooltip: 'Pegar',
                onPressed: () => _pegarTextoEnControlador(_urlMaps),
                icon: const Icon(Icons.paste_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pasoVisual() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
      child: OnbSeccionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const OnbTituloSeccion(
              icono: CupertinoIcons.photo_fill,
              titulo: 'Fotos de tu local',
              subtitulo: 'Avatar circular, banner ancho y al menos 1 foto cuadrada del espacio.',
            ),
            const SizedBox(height: 18),
            Center(
              child: OnbAvatarSlot(
                bytes: _fotoPerfil?.bytes,
                onTap: _pickAndCropProfileImage,
              ),
            ),
            const SizedBox(height: 20),
            OnbBannerSlot(
              bytes: _fotoBanner?.bytes,
              onTap: () => _pickSingleImage(
                perfil: PerfilImagenStorage.bannerLocal,
                onSet: (img) => setState(() => _fotoBanner = img),
              ),
            ),
            const SizedBox(height: 18),
            if (_cantidadFotosLocales < 1)
              Text(
                'Necesitás al menos 1 foto del local',
                style: GoogleFonts.baloo2(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFFFD89B),
                ),
              ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 5,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              itemBuilder: (_, index) => OnbFotoCuadradaSlot(
                indice: index,
                bytes: _fotosLocales[index]?.bytes,
                onTap: () => _pickSingleImage(
                  perfil: PerfilImagenStorage.fotoLocal,
                  onSet: (imgResult) => setState(() => _fotosLocales[index] = imgResult),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pasoExtra() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
      child: OnbSeccionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const OnbTituloSeccion(
              icono: CupertinoIcons.tag_fill,
              titulo: 'Rubro y redes',
              subtitulo: 'Elegí al menos un rubro. El resto es opcional.',
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _rubrosDisponibles.map((rubro) {
                final selected = _rubrosSeleccionados.contains(rubro);
                return OnbChipRubro(
                  label: rubro,
                  seleccionado: selected,
                  onTap: () => setState(() {
                    if (selected) {
                      _rubrosSeleccionados.remove(rubro);
                    } else {
                      _rubrosSeleccionados.add(rubro);
                    }
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            OnbCampo(
              controller: _urlInstagram,
              titulo: 'Instagram (opcional)',
              ayuda: 'Pegá la URL de tu perfil. No alcanza con poner solo el @.',
              hint: 'https://instagram.com/tulocal',
              keyboardType: TextInputType.url,
              suffix: IconButton(
                tooltip: 'Pegar link',
                onPressed: () => _pegarTextoEnControlador(_urlInstagram),
                icon: const Icon(Icons.paste_rounded, color: Colors.white),
              ),
            ),
            const SizedBox(height: 16),
            OnbCampo(
              controller: _urlTiktok,
              titulo: 'TikTok (opcional)',
              ayuda: 'Pegá la URL de tu perfil desde Compartir en TikTok.',
              hint: 'https://tiktok.com/@tulocal',
              keyboardType: TextInputType.url,
              suffix: IconButton(
                tooltip: 'Pegar link',
                onPressed: () => _pegarTextoEnControlador(_urlTiktok),
                icon: const Icon(Icons.paste_rounded, color: Colors.white),
              ),
            ),
            const SizedBox(height: 12),
            OnbCampo(
              controller: _urlWebsite,
              hint: 'Sitio web (opcional)',
              keyboardType: TextInputType.url,
              suffix: IconButton(
                onPressed: () => _pegarTextoEnControlador(_urlWebsite),
                icon: const Icon(Icons.paste_rounded, color: Colors.white),
              ),
            ),
            const SizedBox(height: 12),
            OnbCampo(
              controller: _descripcion,
              hint: 'Descripción breve (opcional)',
              maxLines: 4,
              maxLength: 300,
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pantallaFinal() {
    const beneficios = <({IconData icon, String text, Color color})>[
      (
        icon: CupertinoIcons.checkmark_seal_fill,
        text: 'Insignia verificado — más confianza para tus clientes',
        color: ColoresOnboardingLocales.mostaza,
      ),
      (
        icon: CupertinoIcons.sparkles,
        text: 'Flyers con IA y herramientas premium',
        color: Color(0xFF4ADE80),
      ),
      (
        icon: CupertinoIcons.star_fill,
        text: 'Boost en cartelera y posicionamiento',
        color: Color(0xFF60A5FA),
      ),
      (
        icon: CupertinoIcons.speaker_2_fill,
        text: 'Fernecito Ads para llegar a más gente',
        color: Color(0xFFF472B6),
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            CupertinoIcons.checkmark_circle_fill,
            size: 64,
            color: ColoresOnboardingLocales.texto,
          ),
          const SizedBox(height: 16),
          Text(
            '¡Ya casi está!',
            textAlign: TextAlign.center,
            style: GoogleFonts.baloo2(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: ColoresOnboardingLocales.texto,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Guardá tu perfil ahora. Podés solicitar verificación para desbloquear planes y ventajas.',
            textAlign: TextAlign.center,
            style: GoogleFonts.baloo2(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: ColoresOnboardingLocales.textoSecundario,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 20),
          ...beneficios.map(
            (b) => OnbBeneficioPlan(
              icono: b.icon,
              texto: b.text,
              colorIcono: b.color,
            ),
          ),
          const SizedBox(height: 24),
          OnbBotonMostaza(
            label: 'Guardar y verificar mi local',
            icono: CupertinoIcons.checkmark_seal_fill,
            cargando: _guardando,
            onPressed: _guardando ? null : () => _guardarPerfil(quiereVerificacion: true),
          ),
          const SizedBox(height: 12),
          OnbBotonOutline(
            label: 'Guardar sin verificar',
            icono: CupertinoIcons.arrow_right_circle,
            onPressed: _guardando ? null : () => _guardarPerfil(quiereVerificacion: false),
          ),
        ],
      ),
    );
  }

  Widget _contenidoPaso() {
    switch (_paso) {
      case 0:
        return _introScreen();
      case 1:
        return _pasoBasico();
      case 2:
        return _pasoVisual();
      case 3:
        return _pasoExtra();
      case 4:
      default:
        return _pantallaFinal();
    }
  }

  String _tituloPaso() {
    switch (_paso) {
      case 1:
        return 'Datos del local';
      case 2:
        return 'Fotos';
      case 3:
        return 'Rubro y redes';
      case 4:
        return 'Guardar perfil';
      default:
        return '';
    }
  }

  Widget? _leadingAppBar() {
    if (_paso == 0) {
      return CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: _guardando ? null : _salirYCerrarSesion,
        child: const Icon(
          CupertinoIcons.chevron_back,
          color: ColoresOnboardingLocales.texto,
        ),
      );
    }
    if (_paso > 0) {
      return CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: _guardando ? null : _pasoAnterior,
        child: const Icon(
          CupertinoIcons.chevron_back,
          color: ColoresOnboardingLocales.texto,
        ),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _guardando) return;
        if (_paso == 0) {
          _salirYCerrarSesion();
        } else {
          _pasoAnterior();
        }
      },
      child: Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: ColoresOnboardingLocales.violeta,
      ),
      child: Scaffold(
        backgroundColor: ColoresOnboardingLocales.violeta,
        appBar: AppBar(
          backgroundColor: ColoresOnboardingLocales.violeta,
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: _leadingAppBar(),
          title: _paso > 0 && _paso < 4
              ? Text(
                  _tituloPaso(),
                  style: GoogleFonts.baloo2(
                    color: ColoresOnboardingLocales.texto,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                )
              : null,
        ),
        body: Column(
          children: [
            _buildProgressBar(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: KeyedSubtree(
                  key: ValueKey<int>(_paso),
                  child: _contenidoPaso(),
                ),
              ),
            ),
            if (_paso >= 1 && _paso <= 3)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: OnbBotonPrimario(
                    label: _paso == 3 ? 'Ir al último paso' : 'Continuar',
                    icono: CupertinoIcons.arrow_right,
                    onPressed: _puedeContinuar ? _siguientePaso : null,
                  ),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }
}
