/// Asistente IA (chatbot árbol de decisión) para crear el perfil del local.
///
/// Capa ADITIVA sobre `LocalesCrearPerfil`: recolecta EXACTAMENTE los mismos
/// campos que el form y, al confirmar, guarda por el MISMO camino (callback
/// `onCrearPerfil`). El form tradicional queda intacto como fallback.
///
/// - Atajos determinísticos (sin IA): sugerencia de username, url_maps
///   autogenerado, redes por @handle, ciudad por selector.
/// - IA solo en los 2 pasos engorrosos: horarios (parseo) y descripción
///   (redacción marketinera + rubros sugeridos), vía edge `asistente_perfil_local`.
library;

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../core/colores_onboarding_locales.dart';
import '../core/lanzador_externo.dart';
import '../core/servicio_edges_eventos.dart';
import '../core/supabase_client.dart';
import '../core/ubicaciones_data.dart';
import 'recorte_web_safe.dart';

/// Datos recolectados por el chat. Se mapean 1:1 a los campos del form.
class DatosPerfilChat {
  String nombreLocal = '';
  String localUsername = '';
  String direccion = '';
  String provincia = UbicacionesData.provinciaPorDefecto;
  String ciudad = UbicacionesData.ciudadPorDefecto;
  final Set<String> rubros = <String>{};
  Uint8List? fotoPerfilBytes;
  Uint8List? fotoBannerBytes;
  final List<Uint8List?> fotosLocalesBytes = <Uint8List?>[];
  String? urlMaps;
  String? urlWebsite;
  String? urlTiktok; // @handle o URL (el guardado normaliza)
  String? urlInstagram;
  String? descripcion;
  Map<String, dynamic>? horariosJson;
}

/// Abre el chatbot. [onCrearPerfil] guarda por el mismo camino que el form y
/// devuelve `null` si guardó OK o un mensaje de error. [onIrADashboard] navega.
Future<void> mostrarAsistentePerfilSheet(
  BuildContext context, {
  required Future<String?> Function(DatosPerfilChat) onCrearPerfil,
  required VoidCallback onIrADashboard,
  VoidCallback? onVerPlanes,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => _AsistenteChatSheet(
      onCrearPerfil: onCrearPerfil,
      onIrADashboard: onIrADashboard,
      onVerPlanes: onVerPlanes,
    ),
  );
}

// ── Pasos del árbol ────────────────────────────────────────────────────────────
enum _Paso {
  nombre,
  usernameSugerido,
  usernameManual,
  ubicacion,
  direccion,
  horarios,
  horariosPreview,
  descripcion,
  descripcionPreview,
  rubros,
  redes,
  avatar,
  banner,
  fotosLocal,
  resumen,
  guardando,
  felicitacion,
}

const _kRubros = <String>[
  'Bar',
  'Boliche',
  'Cerveceria',
  'Restaurante',
  'Pub',
  'Cafe',
  'Eventos',
  'After',
];

/// Chat dark: fondo negro, IA violeta marca, usuario violeta claro.
const _kFondoChat = Color(0xFF121212);
const _kBurbujaBot = Color(0xFF7C3AED);
const _kBurbujaUsuario = Color(0xFFBB8FCE);
const _kTextoBot = Colors.white;
const _kTextoUsuario = ColoresOnboardingLocales.violetaProfundo;
const _kAcento = Color(0xFF7C3AED);

class _AsistenteChatSheet extends StatefulWidget {
  const _AsistenteChatSheet({
    required this.onCrearPerfil,
    required this.onIrADashboard,
    this.onVerPlanes,
  });

  final Future<String?> Function(DatosPerfilChat) onCrearPerfil;
  final VoidCallback onIrADashboard;
  final VoidCallback? onVerPlanes;

  @override
  State<_AsistenteChatSheet> createState() => _AsistenteChatSheetState();
}

class _AsistenteChatSheetState extends State<_AsistenteChatSheet> {
  final DatosPerfilChat _datos = DatosPerfilChat();
  final List<_Mensaje> _mensajes = <_Mensaje>[];
  final ScrollController _scroll = ScrollController();
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  // Redes (paso único).
  final TextEditingController _ig = TextEditingController();
  final TextEditingController _tk = TextEditingController();
  final TextEditingController _web = TextEditingController();

  _Paso _paso = _Paso.nombre;
  bool _botEscribiendo = false;
  bool _procesando = false; // llamadas IA / guardado

  // Username manual.
  Timer? _debounce;
  bool _verificando = false;
  bool? _disponible;
  List<String> _sugerenciasUser = <String>[];

  // Descripción.
  String _descripcionBorrador = '';
  int _regeneraciones = 0;

  // Horarios (corrección en segunda vuelta).
  String? _horariosTextoAnterior;
  String? _horariosResumenAnterior;
  bool _correccionHorarios = false;

  // Progreso (para la barra superior).
  static const _totalPasos = 12;

  @override
  void initState() {
    super.initState();
    _inputFocus.addListener(_onFocusInput);
    _arrancar();
  }

