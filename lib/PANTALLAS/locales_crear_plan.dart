library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../core/comprimir_imagen_storage.dart';
import '../core/constants.dart';
import '../core/planes_presets.dart';
import '../core/servicio_planes_locales.dart';
import '../core/supabase_client.dart';

/// Look dark del chatbot (independiente del tema claro de locales).
const _fondo = Color(0xFF121212);
const _marca = ColoresLocales.acentoVioletaMarca;
const _textoSec = Color(0xFF9CA3AF);

class LocalesCrearPlan extends StatefulWidget {
  const LocalesCrearPlan({super.key});

  @override
  State<LocalesCrearPlan> createState() => _LocalesCrearPlanState();
}

enum _PasoPlan {
  titulo,
  descripcion,
  descripcionPreview,
  fondo,
  fechas,
  fechasPreview,
  union,
  contacto,
  resumen,
  guardando,
  felicitacion,
}

class _LocalesCrearPlanState extends State<LocalesCrearPlan> {
  final _srv = ServicioPlanesLocales.instancia;
  final _picker = ImagePicker();
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _contactoTituloInput = TextEditingController(text: 'Contactar');
  final _contactoValorInput = TextEditingController();
  final _focus = FocusNode();

  // Organizadores: elegir local adherido o ubicación custom.
  bool _cargandoPerfil = true;
  bool _esOrganizadorEventos = false;
  bool _esUbicacionCustom = false;
  String? _idLocalDestino;
  final _ubicacionCustomCtrl = TextEditingController();
  final _urlMapsCustomCtrl = TextEditingController();

  final List<_MensajePlan> _mensajes = <_MensajePlan>[];

  String _titulo = '';
  String _descripcion = '';
  DateTime _inicio = DateTime.now().add(const Duration(days: 7));
  DateTime? _fin;
  String _modo = 'auto';
  int? _cupo;
  int? _edadMinima;
  bool _permiteSquads = true;
  String? _contacto;
  String? _contactoTitulo;
  String _contactoModo = 'contactar';
  String _presetAsset = fondosPlanesPreset.first.asset;
  XFile? _imagen;
  final String _nombreOrganizador = 'Tu local';

