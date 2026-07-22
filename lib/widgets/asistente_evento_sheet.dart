/// Asistente IA (chatbot árbol de decisión) para crear un EVENTO (modo completo).
///
/// Capa ADITIVA sobre `LocalesCrearEvento`: recolecta los MISMOS campos que el
/// form y publica por el MISMO camino (`onPublicar` → `subir_evento`). El form
/// tradicional queda intacto como fallback.
///
/// Diseño: tema claro de la app locales (ColoresLocales), copy amable de crear
/// evento. IA solo donde suma: fechas (parseo NL) y descripción (redacción +
/// clasifica el tipo en la MISMA llamada, para no gastar tokens de más).
/// Todo lo no bloqueante tiene skip claro ("Entrada libre", "Sin requisitos"…).
library;

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../core/constants.dart';
import '../core/servicio_edges_eventos.dart';

// ── Datos recolectados (mapeados 1:1 al form) ────────────────────────────────
class PromoChat {
  String titulo = '';
  String descripcion = '';
  int? cuposTotales; // null = sin límite
  String modoUso = 'individual'; // 'individual' | 'squad'
  int? minSquad;
  int? maxSquad;
}

class DatosEventoChat {
  String titulo = '';
  String tipo = 'evento';
  Uint8List? flyerBytes;
  DateTime? fechaInicio;
  DateTime? fechaFin;
  bool esEnLocal = true;
  String? direccion;
  String? ciudad;
  String? provincia;
  String? urlMaps;
  int? edadMinima;
  String modoLista = 'auto'; // 'auto' | 'manual'
  int? cupoListaMax; // null = sin límite
  bool permiteSquads = true;
  String? urlCompraEntradas;
  String? advertencias;
  String? descripcion;
  bool agregarPromos = false;
  final List<PromoChat> promos = <PromoChat>[];
}

const _kTipos = <String>[
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
];

const _kRestricciones = <String>[
  'DNI obligatorio',
  'Código de vestimenta',
  'Prohibido para menores',
  'Reservá con anticipación',
];

String _tipoLabel(String t) =>
    t.isEmpty ? t : '${t[0].toUpperCase()}${t.substring(1)}';

const _kVioleta = Color(0xFF7C3AED); // acento marca fijo (contraste estable)

/// Abre el chatbot de creación de evento.
///
/// [onPublicar] debe devolver `(error: null, idEvento: '…')` si salió bien,
/// o `(error: 'mensaje', idEvento: null)` si falló.
Future<void> mostrarAsistenteEventoSheet(
  BuildContext context, {
  String? ciudadLocal,
  Uint8List? flyerInicial,
  required Future<({String? error, String? idEvento})> Function(DatosEventoChat)
      onPublicar,
  required VoidCallback onIrHome,
  required void Function(String? idEvento) onSubirJerarquia,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => _AsistenteEventoSheet(
      ciudadLocal: ciudadLocal,
      flyerInicial: flyerInicial,
      onPublicar: onPublicar,
      onIrHome: onIrHome,
      onSubirJerarquia: onSubirJerarquia,
    ),
  );
}

enum _Paso {
  titulo,
  flyer,
  fechas,
  fechasPreview,
  ubicacion,
  direccionExterna,
  descripcion,
  descripcionPreview,
  tipo,
  tipoManual,
  ingreso,
  ingresoCupo,
  entrada,
  edad,
  restricciones,
  promosPregunta,
  promoTitulo,
  promoDescripcion,
  promoModo,
  promoSquad,
  promoCupos,
  promoOtra,
  publicar,
  guardando,
  felicitacion,
}

class _AsistenteEventoSheet extends StatefulWidget {
  const _AsistenteEventoSheet({
    required this.ciudadLocal,
    required this.flyerInicial,
    required this.onPublicar,
    required this.onIrHome,
    required this.onSubirJerarquia,
  });

  final String? ciudadLocal;
  final Uint8List? flyerInicial;
  final Future<({String? error, String? idEvento})> Function(DatosEventoChat)
      onPublicar;
  final VoidCallback onIrHome;
  final void Function(String? idEvento) onSubirJerarquia;

  @override
  State<_AsistenteEventoSheet> createState() => _AsistenteEventoSheetState();
}

class _AsistenteEventoSheetState extends State<_AsistenteEventoSheet> {
  final DatosEventoChat _datos = DatosEventoChat();
  final List<_Mensaje> _mensajes = <_Mensaje>[];
  final ScrollController _scroll = ScrollController();
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final TextEditingController _squadMin = TextEditingController();
  final TextEditingController _squadMax = TextEditingController();

  _Paso _paso = _Paso.titulo;
  bool _botEscribiendo = false;
  bool _procesando = false;

  String _descripcionBorrador = '';
  int _regeneraciones = 0;
  String? _fechaInicioPrevia;
  String? _fechaFinPrevia;
  String _tipoSugerido = 'evento';
  String? _idEventoPublicado;

  final Set<String> _restriccionesSel = <String>{};
  PromoChat? _promoActual;

  static const _totalPasos = 10;