  void _onFocusInput() {
    if (_inputFocus.hasFocus) {
      Future<void>.delayed(const Duration(milliseconds: 280), () {
        if (mounted) _scrollAlFinal(suave: true);
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    _inputFocus.dispose();
    _ig.dispose();
    _tk.dispose();
    _web.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── Helpers de mensajes ────────────────────────────────────────────────────
  void _scrollAlFinal({bool suave = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (!suave || max < 24) {
        _scroll.jumpTo(max);
        return;
      }
      _scroll.animateTo(
        max,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _pushUsuario(String texto) {
    setState(
      () => _mensajes.add(
        _Mensaje.usuario(_TextoBurbujaRich(texto, esBot: false)),
      ),
    );
    _scrollAlFinal(suave: true);
  }

  void _pushUsuarioWidget(Widget child) {
    setState(() => _mensajes.add(_Mensaje.usuario(child)));
    _scrollAlFinal(suave: true);
  }

  void _pushBotWidget(Widget child, {bool burbuja = true}) {
    setState(
      () => _mensajes.add(
        _Mensaje.bot(child, conBurbuja: burbuja, revelar: false),
      ),
    );
    _scrollAlFinal(suave: true);
  }

  /// Empuja uno o varios mensajes de bot con efecto "escribiendo".
  Future<void> _bot(List<String> textos) async {
    for (final t in textos) {
      setState(() => _botEscribiendo = true);
      _scrollAlFinal();
      await Future<void>.delayed(const Duration(milliseconds: 950));
      if (!mounted) return;
      setState(() {
        _botEscribiendo = false;
        _mensajes.add(
          _Mensaje.bot(_TextoBurbujaRich(t, esBot: true), revelar: true),
        );
      });
      _scrollAlFinal(suave: true);
      if (textos.length > 1) {
        await Future<void>.delayed(const Duration(milliseconds: 70));
      }
    }
  }

  void _irA(_Paso p) {
    setState(() => _paso = p);
    _scrollAlFinal();
  }

  // ── Flujo ───────────────────────────────────────────────────────────────────
  Future<void> _arrancar() async {
    await _bot([
      '¡Hola! 👋 Bienvenido a **Fernecito Locales** — vamos a crear tu perfil y explotar esas ventas 📈💸🚀',
      '¿Cómo se llama tu local? 🏪✨',
    ]);
    if (mounted) _inputFocus.requestFocus();
  }

  String _formatearNombreLocal(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return v;
    final letras = v.replaceAll(RegExp(r'[^a-zA-ZáéíóúÁÉÍÓÚñÑüÜ]'), '');
    if (letras.isNotEmpty && letras == letras.toUpperCase()) return v;
    return v
        .split(RegExp(r'\s+'))
        .map((palabra) {
          if (palabra.isEmpty) return palabra;
          if (palabra.length == 1) return palabra.toUpperCase();
          return '${palabra[0].toUpperCase()}${palabra.substring(1).toLowerCase()}';
        })
        .join(' ');
  }

  Future<void> _onNombre() async {
    final v = _formatearNombreLocal(_input.text);
    if (v.isEmpty) return;
    _datos.nombreLocal = v;
    _input.clear();
    _pushUsuario(v);
    await _bot(['¡Genial! **$v** queda anotado ✨']);
    await _sugerirUsername(v);
  }

  Future<void> _sugerirUsername(String nombre) async {
    setState(() => _procesando = true);
    final libre = await _primerUsernameLibre(_candidatosUsername(nombre));
    if (!mounted) return;
    setState(() => _procesando = false);
    if (libre != null) {
      _datos.localUsername = libre;
      await _bot([
        'Tengo este username disponible para vos: **@$libre** — ¿querés usarlo?',
      ]);
      _irA(_Paso.usernameSugerido);
    } else {
      await _bot(['Elegí tu **nombre de usuario** (sin espacios) ✏️']);
      _prepararUsernameManual();
    }
  }

  void _prepararUsernameManual() {
    _input.clear();
    setState(() {
      _disponible = null;
      _verificando = false;
      _sugerenciasUser = _candidatosUsername(
        _datos.nombreLocal,
      ).take(3).toList();
    });
    _irA(_Paso.usernameManual);
    _inputFocus.requestFocus();
  }

  Future<void> _confirmarUsername(String u) async {
    _datos.localUsername = u;
    _input.clear();
    _pushUsuario('@$u');
    await _bot([
      '¡Perfecto, **@$u**! 🙌 Ahora elegí **provincia y ciudad** 👇',
    ]);
    _irA(_Paso.ubicacion);
  }

  Future<void> _onUbicacionConfirmada(String provincia, String ciudad) async {
    _datos.provincia = provincia;
    _datos.ciudad = ciudad;
    _pushUsuarioWidget(
      _ChipInfo(
        icon: CupertinoIcons.placemark_fill,
        texto: '$ciudad, $provincia',
      ),
    );
    await _bot([
      '¡Buenísimo! Estás en **$ciudad**, $provincia 📍',
      '¿Cuál es tu **dirección**? (calle y número)',
    ]);
    _irA(_Paso.direccion);
    _inputFocus.requestFocus();
  }

  Future<void> _onDireccion() async {
    final v = _input.text.trim();
    if (v.isEmpty) return;
    _datos.direccion = v;
    _datos.urlMaps = _mapsUrl(v, _datos.ciudad, _datos.provincia);
    _input.clear();
    _pushUsuario(v);
    _pushBotWidget(_MapsLinkPreview(url: _datos.urlMaps!, etiqueta: v));
    await _bot([
      'Revisá el **link de Maps** de arriba para confirmar que la ubicación está bien 📍',
    ]);
    await _irAPedirHorarios();
  }

  Future<void> _sinDireccionOrganizador() async {
    _datos.direccion = 'Organizador de eventos (sin local fijo)';
    _datos.urlMaps = _mapsUrlCiudad(_datos.ciudad, _datos.provincia);
    _pushUsuarioWidget(
      _ChipInfo(icon: CupertinoIcons.calendar, texto: 'Organizador de eventos'),
    );
    await _bot(['¡Entendido! 🎉 Seguimos sin dirección fija.']);
    await _irAPedirHorarios();
  }

  Future<void> _irAPedirHorarios() async {
    await _bot([
      '¡Excelente! 🕐 Contame tus **horarios** en criollo — ej: lun a vie de 5 a 8 pm y fines de semana de 6 pm a 2 am',
    ]);
    _irA(_Paso.horarios);
    _inputFocus.requestFocus();
  }

  Future<void> _confirmarHorarios() async {
    _pushUsuario('Sí, perfectos 👍');
    await _pedirDescripcion();
  }

  Future<void> _onHorarios() async {
    final v = _input.text.trim();
    if (v.length < 3) return;
    _input.clear();
    _pushUsuario(v);
    setState(() => _procesando = true);
    await _bot(['Dejame ordenar eso ✨']);
    try {
      final contexto =
          _correccionHorarios &&
              (_horariosTextoAnterior?.isNotEmpty == true ||
                  _horariosResumenAnterior?.isNotEmpty == true)
          ? <String, dynamic>{
              'es_correccion': true,
              'texto_anterior': _horariosTextoAnterior ?? '',
              'resumen_anterior': _horariosResumenAnterior ?? '',
            }
          : null;
      final res = await ServicioEdgesEventos().asistentePerfilLocal(
        intent: 'horarios',
        texto: v,
        contexto: contexto,
      );
      if (!mounted) return;
      final entendido = res['entendido'] == true;
      final horarios = res['horarios_json'];
      final resumen = (res['resumen'] ?? '').toString();
      if (!entendido ||
          horarios is! Map ||
          horarios.isEmpty ||
          resumen.isEmpty) {
        setState(() => _procesando = false);
        await _bot([
          'No me quedó claro 😅 ¿Lo reescribís? O tocá "No tengo horario fijo".',
        ]);
        _inputFocus.requestFocus();
        return;
      }
      _datos.horariosJson = Map<String, dynamic>.from(horarios);
      _horariosTextoAnterior = v;
      _horariosResumenAnterior = resumen;
      _correccionHorarios = false;
      setState(() => _procesando = false);
      _pushBotWidget(_HorariosPreview(resumen: resumen));
      await _bot(['¿Están bien tus horarios?']);
      _irA(_Paso.horariosPreview);
    } catch (e) {
      if (!mounted) return;
      setState(() => _procesando = false);
      await _bot([_msgError(e)]);
      _inputFocus.requestFocus();
    }
  }

  Future<void> _sinHorarios() async {
    _datos.horariosJson = null;
    _pushUsuarioWidget(
      _ChipInfo(icon: CupertinoIcons.clock, texto: 'Sin horario fijo'),
    );
    await _pedirDescripcion();
  }

  Future<void> _pedirDescripcion() async {
    await _bot([
      '¡Contanos sobre tu local! 📝 Una buena descripción ayuda a que te encuentren los **clientes** y nuestra **IA** 🔍',
      'Ideas para escribir: qué vendés, tu trago o comida **estrella**, qué te hace **único**, si hacés **eventos** o sos de tener **promos** 🍻✨',
    ]);
    setState(() => _regeneraciones = 0);
    _input.clear();
    _irA(_Paso.descripcion);
    _inputFocus.requestFocus();
  }

  Future<void> _usarDescripcionTalCual() async {
    final v = _input.text.trim();
    if (v.length < 8) return;
    _datos.descripcion = v;
    _input.clear();
    _pushUsuario(v);
    await _bot(['Perfecto, la usamos tal cual 👌']);
    await _pedirRubros(iaSugirio: false);
  }

  Future<void> _mejorarDescripcion({required bool desdeBorrador}) async {
    final v = desdeBorrador ? _descripcionBorrador : _input.text.trim();
    if (v.length < 8) return;
    if (!desdeBorrador) {
      _descripcionBorrador = v;
      _input.clear();
      _pushUsuario(v);
    }
    setState(() {
      _procesando = true;
      _regeneraciones++;
    });
    await _bot(['Puliéndola con IA ✨']);
    try {
      final res = await ServicioEdgesEventos().asistentePerfilLocal(
        intent: 'descripcion',
        texto: v,
        contexto: {
          'nombre_local': _datos.nombreLocal,
          'rubros': _datos.rubros.toList(),
        },
      );
      if (!mounted) return;
      final desc = (res['descripcion'] ?? '').toString();
      final rubros =
          (res['rubros'] as List?)?.map((e) => e.toString()).toList() ??
          const [];
      setState(() => _procesando = false);
      if (desc.length < 12) {
        await _bot([
          'No pude mejorarla ahora 😕 Podés usar tu texto tal cual o reintentar.',
        ]);
        _irA(_Paso.descripcion);
        return;
      }
      _datos.descripcion = desc;
      _datos.rubros
        ..clear()
        ..addAll(rubros.where(_kRubros.contains));
      _pushBotWidget(_DescripcionPreview(texto: desc));
      _irA(_Paso.descripcionPreview);
    } catch (e) {
      if (!mounted) return;
      setState(() => _procesando = false);
      await _bot([
        _msgError(e),
        'Podés usar tu texto tal cual mientras tanto.',
      ]);
      _irA(_Paso.descripcion);
    }
  }

  Future<void> _confirmarDescripcion() async {
    final desc = (_datos.descripcion ?? '').trim();
    if (desc.isNotEmpty) {
      _pushUsuario(desc);
    }
    await _bot(['Buenísimo 🙌']);
    await _pedirRubros(iaSugirio: _datos.rubros.isNotEmpty);
  }

  Future<void> _pedirRubros({required bool iaSugirio}) async {
    await _bot([
      iaSugirio
          ? 'Según tu local, te **pre-seleccioné** estos rubros. Ajustá lo que quieras 👇'
          : 'Elegí los **rubros** de tu local — ayudan a que te encuentren 🎯',
    ]);
    _irA(_Paso.rubros);
  }

  Future<void> _confirmarRubros() async {
    if (_datos.rubros.isEmpty) return;
    _pushUsuarioWidget(
      _ChipInfo(
        icon: CupertinoIcons.tag_fill,
        texto: _datos.rubros.join(' · '),
      ),
    );
    await _bot([
      '¿Tenés **redes sociales**? Sumalas para que te sigan (todo opcional) 📱',
    ]);
    _irA(_Paso.redes);
  }

  Future<void> _confirmarRedes() async {
    final ig = _ig.text.trim();
    final tk = _tk.text.trim();
    final web = _web.text.trim();
    _datos.urlInstagram = ig.isEmpty ? null : ig;
    _datos.urlTiktok = tk.isEmpty ? null : tk;
    _datos.urlWebsite = web.isEmpty ? null : web;
    final partes = <String>[
      if (ig.isNotEmpty) 'IG',
      if (tk.isNotEmpty) 'TikTok',
      if (web.isNotEmpty) 'Web',
    ];
    _pushUsuarioWidget(
      _ChipInfo(
        icon: CupertinoIcons.link,
        texto: partes.isEmpty ? 'Sin redes por ahora' : partes.join(' · '),
      ),
    );
    await _bot([
      '¡Ya casi! 📸 Primero el **logo o foto de perfil** de tu negocio.',
    ]);
    _irA(_Paso.avatar);
  }

  Future<void> _confirmarAvatar() async {
    if (_datos.fotoPerfilBytes == null) return;
    _pushUsuarioWidget(_MiniAvatar(bytes: _datos.fotoPerfilBytes!));
    await _bot([
      '¡Quedó genial! 🖼️ Ahora un **banner** (opcional): foto vertical del local, una fiesta o algo que te represente.',
    ]);
    _irA(_Paso.banner);
  }

  Future<void> _confirmarBanner({required bool omitir}) async {
    if (omitir) {
      _datos.fotoBannerBytes = null;
      _pushUsuarioWidget(
        _ChipInfo(icon: CupertinoIcons.photo, texto: 'Banner: lo hago después'),
      );
    } else {
      if (_datos.fotoBannerBytes == null) return;
      _pushUsuarioWidget(_MiniBanner(bytes: _datos.fotoBannerBytes!));
    }
    await _bot([
      'Última tanda: fotos de tu local 🏙️',
      'Subí de 1 a 10 fotos (mínimo 1). Después podés sumar más o cambiarlas desde Mi local.',
    ]);
    _irA(_Paso.fotosLocal);
  }

  Future<void> _confirmarFotosLocal() async {
    if (_datos.fotosLocalesBytes.where((e) => e != null).isEmpty) return;
    final n = _datos.fotosLocalesBytes.where((e) => e != null).length;
    _pushUsuarioWidget(
      _ChipInfo(
        icon: CupertinoIcons.photo_on_rectangle,
        texto: '$n foto(s) del local',
      ),
    );
    await _bot([
      '¡Excelente! **${_datos.nombreLocal}** está completo 🎉 Revisá el resumen y creá tu perfil 👇',
    ]);
    _irA(_Paso.resumen);
  }

  Future<void> _crearPerfil() async {
    setState(() {
      _paso = _Paso.guardando;
      _procesando = true;
    });
    _pushBotWidget(const _CargandoBurbuja(texto: 'Creando tu perfil…'));
    final error = await widget.onCrearPerfil(_datos);
    if (!mounted) return;
    setState(() => _procesando = false);
    if (error != null) {
      await _bot(['Ups: $error']);
      _irA(_Paso.resumen);
      return;
    }
    await _bot([
      '🎉 ¡Listo! Tu local ya está en Fernecito.',
      'Con un plan desbloqueás verificación, más visibilidad en cartelera, flyers con IA y herramientas para vender más. Si sos de los primeros, podés sumarte al Programa Pioneros con beneficios exclusivos 💜',
    ]);
    _irA(_Paso.felicitacion);
  }

  // ── Utilidades ──────────────────────────────────────────────────────────────
  String _msgError(Object e) => e is EdgeException
      ? e.mensaje
      : 'Algo falló. Probá de nuevo en un momento.';

  String _mapsUrl(String direccion, String ciudad, String provincia) {
    final q = Uri.encodeComponent('$direccion, $ciudad, $provincia');
    return 'https://www.google.com/maps/search/?api=1&query=$q';
  }

  String _mapsUrlCiudad(String ciudad, String provincia) {
    final q = Uri.encodeComponent('$ciudad, $provincia, Argentina');
    return 'https://www.google.com/maps/search/?api=1&query=$q';
  }

  String _slug(String nombre) {
    var s = nombre.toLowerCase();
    const from = 'áàäéèëíìïóòöúùüñ';
    const to = 'aaaeeeiiiooouuun';
    for (var i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }
    return s.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  List<String> _candidatosUsername(String nombre) {
    final base = _slug(nombre);
    if (base.isEmpty) return <String>['milocal', 'milocal1', 'milocaloficial'];
    final corto = base.length > 20 ? base.substring(0, 20) : base;
    final set = <String>{
      corto,
      '${corto}1',
      '${corto}ok',
      '${corto}oficial',
      '${corto}ar',
    };
    return set.where((e) => e.length >= 3).toList();
  }

  String _normalizarUsername(String v) =>
      v.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');

  Future<bool> _usernameLibre(String u) async {
    final uid = ServicioSupabase().usuarioActual?.id;
    if (uid == null) return false;
    try {
      final row = await ServicioSupabase().cliente
          .from('perfiles_locales')
          .select('id')
          .eq('local_username', u)
          .neq('id', uid)
          .maybeSingle();
      return row == null;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _primerUsernameLibre(List<String> candidatos) async {
    for (final c in candidatos) {
      if (c.length < 3) continue;
      if (await _usernameLibre(c)) return c;
    }
    return null;
  }

  void _onUsernameManualChanged(String raw) {
    final norm = _normalizarUsername(raw);
    if (norm != raw) {
      _input.value = _input.value.copyWith(
        text: norm,
        selection: TextSelection.collapsed(offset: norm.length),
      );
    }
    _debounce?.cancel();
    if (norm.length < 3) {
      setState(() {
        _disponible = null;
        _verificando = false;
      });
      return;
    }
    setState(() => _verificando = true);
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final libre = await _usernameLibre(norm);
      if (!mounted || _normalizarUsername(_input.text) != norm) return;
      setState(() {
        _verificando = false;
        _disponible = libre;
      });
    });
  }

  Future<void> _pickAvatar() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2000,
        imageQuality: 90,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final recortada = await mostrarRecorteLogoSheet(context, bytes);
      if (recortada == null || !mounted) return;
      setState(() => _datos.fotoPerfilBytes = recortada);
    } catch (_) {
      _snack('No se pudo cargar la imagen.');
    }
  }

  Future<void> _pickBanner() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2200,
        imageQuality: 90,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _datos.fotoBannerBytes = bytes);
    } catch (_) {
      _snack('No se pudo cargar la imagen.');
    }
  }

  Future<void> _pickFotoLocal() async {
    if (_datos.fotosLocalesBytes.where((e) => e != null).length >= 10) return;
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2000,
        imageQuality: 88,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _datos.fotosLocalesBytes.add(bytes));
    } catch (_) {
      _snack('No se pudo cargar la imagen.');
    }
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<bool> _confirmarSalir() async {
    if (_paso == _Paso.felicitacion) return true;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ColoresOnboardingLocales.violetaOscuro,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '¿Salir del asistente?',
          style: GoogleFonts.baloo2(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'Vas a perder lo que cargaste acá. Podés seguir con el formulario tradicional.',
          style: GoogleFonts.baloo2(
            color: ColoresOnboardingLocales.textoSecundario,
            height: 1.3,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Seguir acá',
              style: GoogleFonts.baloo2(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Salir',
              style: GoogleFonts.baloo2(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  int get _pasoIndice {
    switch (_paso) {
      case _Paso.nombre:
        return 1;
      case _Paso.usernameSugerido:
      case _Paso.usernameManual:
        return 2;
      case _Paso.ubicacion:
        return 3;
      case _Paso.direccion:
        return 4;
      case _Paso.horarios:
      case _Paso.horariosPreview:
        return 5;
      case _Paso.descripcion:
      case _Paso.descripcionPreview:
        return 6;
      case _Paso.rubros:
        return 7;
      case _Paso.redes:
        return 8;
      case _Paso.avatar:
        return 9;
      case _Paso.banner:
        return 10;
      case _Paso.fotosLocal:
        return 11;
      default:
        return 12;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmarSalir() && mounted) Navigator.of(context).pop();
      },
      child: DraggableScrollableSheet(
        initialChildSize: 0.94,
        minChildSize: 0.6,
        maxChildSize: 0.97,
        expand: false,
        builder: (_, scrollExterno) => Padding(
          padding: EdgeInsets.only(bottom: viewInsets),
          child: Container(
            decoration: const BoxDecoration(
              color: _kFondoChat,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                _header(),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                    itemCount: _mensajes.length + (_botEscribiendo ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= _mensajes.length) return const _TypingBurbuja();
                      return _mensajes[i].build();
                    },
                  ),
                ),
                _AreaInput(child: _buildInput()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kBurbujaBot,
                ),
                child: const Icon(
                  CupertinoIcons.sparkles,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Asistente Fernecito',
                      style: GoogleFonts.baloo2(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Creá tu perfil charlando',
                      style: GoogleFonts.baloo2(
                        color: ColoresOnboardingLocales.textoSuave,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () async {
                  if (await _confirmarSalir() && mounted)
                    Navigator.of(context).pop();
                },
                icon: const Icon(
                  CupertinoIcons.xmark,
                  color: Colors.white70,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _pasoIndice / _totalPasos,
              minHeight: 5,
              backgroundColor: Colors.white.withValues(alpha: 0.14),
              valueColor: const AlwaysStoppedAnimation(_kAcento),
            ),
          ),
        ],
      ),
    );
  }

  // ── Área de input dinámica ────────────────────────────────────────────────────
  Widget _buildInput() {
    if (_procesando && _paso != _Paso.usernameManual) {
      return const _InputDeshabilitado(texto: 'Un segundo…');
    }
    switch (_paso) {
      case _Paso.nombre:
        return _inputTexto(hint: 'Ej: El bar de la esquina', onSend: _onNombre);
      case _Paso.usernameSugerido:
        return _opciones([
          _OpcionBtn(
            'Sí, usar @${_datos.localUsername}',
            () => _confirmarUsername(_datos.localUsername),
            primario: true,
          ),
          _OpcionBtn('Prefiero otro', _prepararUsernameManual),
        ]);
      case _Paso.usernameManual:
        return _inputUsernameManual();
      case _Paso.ubicacion:
        return _OpcionBtn(
          'Elegir provincia y ciudad',
          _abrirSelectorUbicacion,
          primario: true,
          icono: CupertinoIcons.placemark,
        ).comoBarra();
      case _Paso.direccion:
        return _inputTexto(
          hint: 'Ej: Av. Colón 450',
          onSend: _onDireccion,
          accionExtra: _OpcionBtn(
            'No tengo dirección (organizador)',
            _sinDireccionOrganizador,
          ),
        );
      case _Paso.horarios:
        return _inputTexto(
          hint: 'Ej: lun a vie 5-8 pm, sáb y dom 6 pm-2 am',
          onSend: _onHorarios,
          multilinea: true,
          accionExtra: _OpcionBtn('No tengo horario fijo', _sinHorarios),
        );
      case _Paso.horariosPreview:
        return _opciones([
          _OpcionBtn('Están bien 👍', _confirmarHorarios, primario: true),
          _OpcionBtn('Reescribir', () async {
            _correccionHorarios = true;
            _irA(_Paso.horarios);
            await _bot([
              'Contame la **corrección** 👇 ej: los sábados es de 6 pm a 2 am, no de 6 am',
            ]);
            _inputFocus.requestFocus();
          }),
        ]);
      case _Paso.descripcion:
        return _inputDescripcion();
      case _Paso.descripcionPreview:
        return _opciones([
          _OpcionBtn('Usar esta ✨', _confirmarDescripcion, primario: true),
          if (_regeneraciones < 3)
            _OpcionBtn(
              'Regenerar (${3 - _regeneraciones})',
              () => _mejorarDescripcion(desdeBorrador: true),
            ),
          _OpcionBtn('Prefiero la mía', () async {
            _datos.descripcion = _descripcionBorrador;
            await _bot(['Dale, usamos la tuya 👌']);
            await _pedirRubros(iaSugirio: false);
          }),
        ]);
      case _Paso.rubros:
        return _inputRubros();
      case _Paso.redes:
        return _inputRedes();
      case _Paso.avatar:
        return _inputAvatar();
      case _Paso.banner:
        return _inputBanner();
      case _Paso.fotosLocal:
        return _inputFotosLocal();
      case _Paso.resumen:
        return _OpcionBtn(
          'Crear perfil 🚀',
          _crearPerfil,
          primario: true,
          icono: CupertinoIcons.checkmark_seal_fill,
        ).comoBarra();
      case _Paso.guardando:
        return const _InputDeshabilitado(texto: 'Creando tu perfil…');
      case _Paso.felicitacion:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _OpcionBtn(
              'Ir a mi dashboard',
              () {
                Navigator.of(context).pop();
                widget.onIrADashboard();
              },
              primario: true,
              icono: CupertinoIcons.arrow_right_circle_fill,
            ).comoBarra(),
            const SizedBox(height: 8),
            _OpcionBtn('Ver planes', () {
              Navigator.of(context).pop();
              if (widget.onVerPlanes != null) {
                widget.onVerPlanes!();
              } else {
                widget.onIrADashboard();
              }
            }, icono: CupertinoIcons.sparkles).comoBarra(),
          ],
        );
    }
  }

  Widget _inputTexto({
    required String hint,
    required Future<void> Function() onSend,
    bool multilinea = false,
    Widget? accionExtra,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (accionExtra != null) ...[
          Align(alignment: Alignment.centerLeft, child: accionExtra),
          const SizedBox(height: 8),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _campoTexto(
                hint: hint,
                multilinea: multilinea,
                onSubmit: onSend,
              ),
            ),
            const SizedBox(width: 8),
            _BotonEnviar(onTap: onSend),
          ],
        ),
      ],
    );
  }

  Widget _campoTexto({
    required String hint,
    bool multilinea = false,
    VoidCallback? onSubmit,
    void Function(String)? onChanged,
  }) {
    return TextField(
      controller: _input,
      focusNode: _inputFocus,
      onChanged: onChanged,
      minLines: 1,
      maxLines: multilinea ? 4 : 1,
      textInputAction: multilinea
          ? TextInputAction.newline
          : TextInputAction.send,
      onSubmitted: onSubmit == null ? null : (_) => onSubmit(),
      style: GoogleFonts.baloo2(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      cursorColor: _kAcento,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.baloo2(
          color: ColoresOnboardingLocales.textoSuave,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.10),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _inputUsernameManual() {
    final norm = _normalizarUsername(_input.text);
    final puede = norm.length >= 3 && _disponible == true;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_sugerenciasUser.isNotEmpty) ...[
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _sugerenciasUser.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _ChipSugerencia(
                texto: '@${_sugerenciasUser[i]}',
                onTap: () async {
                  final u = _sugerenciasUser[i];
                  if (await _usernameLibre(u)) {
                    _confirmarUsername(u);
                  } else {
                    _snack('Ese ya está ocupado, probá otro.');
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _campoTexto(
                hint: 'tu_usuario',
                onChanged: _onUsernameManualChanged,
                onSubmit: puede ? () => _confirmarUsername(norm) : null,
              ),
            ),
            const SizedBox(width: 8),
            if (_verificando)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else if (norm.length >= 3)
              Icon(
                _disponible == true
                    ? CupertinoIcons.check_mark_circled_solid
                    : CupertinoIcons.xmark_circle_fill,
                color: _disponible == true
                    ? const Color(0xFF4ADE80)
                    : const Color(0xFFFF8A80),
              ),
            const SizedBox(width: 8),
            _BotonEnviar(onTap: puede ? () => _confirmarUsername(norm) : null),
          ],
        ),
        if (norm.length >= 3 && _disponible == false)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'Ese ya existe, probá otro.',
              style: GoogleFonts.baloo2(
                color: const Color(0xFFFFB4B4),
                fontSize: 12.5,
              ),
            ),
          ),
      ],
    );
  }