  _PasoPlan _paso = _PasoPlan.titulo;
  bool _botEscribiendo = false;
  bool _procesando = false;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    unawaited(_arrancar());
    unawaited(_cargarPerfilOrganizador());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    _contactoTituloInput.dispose();
    _contactoValorInput.dispose();
    _focus.dispose();
    _ubicacionCustomCtrl.dispose();
    _urlMapsCustomCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarPerfilOrganizador() async {
    try {
      final uid = _srv.miUid;
      if (uid == null) return;

      final res = await ServicioSupabase()
          .cliente
          .from('perfiles_locales')
          .select('es_organizador_eventos')
          .eq('id', uid)
          .maybeSingle();

      final esOrg = res?['es_organizador_eventos'] == true;
      if (!mounted) return;
      setState(() {
        _esOrganizadorEventos = esOrg;
        _esUbicacionCustom = esOrg;
        _idLocalDestino = uid;
        _cargandoPerfil = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargandoPerfil = false);
    }
  }

  Future<void> _arrancar() async {
    await _bot([
      'Vamos a crear un plan para tu local 🍻',
      'Te guío paso a paso. Sale a nombre de tu local, puede durar hasta 45 días, y la gente se suma libre o con tu aprobación.',
      '¿Cómo querés que se llame?',
    ]);
    _focus.requestFocus();
  }

  void _scrollFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _bot(List<String> textos) async {
    setState(() => _procesando = true);
    for (final t in textos) {
      if (!mounted) return;
      setState(() => _botEscribiendo = true);
      _scrollFinal();
      await Future<void>.delayed(const Duration(milliseconds: 820));
      if (!mounted) return;
      setState(() {
        _botEscribiendo = false;
        _mensajes.add(_MensajePlan.bot(_TextoBurbujaPlan(t, esBot: true)));
      });
      _scrollFinal();
      await Future<void>.delayed(const Duration(milliseconds: 90));
    }
    if (mounted) setState(() => _procesando = false);
  }

  void _usuarioTexto(String texto) {
    setState(
      () => _mensajes.add(
        _MensajePlan.usuario(_TextoBurbujaPlan(texto, esBot: false)),
      ),
    );
    _scrollFinal();
  }

  void _usuarioWidget(Widget child) {
    setState(() => _mensajes.add(_MensajePlan.usuario(child)));
    _scrollFinal();
  }

  void _irA(_PasoPlan paso) {
    setState(() => _paso = paso);
    _scrollFinal();
  }

  Future<void> _onTexto() async {
    final v = _input.text.trim();
    if (v.isEmpty || _guardando || _procesando || _botEscribiendo) return;
    _input.clear();
    switch (_paso) {
      case _PasoPlan.titulo:
        if (v.length < 3) {
          _toast('El nombre tiene que tener al menos 3 caracteres.');
          return;
        }
        _titulo = v;
        _usuarioTexto(v);
        await _bot([
          'Buena elección 👍',
          'Contame en pocas líneas qué se hace y por qué alguien se sumaría.',
          'Ej: birritas tranqui, previa con música, merienda para charlar…',
        ]);
        _irA(_PasoPlan.descripcion);
        _focus.requestFocus();
        break;
      case _PasoPlan.descripcion:
        if (v.length < 8) {
          _toast('Sumale un poquito más de contexto.');
          return;
        }
        _descripcion = v;
        _usuarioTexto(v);
        await _bot([
          'Buena, ya se entiende 😊',
          'Quedó así:\n\n**$_titulo**\n$_descripcion',
          '¿Está bien o lo corregimos?',
        ]);
        _irA(_PasoPlan.descripcionPreview);
        break;
      case _PasoPlan.contacto:
        _contactoValorInput.text = v;
        await _confirmarContacto();
        break;
      default:
        break;
    }
  }

  Future<void> _confirmarDescripcion() async {
    if (_procesando || _botEscribiendo) return;
    _usuarioTexto('Está bien');
    await _bot(['Ahora elegí un fondo o subí una portada 🎨']);
    _irA(_PasoPlan.fondo);
  }

  Future<void> _corregirDescripcion() async {
    if (_procesando || _botEscribiendo) return;
    _usuarioTexto('Corregir');
    await _bot(['Dale, reescribí la descripción y la vemos de nuevo ✏️']);
    _irA(_PasoPlan.descripcion);
    _focus.requestFocus();
  }

  Future<void> _seleccionarFondo(String asset) async {
    if (_procesando || _botEscribiendo) return;
    final preset = fondosPlanesPreset.firstWhere(
      (p) => p.asset == asset,
      orElse: () => fondosPlanesPreset.first,
    );
    setState(() {
      _presetAsset = asset;
      _imagen = null;
    });
    _usuarioWidget(
      _ChipRespuesta(icono: CupertinoIcons.photo, texto: preset.nombre),
    );
    await _bot([
      'Buena elección 🎨',
      'Ahora pongamos cuándo arranca y, si querés, cuándo termina 🕒',
    ]);
    _irA(_PasoPlan.fechas);
  }

  Future<void> _pickImagen() async {
    if (_procesando || _botEscribiendo) return;
    final img = await _picker.pickImage(source: ImageSource.gallery);
    if (img == null) return;
    setState(() => _imagen = img);
    _usuarioWidget(
      const _ChipRespuesta(
        icono: CupertinoIcons.photo_fill_on_rectangle_fill,
        texto: 'Portada custom seleccionada',
      ),
    );
    await _bot([
      'Portada lista ✨',
      'Ahora pongamos cuándo arranca y, si querés, cuándo termina 🕒',
    ]);
    _irA(_PasoPlan.fechas);
  }

  Future<void> _pickFecha({required bool inicio}) async {
    final ahora = DateTime.now();
    var base = inicio
        ? _inicio
        : (_fin ?? _inicio.add(const Duration(hours: 3)));
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => Container(
        height: 310,
        color: const Color(0xFF1B1B1B),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Listo'),
              ),
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.dateAndTime,
                initialDateTime: base.isBefore(ahora) ? ahora : base,
                minimumDate: ahora.subtract(const Duration(minutes: 10)),
                maximumDate: ahora.add(const Duration(days: 45)),
                use24hFormat: true,
                onDateTimeChanged: (v) => base = v,
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      if (inicio) {
        _inicio = base;
        if (_fin != null && _fin!.isBefore(_inicio)) _fin = null;
      } else {
        _fin = base;
      }
    });
  }

  Future<void> _confirmarFechas() async {
    if (_procesando || _botEscribiendo) return;
    if (_fin != null && _fin!.isBefore(_inicio)) {
      _toast('La fecha de fin no puede ser antes del inicio.');
      return;
    }
    final resumen =
        '${_fmt(_inicio)}${_fin == null ? '' : ' · fin ${_fmt(_fin!)}'}';
    _usuarioWidget(
      _ChipRespuesta(icono: CupertinoIcons.calendar, texto: resumen),
    );
    await _bot([
      'Quedó agendado así:\n\n**$resumen**',
      '¿Están bien las fechas o las corregimos?',
    ]);
    _irA(_PasoPlan.fechasPreview);
  }

  Future<void> _aceptarFechasPreview() async {
    if (_procesando || _botEscribiendo) return;
    _usuarioTexto('Están bien');
    await _bot([
      'Listo. Ahora definamos cómo se suma la gente 🚪',
      'Puede ser entrada libre o con tu aprobación, una por una.',
    ]);
    _irA(_PasoPlan.union);
  }

  Future<void> _corregirFechas() async {
    if (_procesando || _botEscribiendo) return;
    _usuarioTexto('Corregir');
    await _bot(['Dale, ajustá inicio o fin y confirmá de nuevo 🕒']);
    _irA(_PasoPlan.fechas);
  }

  Future<void> _confirmarUnion() async {
    if (_procesando || _botEscribiendo) return;
    _usuarioWidget(
      _ChipRespuesta(
        icono: CupertinoIcons.person_2_fill,
        texto:
            '${_modo == 'manual' ? 'Con aprobación' : 'Entrada libre'} · ${_cupo == null ? 'sin cupo' : '${_cupo!} cupos'} · ${_permiteSquads ? 'squads ok' : 'solo personas'}',
      ),
    );
    await _bot([
      'Último detalle opcional 📲',
      'Elegí **contactar organizador** (WhatsApp/IG) o **vaquita para el organizador** (alias o link).',
      'Solo una opción. Si no hace falta, saltealo.',
    ]);
    _irA(_PasoPlan.contacto);
    _focus.requestFocus();
  }

  Future<void> _saltearContacto() async {
    if (_procesando || _botEscribiendo) return;
    _contacto = null;
    _contactoTitulo = null;
    _contactoTituloInput.text = _contactoTituloSugerido;
    _contactoValorInput.clear();
    _usuarioTexto('Sin contacto opcional');
    await _mostrarResumen();
  }

  String get _contactoTituloSugerido =>
      _contactoModo == 'vaquita' || _contactoModo == 'vaquita' ? 'Vaquita' : 'Contactar';

  void _cambiarContactoModo(String modo) {
    setState(() {
      _contactoModo = (modo == 'vaquita' || modo == 'colaborar') ? 'vaquita' : 'contactar';
      final actual = _contactoTituloInput.text.trim();
      if (actual.isEmpty || actual == 'Contactar' || actual == 'Colaborar' || actual == 'Vaquita') {
        _contactoTituloInput.text = _contactoTituloSugerido;
      }
    });
  }

  Future<void> _confirmarContacto() async {
    if (_procesando || _botEscribiendo) return;
    final valor = _contactoValorInput.text.trim();
    if (valor.length < 3) {
      _toast('Agregá un dato de contacto o saltealo.');
      return;
    }
    final titulo = _contactoTituloInput.text.trim();
    _contactoTitulo = titulo.isEmpty ? _contactoTituloSugerido : titulo;
    _contacto = valor;
    _usuarioWidget(
      _ChipRespuesta(
        icono: _contactoModo == 'vaquita'
            ? CupertinoIcons.link
            : CupertinoIcons.chat_bubble_2,
        texto: '${_contactoTitulo!}: $valor',
      ),
    );
    await _mostrarResumen();
  }

  Future<void> _mostrarResumen() async {
    await _bot([
      'Listo, ya tenemos el plan armado 🥂',
      'Revisá el resumen y, si está todo bien, lo publicamos.',
    ]);
    _irA(_PasoPlan.resumen);
  }

  Future<void> _guardar() async {
    if (_titulo.length < 3 || _descripcion.length < 8) {
      _toast('Faltan datos del plan.');
      return;
    }
    if (_srv.miUid == null) {
      _toast('Tu sesión expiró. Volvé a entrar.');
      return;
    }
    if (_cargandoPerfil) {
      _toast('Un segundo… cargando tu perfil.');
      return;
    }
    if (_inicio.isAfter(DateTime.now().add(const Duration(days: 45)))) {
      _toast('Los planes duran 45 días. Crealo más cerca de la fecha.');
      return;
    }
    if (_esOrganizadorEventos) {
      final ubic = _ubicacionCustomCtrl.text.trim();
      final url = _urlMapsCustomCtrl.text.trim();
      if (ubic.isEmpty || ubic.length < 3) {
        _toast('Sumá dónde es el plan.');
        return;
      }
      if (url.isEmpty ||
          !RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) {
        _toast('Pegá un link de Google Maps válido.');
        return;
      }
    }
    setState(() {
      _guardando = true;
      _procesando = true;
      _paso = _PasoPlan.guardando;
    });
    _usuarioTexto('Publicar plan');
    await _bot(['Publicando tu plan…']);
    setState(() => _procesando = true);
    try {
      String? portada;
      if (_imagen != null) {
        final comprimida = await comprimirDesdeXFile(
          _imagen!,
          perfil: PerfilImagenStorage.portadaPlan,
        );
        portada = await _srv.subirPortada(
          idTemporal:
              '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}',
          bytes: comprimida.bytes,
          ext: comprimida.extension,
        );
      }
      portada ??= _presetAsset;
      final id = await _srv.crear(
        titulo: _titulo,
        descripcion: _descripcion,
        fechaInicio: _inicio,
        fechaFin: _fin,
        modoLista: _modo,
        cupoMax: _cupo,
        tipoOrganizador: 'local',
        contactoAnfitrion: _contacto,
        contactoTitulo: _contactoTitulo,
        contactoModo: _contactoModo,
        portadaPath: portada,
        colorHex: '#111111',
        permiteSquads: _permiteSquads,
        edadMinima: _edadMinima,
        idLocalDestino: _idLocalDestino,
        esUbicacionCustom: _esUbicacionCustom,
        ubicacionCustom: _esUbicacionCustom
            ? _ubicacionCustomCtrl.text.trim()
            : null,
        urlMapsCustom: _esUbicacionCustom
            ? _urlMapsCustomCtrl.text.trim()
            : null,
      );
      if (!mounted) return;
      if (id == null) {
        setState(() {
          _guardando = false;
          _procesando = false;
        });
        _toast('No se pudo crear el plan.');
        _irA(_PasoPlan.resumen);
        return;
      }
      await _bot([
        '¡Listo! Plan publicado 🍻',
        'Ya está visible para que la comunidad se sume a tu local.',
      ]);
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _procesando = false;
      });
      _irA(_PasoPlan.felicitacion);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _procesando = false;
      });
      _toast(_srv.mensajeError(e, accion: 'crear el plan'));
      _irA(_PasoPlan.resumen);
    }
  }

  void _toast(String msg) {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        content: Text(msg),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Ok'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmarSalir() async {
    if (_paso == _PasoPlan.felicitacion) return true;
    final r = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(
          '¿Salir del asistente?',
          style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Vas a perder lo que cargaste acá. ¿Seguro querés salir?',
          style: GoogleFonts.baloo2(height: 1.3),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Seguir acá',
              style: GoogleFonts.baloo2(
                color: _marca,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Salir', style: GoogleFonts.baloo2()),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  Future<void> _intentarSalir() async {
    if (await _confirmarSalir() && mounted) {
      Navigator.of(context).pop();
    }
  }

  int get _pasoIndice {
    switch (_paso) {
      case _PasoPlan.titulo:
        return 1;
      case _PasoPlan.descripcion:
      case _PasoPlan.descripcionPreview:
        return 2;
      case _PasoPlan.fondo:
        return 3;
      case _PasoPlan.fechas:
      case _PasoPlan.fechasPreview:
        return 4;
      case _PasoPlan.union:
        return 5;
      case _PasoPlan.contacto:
        return 6;
      case _PasoPlan.resumen:
      case _PasoPlan.guardando:
        return 7;
      case _PasoPlan.felicitacion:
        return 8;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _intentarSalir();
      },
      child: CupertinoPageScaffold(
        backgroundColor: _fondo,
        child: SafeArea(
          child: Column(
            children: [
              _HeaderPlan(paso: _pasoIndice, onClose: _intentarSalir),
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                  itemCount: _mensajes.length + (_botEscribiendo ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i >= _mensajes.length) return const _TypingPlan();
                    return _mensajes[i].build();
                  },
                ),
              ),
              _AreaInputPlan(child: _buildInput()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInput() {
    if (_guardando || _paso == _PasoPlan.guardando) {
      return const _InputDeshabilitadoPlan(texto: 'Publicando…');
    }
    if (_procesando || _botEscribiendo) {
      return const _InputDeshabilitadoPlan(texto: 'Un segundo…');
    }
    switch (_paso) {
      case _PasoPlan.titulo:
        return _InputTextoPlan(
          controller: _input,
          focus: _focus,
          hint: 'Nombre del plan',
          onSend: _onTexto,
        );
      case _PasoPlan.descripcion:
        return _InputTextoPlan(
          controller: _input,
          focus: _focus,
          hint: 'Descripción breve',
          maxLines: 3,
          onSend: _onTexto,
        );
      case _PasoPlan.descripcionPreview:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _OpcionBarraPlan(
              texto: 'Está bien 👍',
              icono: CupertinoIcons.checkmark_circle_fill,
              primario: true,
              onTap: _confirmarDescripcion,
            ),
            const SizedBox(height: 8),
            _OpcionBarraPlan(
              texto: 'Corregir',
              icono: CupertinoIcons.pencil,
              onTap: _corregirDescripcion,
            ),
          ],
        );
      case _PasoPlan.fondo:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 190,
              child: GridView.builder(
                itemCount: fondosPlanesPreset.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.7,
                ),
                itemBuilder: (_, i) {
                  final preset = fondosPlanesPreset[i];
                  final url = ServicioSupabase().urlPortadaPlan(preset.asset);
                  return GestureDetector(
                    onTap: () => _seleccionarFondo(preset.asset),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (url != null)
                            Image.network(
                              url,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const ColoredBox(color: Color(0xFF252525)),
                            )
                          else
                            const ColoredBox(color: Color(0xFF252525)),
                          Container(
                            color: Colors.black.withValues(alpha: 0.35),
                          ),
                          Align(
                            alignment: Alignment.bottomLeft,
                            child: Padding(
                              padding: const EdgeInsets.all(9),
                              child: Text(
                                '${preset.emoji} ${preset.nombre}',
                                style: GoogleFonts.baloo2(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 9),
            _OpcionBarraPlan(
              texto: 'Subir portada custom',
              icono: CupertinoIcons.photo_on_rectangle,
              onTap: _pickImagen,
            ),
          ],
        );
      case _PasoPlan.fechas:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _OpcionBarraPlan(
              texto: 'Arranca · ${_fmt(_inicio)}',
              icono: CupertinoIcons.calendar,
              onTap: () => _pickFecha(inicio: true),
            ),
            const SizedBox(height: 8),
            _OpcionBarraPlan(
              texto: _fin == null ? 'Agregar fin' : 'Termina · ${_fmt(_fin!)}',
              icono: CupertinoIcons.clock,
              onTap: () => _pickFecha(inicio: false),
            ),
            const SizedBox(height: 8),
            _OpcionBarraPlan(
              texto: 'Confirmar fechas',
              icono: CupertinoIcons.checkmark_circle_fill,
              primario: true,
              onTap: _confirmarFechas,
            ),
          ],
        );
      case _PasoPlan.fechasPreview:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _OpcionBarraPlan(
              texto: 'Están bien 👍',
              icono: CupertinoIcons.checkmark_circle_fill,
              primario: true,
              onTap: _aceptarFechasPreview,
            ),
            const SizedBox(height: 8),
            _OpcionBarraPlan(
              texto: 'Corregir fechas',
              icono: CupertinoIcons.pencil,
              onTap: _corregirFechas,
            ),
          ],
        );
      case _PasoPlan.union:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: _ChoicePlan(
                    texto: 'Entrada libre',
                    selected: _modo == 'auto',
                    onTap: () => setState(() => _modo = 'auto'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ChoicePlan(
                    texto: 'Yo acepto',
                    selected: _modo == 'manual',
                    onTap: () => setState(() => _modo = 'manual'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _StepperPlan(
                    label: 'Cupo',
                    value: _cupo,
                    onChanged: (v) => setState(() => _cupo = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StepperPlan(
                    label: 'Edad mín.',
                    value: _edadMinima,
                    min: 13,
                    onChanged: (v) => setState(() => _edadMinima = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _OpcionBarraPlan(
              texto: _permiteSquads ? 'Permite squads' : 'Solo personas',
              icono: CupertinoIcons.person_3_fill,
              onTap: () => setState(() => _permiteSquads = !_permiteSquads),
            ),
            const SizedBox(height: 8),
            if (_esOrganizadorEventos) ...[
              CupertinoTextField(
                controller: _ubicacionCustomCtrl,
                placeholder: '¿Dónde es? (ej: descampado / sunset)',
                style: const TextStyle(color: Colors.white),
                placeholderStyle:
                    const TextStyle(color: Color(0xFF9CA3AF)),
                onChanged: (_) => setState(() {}),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              const SizedBox(height: 10),
              CupertinoTextField(
                controller: _urlMapsCustomCtrl,
                placeholder: 'Link de Google Maps',
                style: const TextStyle(color: Colors.white),
                placeholderStyle:
                    const TextStyle(color: Color(0xFF9CA3AF)),
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {}),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              const SizedBox(height: 8),
            ],
            _OpcionBarraPlan(
              texto: 'Confirmar unión',
              icono: CupertinoIcons.checkmark_circle_fill,
              primario: true,
              onTap: _confirmarUnion,
            ),
          ],
        );
      case _PasoPlan.contacto:
        return _ContactoPlanCard(
          tituloController: _contactoTituloInput,
          valorController: _contactoValorInput,
          modo: _contactoModo,
          onModo: _cambiarContactoModo,
          onConfirmar: _confirmarContacto,
          onSaltear: _saltearContacto,
        );
      case _PasoPlan.resumen:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ResumenPlanCard(
              titulo: _titulo,
              descripcion: _descripcion,
              local: 'Tu local',
              ciudad: '',
              fecha:
                  '${_fmt(_inicio)}${_fin == null ? '' : ' · fin ${_fmt(_fin!)}'}',
              ingreso: _modo == 'manual' ? 'Con aprobación' : 'Entrada libre',
              cupo: _cupo == null ? 'Sin cupo' : '${_cupo!} cupos',
              organizador: _nombreOrganizador,
              contacto: _contacto,
              contactoTitulo: _contactoTitulo,
              contactoModo: _contactoModo,
            ),
            const SizedBox(height: 8),
            _OpcionBarraPlan(
              texto: 'Publicar plan',
              icono: CupertinoIcons.paperplane_fill,
              primario: true,
              onTap: _guardar,
            ),
          ],
        );
      case _PasoPlan.felicitacion:
        return _OpcionBarraPlan(
          texto: 'Ver planes',
          icono: CupertinoIcons.square_grid_2x2_fill,
          primario: true,
          onTap: () => Navigator.of(context).pop(true),
        );
      default:
        return const _InputDeshabilitadoPlan(texto: 'Un segundo…');
    }
  }
}

class _HeaderPlan extends StatelessWidget {
  const _HeaderPlan({required this.paso, required this.onClose});
  final int paso;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: _marca, shape: BoxShape.circle),
              child: const Icon(
                CupertinoIcons.sparkles,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Asistente de planes',
                    style: GoogleFonts.baloo2(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Plan para tu local, sin vueltas',
                    style: GoogleFonts.baloo2(fontSize: 12, color: _textoSec),
                  ),
                ],
              ),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: onClose,
              child: Icon(
                CupertinoIcons.xmark,
                color: Colors.white.withValues(alpha: 0.72),
                size: 20,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: paso / 8,
            minHeight: 5,
            backgroundColor: Colors.white.withValues(alpha: 0.10),
            valueColor: AlwaysStoppedAnimation(_marca),
          ),
        ),
      ],
    ),
  );
}