  @override
  void initState() {
    super.initState();
    _arrancar();
  }

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    _squadMin.dispose();
    _squadMax.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── Mensajes ────────────────────────────────────────────────────────────────
  void _scrollAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        final max = _scroll.position.maxScrollExtent;
        if (max > 0) {
          _scroll.animateTo(
            max,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  void _pushUsuario(String texto) {
    setState(
      () => _mensajes.add(_Mensaje.usuario(_TextoBurbuja(texto, esBot: false))),
    );
    _scrollAlFinal();
  }

  void _pushUsuarioWidget(Widget child) {
    setState(() => _mensajes.add(_Mensaje.usuario(child)));
    _scrollAlFinal();
  }

  void _pushBotWidget(Widget child) {
    setState(() => _mensajes.add(_Mensaje.bot(child)));
    _scrollAlFinal();
  }

  Future<void> _bot(List<String> textos) async {
    for (final t in textos) {
      setState(() => _botEscribiendo = true);
      _scrollAlFinal();
      await Future<void>.delayed(const Duration(milliseconds: 460));
      if (!mounted) return;
      setState(() {
        _botEscribiendo = false;
        _mensajes.add(_Mensaje.bot(_TextoBurbuja(t, esBot: true)));
      });
      _scrollAlFinal();
      await Future<void>.delayed(const Duration(milliseconds: 110));
    }
  }

  void _irA(_Paso p) {
    setState(() => _paso = p);
    _scrollAlFinal();
  }

  String _msgError(Object e) => e is EdgeException
      ? e.mensaje
      : 'Algo falló. Probá de nuevo en un momento.';

  // ── Flujo ─────────────────────────────────────────────────────────────────
  Future<void> _arrancar() async {
    await _bot([
      '¡Hola! 👋 Armemos tu evento en un toque.',
      '¿Cómo se llama? Poné el título tal cual querés que aparezca 🎟️',
    ]);
    if (mounted) _inputFocus.requestFocus();
  }

  Future<void> _onTitulo() async {
    final v = _input.text.trim();
    if (v.isEmpty) return;
    _datos.titulo = v;
    _input.clear();
    _pushUsuario(v);
    await _bot([
      '¡Buen nombre! 🔥 Subí el flyer de tu evento (vertical se ve mejor).',
    ]);
    _pedirFlyer();
  }

  void _pedirFlyer() {
    if (widget.flyerInicial != null && _datos.flyerBytes == null) {
      _datos.flyerBytes = widget.flyerInicial;
      _pushBotWidget(
        const _TextoBurbuja(
          'Tengo este flyer del paso anterior. ¿Lo usamos?',
          esBot: true,
        ),
      );
      _pushBotWidget(_FlyerPreview(bytes: widget.flyerInicial!));
    }
    _irA(_Paso.flyer);
  }

  Future<void> _pickFlyer() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2200,
        imageQuality: 92,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _datos.flyerBytes = bytes);
    } catch (_) {
      _snack('No se pudo cargar la imagen.');
    }
  }

  Future<void> _confirmarFlyer() async {
    if (_datos.flyerBytes == null) return;
    _pushUsuarioWidget(_MiniFlyer(bytes: _datos.flyerBytes!));
    await _bot([
      '¡Genial! Ahora decime cuándo es el evento y cuándo termina 🕒 '
          '(podés decirlo en lenguaje natural). '
          'Por ejemplo: "el sábado 25 a las 23, termina 6 am".',
    ]);
    setState(() {
      _fechaInicioPrevia = null;
      _fechaFinPrevia = null;
    });
    _irA(_Paso.fechas);
    _inputFocus.requestFocus();
  }

  Future<void> _onFechas({required bool esCorreccion}) async {
    final v = _input.text.trim();
    if (v.length < 3) return;
    _input.clear();
    _pushUsuario(v);
    setState(() => _procesando = true);
    await _bot(['Ordenando las fechas ✨']);
    try {
      final res = await ServicioEdgesEventos().asistenteEventoLocal(
        intent: 'fechas',
        texto: v,
        contexto: esCorreccion && _fechaInicioPrevia != null
            ? {
                'es_correccion': true,
                'inicio_anterior': _fechaInicioPrevia,
                'fin_anterior': _fechaFinPrevia,
              }
            : null,
      );
      if (!mounted) return;
      setState(() => _procesando = false);
      if (res['entendido'] != true) {
        await _bot([
          (res['error'] ?? 'No entendí la fecha 😅 ¿La reescribís?').toString(),
        ]);
        _inputFocus.requestFocus();
        return;
      }
      final ini = DateTime.tryParse((res['fecha_inicio'] ?? '').toString());
      final fin = DateTime.tryParse((res['fecha_fin'] ?? '').toString());
      final resumen = (res['resumen'] ?? '').toString();
      if (ini == null || fin == null) {
        await _bot(['No entendí la fecha 😅 ¿La reescribís?']);
        _inputFocus.requestFocus();
        return;
      }
      _datos.fechaInicio = ini;
      _datos.fechaFin = fin;
      _fechaInicioPrevia = ini.toIso8601String();
      _fechaFinPrevia = fin.toIso8601String();
      _pushBotWidget(
        _FichaPreview(
          icono: CupertinoIcons.calendar,
          titulo: 'Fecha y hora',
          texto: resumen,
        ),
      );
      await _bot(['¿Están bien las fechas?']);
      _irA(_Paso.fechasPreview);
    } catch (e) {
      if (!mounted) return;
      setState(() => _procesando = false);
      await _bot([_msgError(e)]);
      _inputFocus.requestFocus();
    }
  }

  Future<void> _preguntarUbicacion() async {
    await _bot([
      '¿Dónde es el evento? 📍 Si es en tu local, pongo la misma dirección. '
          'Si es en otro lugar, indicámelo.',
    ]);
    _irA(_Paso.ubicacion);
  }

  Future<void> _ubicacionEnLocal() async {
    _datos.esEnLocal = true;
    _pushUsuarioWidget(
      const _ChipInfo(icon: CupertinoIcons.house_fill, texto: 'En mi local'),
    );
    await _pedirDescripcion();
  }

  Future<void> _ubicacionExterna(String provincia, String ciudad) async {
    _datos.esEnLocal = false;
    _datos.provincia = provincia;
    _datos.ciudad = ciudad;
    _pushUsuarioWidget(
      _ChipInfo(
        icon: CupertinoIcons.placemark_fill,
        texto: '$ciudad, $provincia',
      ),
    );
    await _bot(['¿Cuál es la dirección exacta? (calle y número)']);
    _irA(_Paso.direccionExterna);
    _inputFocus.requestFocus();
  }

  Future<void> _onDireccionExterna() async {
    final v = _input.text.trim();
    if (v.isEmpty) return;
    _datos.direccion = v;
    _datos.urlMaps = _mapsUrl(v, _datos.ciudad ?? '', _datos.provincia ?? '');
    _input.clear();
    _pushUsuario(v);
    await _bot(['Anotado ✅ (te generé el link de Maps).']);
    await _pedirDescripcion();
  }

  Future<void> _pedirDescripcion() async {
    await _bot([
      '¿De qué trata tu evento? ✨ Describilo lo mejor que puedas: '
          'esto ayuda a nuestra búsqueda IA y a que los usuarios te encuentren. '
          'Podés contar cosas como música, ambiente, bebidas, tipo de comida…',
    ]);
    setState(() => _regeneraciones = 0);
    _input.clear();
    _irA(_Paso.descripcion);
    _inputFocus.requestFocus();
  }

  Future<void> _usarDescripcionTalCual() async {
    final v = _input.text.trim();
    if (v.length < 8) {
      _snack('Escribí un poquito más para la descripción.');
      return;
    }
    _datos.descripcion = v;
    _input.clear();
    _pushUsuario(v);
    await _bot(['Perfecto, la usamos tal cual 👌']);
    await _pedirTipo();
  }

  Future<void> _mejorarDescripcion({required bool desdeBorrador}) async {
    final v = desdeBorrador ? _descripcionBorrador : _input.text.trim();
    if (v.length < 8) {
      _snack('Escribí un poquito más para mejorarla.');
      return;
    }
    if (!desdeBorrador) {
      _descripcionBorrador = v;
      _input.clear();
      _pushUsuario(v);
    }
    setState(() => _procesando = true);
    await _bot(['Puliéndola con IA ✨']);
    try {
      final res = await ServicioEdgesEventos().asistenteEventoLocal(
        intent: 'descripcion',
        texto: v,
        contexto: {'titulo': _datos.titulo},
      );
      if (!mounted) return;
      setState(() => _procesando = false);
      final desc = (res['descripcion'] ?? '').toString();
      if (desc.length < 12) {
        await _bot([
          'No pude mejorarla ahora 😕 Podés usar tu texto tal cual o reintentar.',
        ]);
        _irA(_Paso.descripcion);
        return;
      }
      // Solo descuenta regeneración si la IA devolvió algo usable.
      setState(() => _regeneraciones++);
      _datos.descripcion = desc;
      // La MISMA llamada nos clasifica el tipo (menos tokens).
      final t = (res['tipo'] ?? '').toString();
      if (_kTipos.contains(t)) _tipoSugerido = t;
      _pushBotWidget(
        _FichaPreview(
          icono: CupertinoIcons.sparkles,
          titulo: 'Descripción sugerida',
          texto: desc,
        ),
      );
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

  Future<void> _pedirTipo() async {
    _datos.tipo = _tipoSugerido;
    await _bot(['Lo catalogué como "${_tipoLabel(_tipoSugerido)}". ¿Va así?']);
    _irA(_Paso.tipo);
  }

  Future<void> _confirmarTipo(String tipo) async {
    _datos.tipo = tipo;
    _pushUsuarioWidget(
      _ChipInfo(icon: CupertinoIcons.tag_fill, texto: _tipoLabel(tipo)),
    );
    await _pedirIngreso();
  }

  Future<void> _pedirIngreso() async {
    await _bot(['¿Cómo manejás la lista de entrada desde la app?']);
    _irA(_Paso.ingreso);
  }

  Future<void> _ingresoPaseLibre() async {
    _datos.modoLista = 'auto';
    _datos.cupoListaMax = null;
    _pushUsuarioWidget(
      const _ChipInfo(
        icon: CupertinoIcons.checkmark_seal_fill,
        texto: 'Pase libre (auto, sin límite)',
      ),
    );
    await _pedirEntrada();
  }

  Future<void> _ingresoConCupo() async {
    _datos.modoLista = 'auto';
    _input.clear();
    await _bot(['¿Cuántos cupos máximo en la lista?']);
    _irA(_Paso.ingresoCupo);
    _inputFocus.requestFocus();
  }

  Future<void> _ingresoManual() async {
    _datos.modoLista = 'manual';
    _input.clear();
    await _bot(['Dale, aprobás vos cada uno 👌 ¿Querés limitar el cupo?']);
    _irA(_Paso.ingresoCupo);
  }

  Future<void> _finalizarIngreso({int? cupo}) async {
    _datos.cupoListaMax = cupo;
    final modo = _datos.modoLista == 'manual' ? 'Manual' : 'Auto';
    _pushUsuarioWidget(
      _ChipInfo(
        icon: CupertinoIcons.person_2_fill,
        texto: cupo == null
            ? 'Lista $modo · sin límite'
            : 'Lista $modo · $cupo cupos',
      ),
    );
    await _pedirEntrada();
  }

  Future<void> _pedirEntrada() async {
    await _bot([
      '¿Vendés tickets por ticketera? 🎫 Pegá el link abajo, o tocá '
          '"No vendo tickets" si no aplica.',
    ]);
    _input.clear();
    _irA(_Paso.entrada);
    _inputFocus.requestFocus();
  }

  Future<void> _entradaLibre() async {
    _datos.urlCompraEntradas = null;
    _pushUsuarioWidget(
      const _ChipInfo(
        icon: CupertinoIcons.ticket_fill,
        texto: 'No vendo tickets',
      ),
    );
    await _pedirEdad();
  }

  Future<void> _onEntradaLink() async {
    final v = _input.text.trim();
    if (v.isEmpty) return;
    _datos.urlCompraEntradas = v;
    _input.clear();
    _pushUsuario(v);
    await _bot(['¡Listo! Sumé el link de venta 🎫']);
    await _pedirEdad();
  }

  Future<void> _pedirEdad() async {
    await _bot(['¿Hay edad mínima para entrar?']);
    _input.clear();
    _irA(_Paso.edad);
  }

  Future<void> _confirmarEdad(int? edad) async {
    _datos.edadMinima = edad;
    _pushUsuarioWidget(
      _ChipInfo(
        icon: CupertinoIcons.person_fill,
        texto: edad == null ? 'Sin restricción de edad' : 'Desde $edad años',
      ),
    );
    await _bot(['¿Algún requisito para entrar? Tocá los que apliquen o escribí uno custom 👇']);
    setState(() => _restriccionesSel.clear());
    _input.clear();
    _irA(_Paso.restricciones);
  }

  Future<void> _confirmarRestricciones() async {
    final custom = _input.text.trim();
    final partes = <String>[
      ..._restriccionesSel,
      if (custom.isNotEmpty) custom,
    ];
    _datos.advertencias = partes.isEmpty ? null : partes.join('. ');
    _input.clear();
    if (partes.isEmpty) {
      _pushUsuarioWidget(
        const _ChipInfo(
          icon: CupertinoIcons.checkmark_circle,
          texto: 'Sin requisitos',
        ),
      );
    } else {
      _pushUsuarioWidget(
        _ChipInfo(
          icon: CupertinoIcons.exclamationmark_shield_fill,
          texto: partes.join(' · '),
        ),
      );
    }
    await _bot([
      '¡Ya casi terminamos! 🎉 Última cosa: ¿querés sumar promos? Venden un montón 🔥',
    ]);
    _irA(_Paso.promosPregunta);
  }

  // ── Promos ──────────────────────────────────────────────────────────────────
  Future<void> _iniciarPromo() async {
    _promoActual = PromoChat();
    _input.clear();
    await _bot([
      'Dale 🙌 ¿Cómo se llama la promo? Ej: "2x1 en birras", "Combo previa"',
    ]);
    _irA(_Paso.promoTitulo);
    _inputFocus.requestFocus();
  }

  Future<void> _onPromoTitulo() async {
    final v = _input.text.trim();
    if (v.isEmpty) return;
    _promoActual!.titulo = v;
    _input.clear();
    _pushUsuario(v);
    await _bot(['¿Qué incluye la promo? Describila corta.']);
    _irA(_Paso.promoDescripcion);
    _inputFocus.requestFocus();
  }

  Future<void> _onPromoDescripcion() async {
    final v = _input.text.trim();
    if (v.isEmpty) return;
    _promoActual!.descripcion = v;
    _input.clear();
    _pushUsuario(v);
    await _bot(['¿Cómo se usa?']);
    _irA(_Paso.promoModo);
  }

  Future<void> _onPromoModo(String modo) async {
    _promoActual!.modoUso = modo;
    if (modo == 'squad') {
      _squadMin.clear();
      _squadMax.clear();
      _pushUsuarioWidget(
        const _ChipInfo(
          icon: CupertinoIcons.person_2_fill,
          texto: 'En squad (grupo)',
        ),
      );
      await _bot(['¿Mínimo y máximo de personas por squad?']);
      _irA(_Paso.promoSquad);
    } else {
      _pushUsuarioWidget(
        const _ChipInfo(icon: CupertinoIcons.person_fill, texto: 'Individual'),
      );
      await _pedirCuposPromo();
    }
  }

  Future<void> _onPromoSquad() async {
    final min = int.tryParse(_squadMin.text.trim());
    final max = int.tryParse(_squadMax.text.trim());
    if (min == null || max == null || min < 2 || max < min) {
      _snack('Ingresá mínimo 2 personas y un máximo válido (máx ≥ mín).');
      return;
    }
    _promoActual!.minSquad = min;
    _promoActual!.maxSquad = max;
    _pushUsuarioWidget(
      _ChipInfo(
        icon: CupertinoIcons.person_3_fill,
        texto: 'Squad de $min a $max',
      ),
    );
    await _pedirCuposPromo();
  }

  Future<void> _pedirCuposPromo() async {
    _input.clear();
    await _bot(['¿Limitás los cupos de esta promo?']);
    _irA(_Paso.promoCupos);
  }

  Future<void> _finalizarPromo({int? cupos}) async {
    _promoActual!.cuposTotales = cupos;
    _datos.promos.add(_promoActual!);
    _datos.agregarPromos = true;
    _pushUsuarioWidget(
      _ChipInfo(
        icon: CupertinoIcons.tag_fill,
        texto: cupos == null
            ? '${_promoActual!.titulo} · sin límite'
            : '${_promoActual!.titulo} · $cupos cupos',
      ),
    );
    _promoActual = null;
    await _bot(['¡Promo agregada! (${_datos.promos.length}) ¿Sumás otra?']);
    _irA(_Paso.promoOtra);
  }

  Future<void> _pedirPublicar() async {
    await _bot(['¡Listo! ¿Publicamos tu evento? 🚀']);
    _irA(_Paso.publicar);
  }

  Future<void> _publicar() async {
    if (_procesando) return;
    setState(() {
      _paso = _Paso.guardando;
      _procesando = true;
    });
    _pushBotWidget(const _CargandoBurbuja(texto: 'Publicando tu evento…'));
    final resultado = await widget.onPublicar(_datos);
    if (!mounted) return;
    setState(() => _procesando = false);
    if (resultado.error != null) {
      await _bot(['Ups: ${resultado.error}']);
      _irA(_Paso.publicar);
      return;
    }
    _idEventoPublicado = resultado.idEvento;
    await _bot([
      '¡Excelente! Tu publicación ya está en cartelera!! 🎉',
      'Podés subir la jerarquía para tener más visibilidad 🚀',
    ]);
    _irA(_Paso.felicitacion);
  }

  // ── Utils ─────────────────────────────────────────────────────────────────
  String _mapsUrl(String dir, String ciudad, String prov) {
    final q = Uri.encodeComponent('$dir, $ciudad, $prov');
    return 'https://www.google.com/maps/search/?api=1&query=$q';
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<bool> _confirmarSalir() async {
    if (_paso == _Paso.felicitacion) return true;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ColoresLocales.superficie,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '¿Salir del asistente?',
          style: GoogleFonts.baloo2(
            color: ColoresLocales.textoOnFondoClaro,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'Vas a perder lo que cargaste acá. Podés seguir con el formulario tradicional.',
          style: GoogleFonts.baloo2(
            color: ColoresLocales.textoSecundarioOnFondoClaro,
            height: 1.3,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Seguir acá',
              style: GoogleFonts.baloo2(
                color: _kVioleta,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Salir',
              style: GoogleFonts.baloo2(
                color: ColoresLocales.textoSecundarioOnFondoClaro,
              ),
            ),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  int get _pasoIndice {
    switch (_paso) {
      case _Paso.titulo:
        return 1;
      case _Paso.flyer:
        return 2;
      case _Paso.fechas:
      case _Paso.fechasPreview:
        return 3;
      case _Paso.ubicacion:
      case _Paso.direccionExterna:
        return 4;
      case _Paso.descripcion:
      case _Paso.descripcionPreview:
        return 5;
      case _Paso.tipo:
      case _Paso.tipoManual:
        return 6;
      case _Paso.ingreso:
      case _Paso.ingresoCupo:
        return 7;
      case _Paso.entrada:
        return 8;
      case _Paso.edad:
      case _Paso.restricciones:
        return 9;
      default:
        return 10;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
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
        builder: (_, __) => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: ColoresLocales.degradadoHome,
              stops: const [0.0, 0.25, 0.6, 1.0],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              _header(),
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                  itemCount: _mensajes.length + (_botEscribiendo ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i >= _mensajes.length) return const _TypingBurbuja();
                    return _mensajes[i].build();
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.only(bottom: viewInsets),
                child: _AreaInput(child: _buildInput()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      decoration: BoxDecoration(
        color: ColoresLocales.superficie,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kVioleta,
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
                      'Asistente de eventos',
                      style: GoogleFonts.baloo2(
                        color: ColoresLocales.textoOnFondoClaro,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Creá tu evento charlando',
                      style: GoogleFonts.baloo2(
                        color: ColoresLocales.textoSecundarioOnFondoClaro,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () async {
                  if (await _confirmarSalir() && mounted) {
                    Navigator.of(context).pop();
                  }
                },
                icon: Icon(
                  CupertinoIcons.xmark,
                  color: ColoresLocales.textoSecundarioOnFondoClaro,
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
              backgroundColor: _kVioleta.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation(_kVioleta),
            ),
          ),
        ],
      ),
    );
  }

  // ── Input dinámico ──────────────────────────────────────────────────────────
  Widget _buildInput() {
    if (_procesando && _paso != _Paso.guardando) {
      return const _InputDeshabilitado(texto: 'Un segundo…');
    }
    switch (_paso) {
      case _Paso.titulo:
        return _inputTexto(hint: 'Ej: Noche de Reggaetón', onSend: _onTitulo);
      case _Paso.flyer:
        return _inputFlyer();
      case _Paso.fechas:
        return _inputTexto(
          hint: _fechaInicioPrevia != null
              ? '¿Qué cambiamos? Ej: termina a las 7 am'
              : 'Ej: sábado 25, 23 a 6 am',
          onSend: () => _onFechas(esCorreccion: _fechaInicioPrevia != null),
          multilinea: true,
        );
      case _Paso.fechasPreview:
        return _opciones([
          _OpcionBtn('Están bien 👍', _preguntarUbicacion, primario: true),
          _OpcionBtn('Corregir fecha/hora', () async {
            await _bot([
              'Decime qué corregimos ✏️ (el resto lo dejo igual)',
            ]);
            _irA(_Paso.fechas);
            _inputFocus.requestFocus();
          }),
        ]);
      case _Paso.ubicacion:
        return _opciones([
          _OpcionBtn(
            widget.ciudadLocal != null && widget.ciudadLocal!.trim().isNotEmpty
                ? 'En mi local (${widget.ciudadLocal})'
                : 'En mi local',
            _ubicacionEnLocal,
            primario: true,
            icono: CupertinoIcons.house_fill,
          ),
          _OpcionBtn(
            'En otro lugar',
            _abrirSelectorUbicacion,
            icono: CupertinoIcons.placemark,
          ),
        ]);
      case _Paso.direccionExterna:
        return _inputTexto(
          hint: 'Ej: Av. Colón 1234',
          onSend: _onDireccionExterna,
        );
      case _Paso.descripcion:
        return _inputDescripcion();
      case _Paso.descripcionPreview:
        return _opciones([
          _OpcionBtn('Usar esta ✨', _pedirTipo, primario: true),
          if (_regeneraciones < 3)
            _OpcionBtn(
              'Regenerar (${3 - _regeneraciones})',
              () => _mejorarDescripcion(desdeBorrador: true),
            ),
          _OpcionBtn('Prefiero la mía', () async {
            _datos.descripcion = _descripcionBorrador;
            await _bot(['Dale, usamos la tuya 👌']);
            await _pedirTipo();
          }),
        ]);
      case _Paso.tipo:
        return _opciones([
          _OpcionBtn(
            'Sí, es "${_tipoLabel(_datos.tipo)}"',
            () => _confirmarTipo(_datos.tipo),
            primario: true,
          ),
          _OpcionBtn('Elegir otro', () => _irA(_Paso.tipoManual)),
        ]);
      case _Paso.tipoManual:
        return _gridTipos();
      case _Paso.ingreso:
        return _opciones([
          _OpcionBtn(
            'Pase libre (auto, sin límite)',
            _ingresoPaseLibre,
            primario: true,
            icono: CupertinoIcons.checkmark_seal_fill,
          ),
          _OpcionBtn(
            'Con cupo limitado',
            _ingresoConCupo,
            icono: CupertinoIcons.number,
          ),
          _OpcionBtn(
            'Apruebo yo cada uno (manual)',
            _ingresoManual,
            icono: CupertinoIcons.hand_raised,
          ),
        ]);
      case _Paso.ingresoCupo:
        return _inputCupoIngreso();
      case _Paso.entrada:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _inputTexto(
              hint: 'Pegá acá tu link de PaseShow, Ticketek, etc.',
              onSend: _onEntradaLink,
            ),
            const SizedBox(height: 8),
            _OpcionBtn(
              'No vendo tickets',
              _entradaLibre,
              skip: true,
            ).comoBarra(),
          ],
        );
      case _Paso.edad:
        return _inputEdad();
      case _Paso.restricciones:
        return _inputRestricciones();
      case _Paso.promosPregunta:
        return _opciones([
          _OpcionBtn('Sí, sumar promo', _iniciarPromo, primario: true),
          _OpcionBtn('No, sin promos', _pedirPublicar, skip: true),
        ]);
      case _Paso.promoTitulo:
        return _inputTexto(hint: 'Título de la promo', onSend: _onPromoTitulo);
      case _Paso.promoDescripcion:
        return _inputTexto(
          hint: '¿Qué incluye?',
          onSend: _onPromoDescripcion,
          multilinea: true,
        );
      case _Paso.promoModo:
        return _opciones([
          _OpcionBtn(
            'Individual',
            () => _onPromoModo('individual'),
            primario: true,
          ),
          _OpcionBtn('En squad (grupo)', () => _onPromoModo('squad')),
        ]);
      case _Paso.promoSquad:
        return _inputSquad();
      case _Paso.promoCupos:
        return _inputCuposPromo();
      case _Paso.promoOtra:
        return _opciones([
          _OpcionBtn('Sí, otra promo', _iniciarPromo, primario: true),
          _OpcionBtn('Listo, continuar', _pedirPublicar),
        ]);
      case _Paso.publicar:
        return _OpcionBtn(
          'Publicar evento 🚀',
          _publicar,
          primario: true,
          icono: CupertinoIcons.paperplane_fill,
        ).comoBarra();
      case _Paso.guardando:
        return const _InputDeshabilitado(texto: 'Publicando…');
      case _Paso.felicitacion:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _OpcionBtn(
              'Subir la jerarquía 🚀',
              () {
                Navigator.of(context).pop();
                widget.onSubirJerarquia(_idEventoPublicado);
              },
              primario: true,
              icono: CupertinoIcons.arrow_up_circle_fill,
            ).comoBarra(),
            const SizedBox(height: 8),
            _OpcionBtn(
              'Volver al dashboard',
              () {
                Navigator.of(context).pop();
                widget.onIrHome();
              },
              icono: CupertinoIcons.house_fill,
            ).comoBarra(),
          ],
        );
    }
  }

  Widget _inputTexto({
    required String hint,
    required Future<void> Function() onSend,
    bool multilinea = false,
  }) {
    return Row(
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
    );
  }

  Widget _campoTexto({
    required String hint,
    bool multilinea = false,
    VoidCallback? onSubmit,
    TextInputType? tipoTeclado,
  }) {
    return TextField(
      controller: _input,
      focusNode: _inputFocus,
      minLines: 1,
      maxLines: multilinea ? 4 : 1,
      keyboardType: tipoTeclado,
      textInputAction: multilinea
          ? TextInputAction.newline
          : TextInputAction.send,
      onSubmitted: onSubmit == null ? null : (_) => onSubmit(),
      style: GoogleFonts.baloo2(
        color: ColoresLocales.textoOnFondoClaro,
        fontWeight: FontWeight.w600,
      ),
      cursorColor: _kVioleta,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.baloo2(
          color: ColoresLocales.textoSecundarioOnFondoClaro,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: ColoresLocales.superficieElevada,
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

  Widget _gridTipos() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _kTipos.map((t) {
        return GestureDetector(
          onTap: () => _confirmarTipo(t),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: ColoresLocales.superficie,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: ColoresLocales.bordeSuave),
            ),
            child: Text(
              _tipoLabel(t),
              style: GoogleFonts.baloo2(
                color: ColoresLocales.textoOnFondoClaro,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _inputFlyer() {
    final tiene = _datos.flyerBytes != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _pickFlyer,
          child: tiene
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _datos.flyerBytes!,
                    width: 92,
                    height: 138,
                    fit: BoxFit.cover,
                  ),
                )
              : Container(
                  width: 92,
                  height: 138,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: ColoresLocales.cardLavanda,
                    border: Border.all(color: _kVioleta, width: 1.6),
                  ),
                  child: const Icon(
                    CupertinoIcons.add,
                    color: _kVioleta,
                    size: 28,
                  ),
                ),
        ),
        const SizedBox(height: 12),
        if (tiene)
          Row(
            children: [
              Expanded(child: _OpcionBtn('Cambiar', _pickFlyer)),
              const SizedBox(width: 8),
              Expanded(
                child: _OpcionBtn(
                  'Usar este flyer',
                  _confirmarFlyer,
                  primario: true,
                ),
              ),
            ],
          )
        else
          _OpcionBtn('Elegir imagen', _pickFlyer, primario: true).comoBarra(),
      ],
    );
  }

  Widget _inputDescripcion() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _campoTexto(hint: 'Escribí sobre tu evento…', multilinea: true),
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

  Widget _inputCupoIngreso() {
    final manual = _datos.modoLista == 'manual';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (manual) ...[
          _OpcionBtn(
            'Sin límite de cupo',
            () => _finalizarIngreso(cupo: null),
            primario: true,
          ).comoBarra(),
          const SizedBox(height: 8),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _campoTexto(
                hint: 'Cupo máximo (número)',
                tipoTeclado: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            _BotonEnviar(
              onTap: () {
                final c = int.tryParse(_input.text.trim());
                if (c != null && c > 0) {
                  _input.clear();
                  _finalizarIngreso(cupo: c);
                } else {
                  _snack('Ingresá un cupo válido.');
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _inputEdad() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: _OpcionBtn('Sin restricción', () => _confirmarEdad(null)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _OpcionBtn(
                '+18',
                () => _confirmarEdad(18),
                primario: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _OpcionBtn('+21', () => _confirmarEdad(21))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _campoTexto(
                hint: 'Otra edad (número)',
                tipoTeclado: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            _BotonEnviar(
              onTap: () {
                final e = int.tryParse(_input.text.trim());
                if (e != null && e > 0 && e < 100) {
                  _input.clear();
                  _confirmarEdad(e);
                } else {
                  _snack('Ingresá una edad válida.');
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _inputRestricciones() {
    return StatefulBuilder(
      builder: (_, setLocal) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kRestricciones.map((r) {
                final sel = _restriccionesSel.contains(r);
                return GestureDetector(
                  onTap: () {
                    setLocal(() {
                      if (sel) {
                        _restriccionesSel.remove(r);
                      } else {
                        _restriccionesSel.add(r);
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: sel ? _kVioleta : ColoresLocales.superficie,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sel ? _kVioleta : ColoresLocales.bordeSuave,
                      ),
                    ),
                    child: Text(
                      r,
                      style: GoogleFonts.baloo2(
                        color: sel
                            ? Colors.white
                            : ColoresLocales.textoOnFondoClaro,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            _campoTexto(hint: 'Custom / otro requisito (opcional)'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _OpcionBtn(
                    'Sin requisitos',
                    _confirmarRestricciones,
                    skip: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _OpcionBtn(
                    'Listo',
                    _confirmarRestricciones,
                    primario: true,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _inputSquad() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: _campoNumero(_squadMin, 'Mínimo')),
        const SizedBox(width: 8),
        Expanded(child: _campoNumero(_squadMax, 'Máximo')),
        const SizedBox(width: 8),
        _BotonEnviar(onTap: _onPromoSquad),
      ],
    );
  }

  Widget _campoNumero(TextEditingController c, String hint) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: GoogleFonts.baloo2(
        color: ColoresLocales.textoOnFondoClaro,
        fontWeight: FontWeight.w600,
      ),
      cursorColor: _kVioleta,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.baloo2(
          color: ColoresLocales.textoSecundarioOnFondoClaro,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: ColoresLocales.superficieElevada,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _inputCuposPromo() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _OpcionBtn(
          'Sin límite de cupos',
          () => _finalizarPromo(cupos: null),
          primario: true,
        ).comoBarra(),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _campoTexto(
                hint: 'Cantidad de cupos',
                tipoTeclado: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            _BotonEnviar(
              onTap: () {
                final c = int.tryParse(_input.text.trim());
                if (c != null && c > 0) {
                  _input.clear();
                  _finalizarPromo(cupos: c);
                } else {
                  _snack('Ingresá un número de cupos válido.');
                }
              },
            ),
          ],
        ),
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
      builder: (_) => const _SelectorUbicacionEvento(),
    );
    if (res != null && mounted) _ubicacionExterna(res.$1, res.$2);
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  MENSAJES Y WIDGETS (tema claro locales)
// ════════════════════════════════════════════════════════════════════════════
class _Mensaje {
  final bool esBot;
  final Widget child;
  _Mensaje.bot(this.child) : esBot = true;
  _Mensaje.usuario(this.child) : esBot = false;

  Widget build() {
    final align = esBot ? Alignment.centerLeft : Alignment.centerRight;
    return Align(
      alignment: align,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: esBot ? ColoresLocales.superficie : _kVioleta,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(esBot ? 4 : 16),
            bottomRight: Radius.circular(esBot ? 16 : 4),
          ),
          border: esBot ? Border.all(color: ColoresLocales.bordeSuave) : null,
        ),
        child: child,
      ),
    );
  }
}

class _TextoBurbuja extends StatelessWidget {
  const _TextoBurbuja(this.texto, {required this.esBot});
  final String texto;
  final bool esBot;
  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: GoogleFonts.baloo2(
        color: esBot ? ColoresLocales.textoOnFondoClaro : Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 14.5,
        height: 1.3,
      ),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: ColoresLocales.superficie,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: ColoresLocales.bordeSuave),
        ),
        child: const _PuntosAnimados(),
      ),
    );
  }
}

class _PuntosAnimados extends StatefulWidget {
  const _PuntosAnimados();
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
            final op = (0.3 + 0.7 * (t < 0.5 ? t * 2 : (1 - t) * 2)).clamp(
              0.3,
              1.0,
            );
            return Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kVioleta.withValues(alpha: op),
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
          child: CircularProgressIndicator(strokeWidth: 2, color: _kVioleta),
        ),
        const SizedBox(width: 10),
        Text(
          texto,
          style: GoogleFonts.baloo2(
            color: ColoresLocales.textoOnFondoClaro,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Ficha (fechas / descripción sugerida) dentro de una burbuja del bot.
class _FichaPreview extends StatelessWidget {
  const _FichaPreview({
    required this.icono,
    required this.titulo,
    required this.texto,
  });
  final IconData icono;
  final String titulo;
  final String texto;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icono, size: 15, color: _kVioleta),
            const SizedBox(width: 6),
            Text(
              titulo,
              style: GoogleFonts.baloo2(
                color: _kVioleta,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          texto,
          style: GoogleFonts.baloo2(
            color: ColoresLocales.textoOnFondoClaro,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _FlyerPreview extends StatelessWidget {
  const _FlyerPreview({required this.bytes});
  final Uint8List bytes;
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(bytes, width: 120, height: 180, fit: BoxFit.cover),
    );
  }
}

class _MiniFlyer extends StatelessWidget {
  const _MiniFlyer({required this.bytes});
  final Uint8List bytes;
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(bytes, width: 60, height: 90, fit: BoxFit.cover),
    );
  }
}

/// Chip de confirmación del usuario (lado derecho): pill violeta suave.
class _ChipInfo extends StatelessWidget {
  const _ChipInfo({required this.icon, required this.texto});
  final IconData icon;
  final String texto;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: Colors.white),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            texto,
            style: GoogleFonts.baloo2(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

class _AreaInput extends StatelessWidget {
  const _AreaInput({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: ColoresLocales.superficie,
        border: Border(top: BorderSide(color: ColoresLocales.bordeSuave)),
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
          color: activo ? _kVioleta : ColoresLocales.bordeSuave,
        ),
        child: Icon(
          CupertinoIcons.arrow_up,
          color: activo ? Colors.white : Colors.white70,
          size: 22,
        ),
      ),
    );
  }
}

class _OpcionBtn extends StatelessWidget {
  const _OpcionBtn(
    this.label,
    this.onTap, {
    this.primario = false,
    this.skip = false,
    this.icono,
  });
  final String label;
  final VoidCallback? onTap;
  final bool primario;
  final bool skip;
  final IconData? icono;

  Widget comoBarra() => SizedBox(width: double.infinity, child: this);

  @override
  Widget build(BuildContext context) {
    final activo = onTap != null;
    final Color bg;
    final Color fg;
    final Border? borde;
    if (primario) {
      bg = activo ? _kVioleta : _kVioleta.withValues(alpha: 0.4);
      fg = Colors.white;
      borde = null;
    } else if (skip) {
      bg = Colors.transparent;
      fg = ColoresLocales.textoSecundarioOnFondoClaro;
      borde = null;
    } else {
      bg = ColoresLocales.superficie;
      fg = ColoresLocales.textoOnFondoClaro;
      borde = Border.all(color: ColoresLocales.bordeSuave);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: bg,
            border: borde,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icono != null) ...[
                Icon(icono, size: 18, color: fg),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.baloo2(
                    color: fg,
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
          child: CircularProgressIndicator(strokeWidth: 2, color: _kVioleta),
        ),
        const SizedBox(width: 10),
        Text(
          texto,
          style: GoogleFonts.baloo2(
            color: ColoresLocales.textoSecundarioOnFondoClaro,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── Selector provincia + ciudad (evento externo) ────────────────────────────
class _SelectorUbicacionEvento extends StatefulWidget {
  const _SelectorUbicacionEvento();
  @override
  State<_SelectorUbicacionEvento> createState() =>
      _SelectorUbicacionEventoState();
}

class _SelectorUbicacionEventoState extends State<_SelectorUbicacionEvento> {
  static const _provincias = ['Córdoba'];
  static const _ciudades = [
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

  String _provincia = 'Córdoba';
  String _ciudad = 'Córdoba capital';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: ColoresLocales.superficie,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '¿Dónde es el evento?',
            style: GoogleFonts.baloo2(
              color: ColoresLocales.textoOnFondoClaro,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 16),
          _dropdown(
            label: 'Provincia',
            value: _provincia,
            items: _provincias,
            onChanged: (v) => setState(() => _provincia = v!),
          ),
          const SizedBox(height: 12),
          _dropdown(
            label: 'Ciudad',
            value: _ciudad,
            items: _ciudades,
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
      initialValue: items.contains(value) ? value : items.first,
      isExpanded: true,
      dropdownColor: ColoresLocales.superficie,
      style: GoogleFonts.baloo2(
        color: ColoresLocales.textoOnFondoClaro,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.baloo2(
          color: ColoresLocales.textoSecundarioOnFondoClaro,
        ),
        filled: true,
        fillColor: ColoresLocales.superficieElevada,
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