  Widget _inputDescripcion() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _campoTexto(
          hint: 'Ej: cerveza artesanal, picadas, música en vivo los viernes…',
          multilinea: true,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _OpcionBtn('Usar tal cual', _usarDescripcionTalCual),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _OpcionBtn(
                'Mejorar con IA ✨',
                () => _mejorarDescripcion(desdeBorrador: false),
                primario: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _inputRubros() {
    return StatefulBuilder(
      builder: (_, setLocal) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kRubros.map((r) {
                final sel = _datos.rubros.contains(r);
                return GestureDetector(
                  onTap: () {
                    setLocal(() {
                      if (sel) {
                        _datos.rubros.remove(r);
                      } else {
                        _datos.rubros.add(r);
                      }
                    });
                    setState(() {});
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: sel
                          ? _kBurbujaBot
                          : Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sel ? _kBurbujaBot : Colors.white24,
                      ),
                    ),
                    child: Text(
                      r,
                      style: GoogleFonts.baloo2(
                        color: sel ? Colors.white : Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            _OpcionBtn(
              'Continuar',
              _datos.rubros.isEmpty ? null : _confirmarRubros,
              primario: true,
            ).comoBarra(),
          ],
        );
      },
    );
  }

  Widget _inputRedes() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CampoRed(
          controller: _ig,
          prefijo: '@',
          hint: 'Instagram',
          icono: CupertinoIcons.camera,
        ),
        const SizedBox(height: 8),
        _CampoRed(
          controller: _tk,
          prefijo: '@',
          hint: 'TikTok',
          icono: CupertinoIcons.music_note,
        ),
        const SizedBox(height: 8),
        _CampoRed(
          controller: _web,
          prefijo: '',
          hint: 'Sitio web (opcional)',
          icono: CupertinoIcons.globe,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _OpcionBtn('No tengo', () {
                _ig.clear();
                _tk.clear();
                _web.clear();
                _confirmarRedes();
              }),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _OpcionBtn('Listo', _confirmarRedes, primario: true),
            ),
          ],
        ),
      ],
    );
  }

  Widget _inputAvatar() {
    final tiene = _datos.fotoPerfilBytes != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _pickAvatar,
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.10),
              border: Border.all(color: _kAcento, width: 2),
              image: tiene
                  ? DecorationImage(
                      image: MemoryImage(_datos.fotoPerfilBytes!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: tiene
                ? null
                : const Icon(CupertinoIcons.add, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 12),
        _OpcionBtn(
          tiene ? 'Enviar logo' : 'Elegí una imagen',
          tiene ? _confirmarAvatar : _pickAvatar,
          primario: true,
        ).comoBarra(),
      ],
    );
  }

  Widget _inputBanner() {
    final tiene = _datos.fotoBannerBytes != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vertical o cuadrada · foto del local, fiesta o ambiente',
          style: GoogleFonts.baloo2(
            color: ColoresOnboardingLocales.textoSuave,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: GestureDetector(
            onTap: _pickBanner,
            child: SizedBox(
              width: 130,
              child: AspectRatio(
                aspectRatio: 4 / 5,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white.withValues(alpha: 0.10),
                    border: Border.all(color: _kAcento, width: 1.6),
                    image: tiene
                        ? DecorationImage(
                            image: MemoryImage(_datos.fotoBannerBytes!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: tiene
                      ? null
                      : const Icon(
                          CupertinoIcons.add,
                          color: Colors.white,
                          size: 26,
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _OpcionBtn(
                'Lo hago después',
                () => _confirmarBanner(omitir: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _OpcionBtn(
                'Enviar',
                tiene ? () => _confirmarBanner(omitir: false) : _pickBanner,
                primario: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _inputFotosLocal() {
    final fotos = _datos.fotosLocalesBytes.whereType<Uint8List>().toList();
    final puedeMas = fotos.length < 10;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Podés agregar más o editarlas después en Mi local',
          style: GoogleFonts.baloo2(
            color: ColoresOnboardingLocales.textoSuave,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...List.generate(fotos.length, (i) {
              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      fotos[i],
                      width: 58,
                      height: 58,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: -6,
                    right: -6,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () =>
                          setState(() => _datos.fotosLocalesBytes.removeAt(i)),
                      icon: const Icon(
                        CupertinoIcons.minus_circle_fill,
                        color: Color(0xFFFF8A80),
                        size: 20,
                      ),
                    ),
                  ),
                ],
              );
            }),
            if (puedeMas)
              GestureDetector(
                onTap: _pickFotoLocal,
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.white.withValues(alpha: 0.10),
                    border: Border.all(color: _kAcento, width: 1.4),
                  ),
                  child: const Icon(
                    CupertinoIcons.add,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _OpcionBtn(
          'Enviar ${fotos.isEmpty ? "" : "(${fotos.length})"}',
          fotos.isEmpty ? null : _confirmarFotosLocal,
          primario: true,
        ).comoBarra(),
      ],
    );
  }

  Widget _opciones(List<_OpcionBtn> botones) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < botones.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          botones[i].comoBarra(),
        ],
      ],
    );
  }

  Future<void> _abrirSelectorUbicacion() async {
    final res = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SelectorUbicacion(
        provinciaInicial: _datos.provincia,
        ciudadInicial: _datos.ciudad,
      ),
    );
    if (res != null && mounted) {
      _onUbicacionConfirmada(res.$1, res.$2);
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  MODELO Y WIDGETS DE MENSAJE
// ════════════════════════════════════════════════════════════════════════════
class _Mensaje {
  final bool esBot;
  final Widget child;
  final bool conBurbuja;
  final bool revelar;
  _Mensaje.bot(this.child, {this.conBurbuja = true, this.revelar = false})
    : esBot = true;
  _Mensaje.usuario(this.child)
    : esBot = false,
      conBurbuja = true,
      revelar = false;

  Widget build() {
    final align = esBot ? Alignment.centerLeft : Alignment.centerRight;
    Widget contenido = conBurbuja
        ? Container(
            constraints: const BoxConstraints(maxWidth: 300),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: esBot ? _kBurbujaBot : _kBurbujaUsuario,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(esBot ? 4 : 16),
                bottomRight: Radius.circular(esBot ? 16 : 4),
              ),
            ),
            child: child,
          )
        : Container(
            constraints: const BoxConstraints(maxWidth: 320),
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: child,
          );
    if (revelar && esBot) {
      contenido = _RevealMensaje(child: contenido);
    }
    return Align(alignment: align, child: contenido);
  }
}

/// Aparición suave del mensaje nuevo (estilo iMessage), sin empujar exagerado el historial.
class _RevealMensaje extends StatefulWidget {
  const _RevealMensaje({required this.child});
  final Widget child;

  @override
  State<_RevealMensaje> createState() => _RevealMensajeState();
}

class _RevealMensajeState extends State<_RevealMensaje>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  )..forward();
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.12),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class _TextoBurbujaRich extends StatelessWidget {
  const _TextoBurbujaRich(this.texto, {required this.esBot});
  final String texto;
  final bool esBot;

  static final _boldRe = RegExp(r'\*\*(.+?)\*\*');

  @override
  Widget build(BuildContext context) {
    final color = esBot ? _kTextoBot : _kTextoUsuario;
    final base = GoogleFonts.baloo2(
      color: color,
      fontWeight: FontWeight.w600,
      fontSize: 14.5,
      height: 1.3,
    );
    final spans = <TextSpan>[];
    var rest = texto;
    while (rest.isNotEmpty) {
      final m = _boldRe.firstMatch(rest);
      if (m == null) {
        spans.add(TextSpan(text: rest));
        break;
      }
      if (m.start > 0) spans.add(TextSpan(text: rest.substring(0, m.start)));
      spans.add(
        TextSpan(
          text: m.group(1),
          style: base.copyWith(fontWeight: FontWeight.w900),
        ),
      );
      rest = rest.substring(m.end);
    }
    return Text.rich(TextSpan(style: base, children: spans));
  }
}