class _MensajePlan {
  const _MensajePlan._(this.child, this.esBot);
  factory _MensajePlan.bot(Widget child) => _MensajePlan._(child, true);
  factory _MensajePlan.usuario(Widget child) => _MensajePlan._(child, false);

  final Widget child;
  final bool esBot;

  Widget build() => Align(
    alignment: esBot ? Alignment.centerLeft : Alignment.centerRight,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 310),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: esBot ? Colors.white.withValues(alpha: 0.08) : _marca,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(17),
          topRight: const Radius.circular(17),
          bottomLeft: Radius.circular(esBot ? 5 : 17),
          bottomRight: Radius.circular(esBot ? 17 : 5),
        ),
      ),
      child: child,
    ),
  );
}

class _TextoBurbujaPlan extends StatelessWidget {
  const _TextoBurbujaPlan(this.texto, {required this.esBot});
  final String texto;
  final bool esBot;

  static final _boldRe = RegExp(r'\*\*(.+?)\*\*');

  @override
  Widget build(BuildContext context) {
    final color = Colors.white.withValues(alpha: esBot ? 0.92 : 1);
    final base = GoogleFonts.baloo2(
      fontSize: 14.5,
      height: 1.25,
      fontWeight: FontWeight.w700,
      color: color,
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

class _TypingPlan extends StatelessWidget {
  const _TypingPlan();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(17),
          topRight: Radius.circular(17),
          bottomLeft: Radius.circular(5),
          bottomRight: Radius.circular(17),
        ),
      ),
      child: const _PuntosAnimadosPlan(),
    ),
  );
}