class _MapsLinkPreview extends StatelessWidget {
  const _MapsLinkPreview({required this.url, required this.etiqueta});
  final String url;
  final String etiqueta;

  Future<void> _abrir() async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await lanzarExternoConFallback(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(CupertinoIcons.map_fill, size: 15, color: _kTextoBot),
            const SizedBox(width: 6),
            Text(
              'Ubicación en Maps',
              style: GoogleFonts.baloo2(
                color: _kTextoBot,
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          etiqueta,
          style: GoogleFonts.baloo2(
            color: _kTextoBot,
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: _abrir,
          child: Text(
            'Ver en Google Maps ↗',
            style: GoogleFonts.baloo2(
              color: const Color(0xFFC4B5FD),
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              decoration: TextDecoration.underline,
              decorationColor: const Color(0xFFC4B5FD),
            ),
          ),
        ),
      ],
    );
  }
}

class _TypingBurbuja extends StatelessWidget {
  const _TypingBurbuja();
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _kBurbujaBot,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: const _PuntosAnimados(color: _kTextoBot),
      ),
    );
  }
}

class _PuntosAnimados extends StatefulWidget {
  const _PuntosAnimados({this.color = _kTextoBot});
  final Color color;
  @override
  State<_PuntosAnimados> createState() => _PuntosAnimadosState();
}

class _PuntosAnimadosState extends State<_PuntosAnimados>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = ((_c.value * 3) - i).clamp(0.0, 1.0);
            final op = (0.35 + 0.65 * (t < 0.5 ? t * 2 : (1 - t) * 2)).clamp(
              0.35,
              1.0,
            );
            return Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: op),
              ),
            );
          }),
        );
      },
    );
  }
}

class _CargandoBurbuja extends StatelessWidget {
  const _CargandoBurbuja({required this.texto});
  final String texto;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: _kTextoBot),
        ),
        const SizedBox(width: 10),
        Text(
          texto,
          style: GoogleFonts.baloo2(
            color: _kTextoBot,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _HorariosPreview extends StatelessWidget {
  const _HorariosPreview({required this.resumen});
  final String resumen;
  @override
  Widget build(BuildContext context) {
    final lineas = resumen
        .split('\n')
        .where((e) => e.trim().isNotEmpty)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(CupertinoIcons.clock_fill, size: 15, color: _kTextoBot),
            const SizedBox(width: 6),
            Text(
              'Tus horarios',
              style: GoogleFonts.baloo2(
                color: _kTextoBot,
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...lineas.map(
          (l) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.5),
            child: Text(
              l,
              style: GoogleFonts.baloo2(
                color: _kTextoBot,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                height: 1.25,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DescripcionPreview extends StatelessWidget {
  const _DescripcionPreview({required this.texto});
  final String texto;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(CupertinoIcons.sparkles, size: 15, color: _kTextoBot),
            const SizedBox(width: 6),
            Text(
              'Descripción sugerida',
              style: GoogleFonts.baloo2(
                color: _kTextoBot,
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          texto,
          style: GoogleFonts.baloo2(
            color: _kTextoBot,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _ChipInfo extends StatelessWidget {
  const _ChipInfo({required this.icon, required this.texto});
  final IconData icon;
  final String texto;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: _kTextoUsuario),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            texto,
            style: GoogleFonts.baloo2(
              color: _kTextoUsuario,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.bytes});
  final Uint8List bytes;
  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.memory(bytes, width: 56, height: 56, fit: BoxFit.cover),
    );
  }
}

class _MiniBanner extends StatelessWidget {
  const _MiniBanner({required this.bytes});
  final Uint8List bytes;
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.memory(bytes, width: 72, height: 90, fit: BoxFit.cover),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  WIDGETS DE INPUT
// ════════════════════════════════════════════════════════════════════════════
class _AreaInput extends StatelessWidget {
  const _AreaInput({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        14,
        12,
        14,
        12 + MediaQuery.paddingOf(context).bottom * 0.4,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: SafeArea(top: false, child: child),
    );
  }
}

class _BotonEnviar extends StatelessWidget {
  const _BotonEnviar({this.onTap});
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final activo = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: activo ? _kAcento : Colors.white.withValues(alpha: 0.15),
        ),
        child: Icon(
          CupertinoIcons.arrow_up,
          color: activo ? Colors.white : Colors.white38,
          size: 22,
        ),
      ),
    );
  }
}

class _OpcionBtn extends StatelessWidget {
  const _OpcionBtn(this.label, this.onTap, {this.primario = false, this.icono});
  final String label;
  final VoidCallback? onTap;
  final bool primario;
  final IconData? icono;

  Widget comoBarra() => SizedBox(width: double.infinity, child: this);

  @override
  Widget build(BuildContext context) {
    final activo = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: primario
                ? (activo ? _kAcento : _kAcento.withValues(alpha: 0.4))
                : Colors.white.withValues(alpha: 0.10),
            border: primario ? null : Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icono != null) ...[
                Icon(
                  icono,
                  size: 18,
                  color: primario ? Colors.white : Colors.white,
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.baloo2(
                    color: primario ? Colors.white : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
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

class _ChipSugerencia extends StatelessWidget {
  const _ChipSugerencia({required this.texto, required this.onTap});
  final String texto;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.white.withValues(alpha: 0.10),
          border: Border.all(color: _kAcento.withValues(alpha: 0.55)),
        ),
        child: Text(
          texto,
          style: GoogleFonts.baloo2(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _CampoRed extends StatelessWidget {
  const _CampoRed({
    required this.controller,
    required this.prefijo,
    required this.hint,
    required this.icono,
  });
  final TextEditingController controller;
  final String prefijo;
  final String hint;
  final IconData icono;
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: GoogleFonts.baloo2(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      cursorColor: _kAcento,
      keyboardType: TextInputType.url,
      inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
      decoration: InputDecoration(
        prefixIcon: Icon(
          icono,
          size: 18,
          color: ColoresOnboardingLocales.textoSuave,
        ),
        prefixText: prefijo,
        prefixStyle: GoogleFonts.baloo2(
          color: Colors.white70,
          fontWeight: FontWeight.w700,
        ),
        hintText: hint,
        hintStyle: GoogleFonts.baloo2(
          color: ColoresOnboardingLocales.textoSuave,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.10),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _InputDeshabilitado extends StatelessWidget {
  const _InputDeshabilitado({required this.texto});
  final String texto;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white54,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          texto,
          style: GoogleFonts.baloo2(
            color: Colors.white54,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── Selector provincia + ciudad ────────────────────────────────────────────────
class _SelectorUbicacion extends StatefulWidget {
  const _SelectorUbicacion({
    required this.provinciaInicial,
    required this.ciudadInicial,
  });
  final String provinciaInicial;
  final String ciudadInicial;
  @override
  State<_SelectorUbicacion> createState() => _SelectorUbicacionState();
}

class _SelectorUbicacionState extends State<_SelectorUbicacion> {
  late String _provincia = widget.provinciaInicial;
  late String _ciudad = widget.ciudadInicial;

  @override
  Widget build(BuildContext context) {
    final ciudades = UbicacionesData.ciudadesDe(_provincia);
    if (!ciudades.contains(_ciudad) && ciudades.isNotEmpty)
      _ciudad = ciudades.first;
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '¿Dónde está tu local?',
            style: GoogleFonts.baloo2(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 16),
          _dropdown(
            label: 'Provincia',
            value: _provincia,
            items: UbicacionesData.provincias,
            onChanged: (v) => setState(() {
              _provincia = v!;
              final cs = UbicacionesData.ciudadesDe(v);
              _ciudad = cs.isNotEmpty ? cs.first : _ciudad;
            }),
          ),
          const SizedBox(height: 12),
          _dropdown(
            label: 'Ciudad',
            value: _ciudad,
            items: ciudades,
            onChanged: (v) => setState(() => _ciudad = v!),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: _OpcionBtn(
              'Confirmar',
              () => Navigator.pop(context, (_provincia, _ciudad)),
              primario: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: items.contains(value)
          ? value
          : (items.isNotEmpty ? items.first : null),
      isExpanded: true,
      dropdownColor: const Color(0xFF1F1F1F),
      style: GoogleFonts.baloo2(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.baloo2(
          color: ColoresOnboardingLocales.textoSuave,
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      items: items
          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
          .toList(),
      onChanged: onChanged,
    );
  }
}