class _PuntosAnimadosPlan extends StatefulWidget {
  const _PuntosAnimadosPlan();

  @override
  State<_PuntosAnimadosPlan> createState() => _PuntosAnimadosPlanState();
}

class _PuntosAnimadosPlanState extends State<_PuntosAnimadosPlan>
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
      builder: (_, _) {
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
                color: _marca.withValues(alpha: op),
              ),
            );
          }),
        );
      },
    );
  }
}

class _InputDeshabilitadoPlan extends StatelessWidget {
  const _InputDeshabilitadoPlan({required this.texto});
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: _marca),
        ),
        const SizedBox(width: 10),
        Text(
          texto,
          style: GoogleFonts.baloo2(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: _textoSec,
          ),
        ),
      ],
    );
  }
}

class _AreaInputPlan extends StatelessWidget {
  const _AreaInputPlan({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final keyboardAbierto = MediaQuery.viewInsetsOf(context).bottom > 0;
    final safe = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, keyboardAbierto ? 6 : safe + 10),
      decoration: BoxDecoration(
        color: const Color(0xFF151515).withValues(alpha: 0.98),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: 20,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _InputTextoPlan extends StatelessWidget {
  const _InputTextoPlan({
    required this.controller,
    required this.focus,
    required this.hint,
    required this.onSend,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final String hint;
  final VoidCallback onSend;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: CupertinoTextField(
          controller: controller,
          focusNode: focus,
          placeholder: hint,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white),
          placeholderStyle: TextStyle(color: _textoSec.withValues(alpha: 0.72)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(17),
          ),
          onSubmitted: (_) => onSend(),
        ),
      ),
      const SizedBox(width: 8),
      CupertinoButton(
        padding: const EdgeInsets.all(12),
        color: _marca,
        borderRadius: BorderRadius.circular(16),
        onPressed: onSend,
        child: const Icon(
          CupertinoIcons.arrow_up,
          color: Colors.white,
          size: 18,
        ),
      ),
    ],
  );
}

class _ContactoPlanCard extends StatelessWidget {
  const _ContactoPlanCard({
    required this.tituloController,
    required this.valorController,
    required this.modo,
    required this.onModo,
    required this.onConfirmar,
    required this.onSaltear,
  });

  final TextEditingController tituloController;
  final TextEditingController valorController;
  final String modo;
  final ValueChanged<String> onModo;
  final VoidCallback onConfirmar;
  final VoidCallback onSaltear;

  @override
  Widget build(BuildContext context) {
    final vaquita = modo == 'vaquita' || modo == 'colaborar';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _ChoicePlan(
                  texto: 'Contactar',
                  selected: !vaquita,
                  onTap: () => onModo('contactar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ChoicePlan(
                  texto: 'Vaquita',
                  selected: vaquita,
                  onTap: () => onModo('vaquita'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Título',
            style: GoogleFonts.baloo2(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _textoSec,
            ),
          ),
          const SizedBox(height: 5),
          _CampoContactoPlan(
            controller: tituloController,
            placeholder: vaquita ? 'alias o link' : 'Ej: Contacto',
            textInputAction: TextInputAction.next,
            maxLength: 50,
          ),
          const SizedBox(height: 10),
          Text(
            'Dato visible',
            style: GoogleFonts.baloo2(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _textoSec,
            ),
          ),
          const SizedBox(height: 5),
          _CampoContactoPlan(
            controller: valorController,
            placeholder: vaquita
                ? 'Ej: link, alias o mail'
                : 'Ej: WhatsApp o Instagram',
            onSubmitted: (_) => onConfirmar(),
          ),
          const SizedBox(height: 10),
          _OpcionBarraPlan(
            texto: 'Confirmar contacto',
            icono: CupertinoIcons.checkmark_circle_fill,
            primario: true,
            onTap: onConfirmar,
          ),
          const SizedBox(height: 8),
          _OpcionBarraPlan(
            texto: 'Saltear contacto',
            icono: CupertinoIcons.forward,
            skip: true,
            onTap: onSaltear,
          ),
        ],
      ),
    );
  }
}

class _CampoContactoPlan extends StatelessWidget {
  const _CampoContactoPlan({
    required this.controller,
    required this.placeholder,
    this.textInputAction,
    this.onSubmitted,
    this.maxLength = 80,
  });

  final TextEditingController controller;
  final String placeholder;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final int maxLength;

  @override
  Widget build(BuildContext context) => CupertinoTextField(
    controller: controller,
    placeholder: placeholder,
    maxLength: maxLength,
    textInputAction: textInputAction,
    onSubmitted: onSubmitted,
    style: const TextStyle(color: Colors.white),
    placeholderStyle: TextStyle(color: _textoSec.withValues(alpha: 0.74)),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
    ),
  );
}

class _ChipRespuesta extends StatelessWidget {
  const _ChipRespuesta({required this.icono, required this.texto});
  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icono, color: Colors.white, size: 16),
      const SizedBox(width: 7),
      Flexible(
        child: Text(
          texto,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.baloo2(
            fontSize: 13.5,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ),
    ],
  );
}

class _OpcionBarraPlan extends StatelessWidget {
  const _OpcionBarraPlan({
    required this.texto,
    required this.icono,
    required this.onTap,
    this.primario = false,
    this.skip = false,
  });

  final String texto;
  final IconData icono;
  final VoidCallback onTap;
  final bool primario;
  final bool skip;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    if (primario) {
      bg = _marca;
      fg = Colors.white;
    } else if (skip) {
      bg = Colors.transparent;
      fg = _textoSec;
    } else {
      bg = Colors.white.withValues(alpha: 0.08);
      fg = Colors.white;
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icono, color: fg, size: 17),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                texto,
                style: GoogleFonts.baloo2(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoicePlan extends StatelessWidget {
  const _ChoicePlan({
    required this.texto,
    required this.selected,
    required this.onTap,
  });
  final String texto;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: selected ? _marca : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        texto,
        textAlign: TextAlign.center,
        style: GoogleFonts.baloo2(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    ),
  );
}

class _StepperPlan extends StatelessWidget {
  const _StepperPlan({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 1,
  });

  final String label;
  final int? value;
  final int min;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '$label: ${value ?? 'no'}',
            style: GoogleFonts.baloo2(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
        GestureDetector(
          onTap: () {
            if (value == null || value! <= min) {
              onChanged(null);
            } else {
              onChanged(value! - 1);
            }
          },
          child: const Icon(CupertinoIcons.minus_circle, color: Colors.white),
        ),
        const SizedBox(width: 9),
        GestureDetector(
          onTap: () => onChanged((value ?? (min - 1)) + 1),
          child: const Icon(
            CupertinoIcons.plus_circle_fill,
            color: Colors.white,
          ),
        ),
      ],
    ),
  );
}

class _ResumenPlanCard extends StatelessWidget {
  const _ResumenPlanCard({
    required this.titulo,
    required this.descripcion,
    required this.local,
    required this.ciudad,
    required this.fecha,
    required this.ingreso,
    required this.cupo,
    required this.organizador,
    this.contacto,
    this.contactoTitulo,
    this.contactoModo = 'contactar',
  });

  final String titulo;
  final String descripcion;
  final String local;
  final String ciudad;
  final String fecha;
  final String ingreso;
  final String cupo;
  final String organizador;
  final String? contacto;
  final String? contactoTitulo;
  final String contactoModo;

  @override
  Widget build(BuildContext context) {
    final contactoValor = (contacto ?? '').trim();
    final tituloContacto =
        (contactoTitulo ??
                ((contactoModo == 'vaquita' || contactoModo == 'colaborar') ? 'Vaquita' : 'Contactar'))
            .trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: GoogleFonts.baloo2(
              fontSize: 18,
              height: 1,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            descripcion,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.baloo2(fontSize: 12.5, color: _textoSec),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _PillPlan('Organiza: $organizador'),
              if (ciudad.trim().isEmpty)
                _PillPlan(local)
              else
                _PillPlan('$local · $ciudad'),
              _PillPlan(fecha),
              _PillPlan(ingreso),
              _PillPlan(cupo),
              if (contactoValor.isNotEmpty)
                _PillPlan('$tituloContacto: $contactoValor'),
            ],
          ),
        ],
      ),
    );
  }
}

class _PillPlan extends StatelessWidget {
  const _PillPlan(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFE5E7EB).withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      texto,
      style: GoogleFonts.baloo2(
        fontSize: 10.5,
        fontWeight: FontWeight.w900,
        color: Colors.white.withValues(alpha: 0.9),
      ),
    ),
  );
}

String _fmt(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.day}/${d.month} ${two(d.hour)}:${two(d.minute)}';
}
