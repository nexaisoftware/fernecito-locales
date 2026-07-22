import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/constants.dart';
import '../core/colores_staff.dart';
import '../widgets/scaffold_staff.dart';
import '../widgets/tema_locales_scope.dart';
import '../core/config_validacion_codigo.dart';
import '../core/evento_activo.dart';
import '../core/permisos_staff_validar.dart';
import '../core/servicio_edges_eventos.dart';
import '../core/supabase_client.dart';

String _fmtHoraStatic(DateTime dt) {
  final local = dt.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// Timestamps de Supabase (timestamptz) → UTC para comparar ventanas de promo.
DateTime? _parseFechaUtc(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw.toUtc();
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  final d = DateTime.tryParse(s);
  if (d == null) return null;
  return d.toUtc();
}

String _fmtFechaHoraLocal(DateTime utc) {
  final l = utc.toLocal();
  final d = l.day.toString().padLeft(2, '0');
  final m = l.month.toString().padLeft(2, '0');
  final h = l.hour.toString().padLeft(2, '0');
  final min = l.minute.toString().padLeft(2, '0');
  return '$d/$m/${l.year} · $h:$min';
}

double _opacidadPuntoMarcoQr(double t, int seed) {
  final phase = (t + seed * 0.17) % 1.0;
  final op = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
  return 0.18 + op * 0.82;
}

// ─── Modos y fases ───────────────────────────────────────────────────────────

enum _Modo { manual, qr }

enum _TipoValidacion { lista, promo }

enum _FaseValidacion { idle, cargando, resultado }

// ─── Perfiles / snapshot ─────────────────────────────────────────────────────

String? _nombreDesdePerfilMap(Map<String, dynamic>? perfil) {
  if (perfil == null) return null;
  final nombre = perfil['nombre']?.toString().trim() ?? '';
  if (nombre.isNotEmpty) return nombre;
  final username = perfil['username']?.toString().trim() ?? '';
  if (username.isNotEmpty) return username;
  return null;
}

class _PerfilQrMini {
  final String? nombre;
  final String? username;
  final int? edad;

  const _PerfilQrMini({this.nombre, this.username, this.edad});
}

Future<_PerfilQrMini?> _fetchPerfilUsuarioQr(dynamic sb, String idUsuario) async {
  try {
    final perfil = await sb
        .from('perfiles_usuarios')
        .select('nombre, username, edad')
        .eq('id', idUsuario)
        .maybeSingle();
    if (perfil == null) return null;
    final m = Map<String, dynamic>.from(perfil as Map);
    final edadRaw = m['edad'];
    final edad = edadRaw is int
        ? edadRaw
        : (edadRaw is num ? edadRaw.toInt() : int.tryParse(edadRaw?.toString() ?? ''));
    return _PerfilQrMini(
      nombre: _nombreDesdePerfilMap(m),
      username: m['username']?.toString().trim(),
      edad: edad,
    );
  } catch (e) {
    debugPrint('⚠️ QR: no se pudo cargar perfil $idUsuario: $e');
    return null;
  }
}

class _SquadSnapshotQr {
  final bool esSquad;
  final int cantidadPersonas;
  final List<String> uidsMiembros;
  final int? indice;
  final int? cantidadTotal;
  final String? nombreGrupo;

  const _SquadSnapshotQr({
    required this.esSquad,
    required this.cantidadPersonas,
    required this.uidsMiembros,
    this.indice,
    this.cantidadTotal,
    this.nombreGrupo,
  });
}

_SquadSnapshotQr _parseSquadSnapshot(dynamic raw) {
  if (raw is! Map) {
    return const _SquadSnapshotQr(esSquad: false, cantidadPersonas: 1, uidsMiembros: []);
  }
  final m = Map<String, dynamic>.from(raw);
  final miembrosRaw = m['miembros'];
  final uids = <String>[];
  if (miembrosRaw is List) {
    for (final item in miembrosRaw) {
      final s = item?.toString().trim() ?? '';
      if (s.isNotEmpty) uids.add(s);
    }
  }
  final cantRaw = m['cantidad_total'] ?? m['cantidad'];
  var cantidad = cantRaw is int
      ? cantRaw
      : (cantRaw is num ? cantRaw.toInt() : int.tryParse(cantRaw?.toString() ?? '') ?? 0);
  if (cantidad <= 0) cantidad = uids.isNotEmpty ? uids.length : 1;
  final indiceRaw = m['indice'];
  final indice = indiceRaw is int
      ? indiceRaw
      : (indiceRaw is num ? indiceRaw.toInt() : int.tryParse(indiceRaw?.toString() ?? ''));
  final nombreGrupo = m['nombre_grupo']?.toString().trim();
  final esSquadFlag = m['es_squad'] == true || m['es_squad'] == 1;
  final esSquad = esSquadFlag || indice != null || uids.length > 1 || cantidad > 1;
  return _SquadSnapshotQr(
    esSquad: esSquad,
    cantidadPersonas: indice != null ? 1 : cantidad,
    uidsMiembros: uids,
    indice: indice,
    cantidadTotal: cantidad,
    nombreGrupo: (nombreGrupo != null && nombreGrupo.isNotEmpty) ? nombreGrupo : null,
  );
}

Future<List<String>> _nombresMiembrosSquadQr(dynamic sb, List<String> uids) async {
  if (uids.isEmpty) return const [];
  try {
    final data = await sb
        .from('perfiles_usuarios')
        .select('id, nombre, username')
        .inFilter('id', uids);
    final porId = <String, String>{};
    for (final raw in (data as List).cast<Map<String, dynamic>>()) {
      final id = raw['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final nombre = _nombreDesdePerfilMap(raw) ?? id;
      porId[id] = nombre;
    }
    return uids.map((id) => porId[id] ?? id).toList();
  } catch (e) {
    debugPrint('⚠️ QR: no se pudieron cargar miembros squad: $e');
    return uids;
  }
}

// ─── Resultado de validación ─────────────────────────────────────────────────

class _DatosValidacion {
  final bool ok;
  final _TipoValidacion tipo;
  final String codigo;

  // Usuario
  final String? nombreUsuario;
  final String? username;
  final int? edad;

  // Lista / asistencia
  final bool esSquad;
  final int cantidadPersonas;
  final List<String> miembros;
  final int? indiceSquad;
  final int? cantidadTotalSquad;
  final String? nombreSquad;
  final String? tituloEvento;

  // Promo
  final String? tituloPromo;
  final String? descripcionPromo;
  final String? tituloEventoPromo;
  final DateTime? fechaInicioPromo;
  final DateTime? fechaFinPromo;

  // Error
  final String? errorCode;
  final String? errorMensaje;

  const _DatosValidacion({
    required this.ok,
    required this.tipo,
    required this.codigo,
    this.nombreUsuario,
    this.username,
    this.edad,
    this.esSquad = false,
    this.cantidadPersonas = 1,
    this.miembros = const [],
    this.indiceSquad,
    this.cantidadTotalSquad,
    this.nombreSquad,
    this.tituloEvento,
    this.tituloPromo,
    this.descripcionPromo,
    this.tituloEventoPromo,
    this.fechaInicioPromo,
    this.fechaFinPromo,
    this.errorCode,
    this.errorMensaje,
  });

  factory _DatosValidacion.error({
    required _TipoValidacion tipo,
    required String codigo,
    required String mensaje,
    String? code,
  }) =>
      _DatosValidacion(
        ok: false,
        tipo: tipo,
        codigo: codigo,
        errorCode: code,
        errorMensaje: mensaje,
      );

  factory _DatosValidacion.fromEdgeResponse(
    Map<String, dynamic> data, {
    required _TipoValidacion tipo,
    required String codigo,
  }) {
    Map<String, dynamic>? uMap;
    final usuario = data['usuario'];
    if (usuario is Map) uMap = Map<String, dynamic>.from(usuario);

    Map<String, dynamic>? evMap;
    final evento = data['evento'];
    if (evento is Map) evMap = Map<String, dynamic>.from(evento);

    Map<String, dynamic>? promoMap;
    final promo = data['promo'];
    if (promo is Map) promoMap = Map<String, dynamic>.from(promo);

    final miembrosRaw = data['miembros'];
    final miembros = <String>[];
    if (miembrosRaw is List) {
      for (final m in miembrosRaw) {
        final s = m?.toString().trim() ?? '';
        if (s.isNotEmpty) miembros.add(s);
      }
    }

    final cantRaw = data['cantidad_personas'];
    final cantidad = cantRaw is int
        ? cantRaw
        : (cantRaw is num ? cantRaw.toInt() : miembros.isNotEmpty ? miembros.length : 1);

    DateTime? fechaFinPromo;
    final ff = promoMap?['fecha_fin'];
    if (ff != null) {
      fechaFinPromo = ff is DateTime ? ff : DateTime.tryParse(ff.toString());
    }

    final edadRaw = uMap?['edad'];
    final edad = edadRaw is int
        ? edadRaw
        : (edadRaw is num ? edadRaw.toInt() : int.tryParse(edadRaw?.toString() ?? ''));

    final indiceRaw = data['indice_squad'];
    final indiceSquad = indiceRaw is int
        ? indiceRaw
        : (indiceRaw is num ? indiceRaw.toInt() : int.tryParse(indiceRaw?.toString() ?? ''));
    final totalRaw = data['cantidad_total_squad'];
    final cantidadTotalSquad = totalRaw is int
        ? totalRaw
        : (totalRaw is num ? totalRaw.toInt() : int.tryParse(totalRaw?.toString() ?? ''));
    final nombreSquad = data['nombre_squad']?.toString().trim();

    return _DatosValidacion(
      ok: true,
      tipo: tipo,
      codigo: codigo,
      nombreUsuario: uMap?['nombre']?.toString().trim() ??
          uMap?['nombre_usuario']?.toString().trim(),
      username: uMap?['username']?.toString().trim(),
      edad: edad,
      esSquad: data['es_squad'] == true ||
          indiceSquad != null ||
          cantidad > 1 ||
          miembros.length > 1,
      cantidadPersonas: cantidad,
      miembros: miembros,
      indiceSquad: indiceSquad,
      cantidadTotalSquad: cantidadTotalSquad,
      nombreSquad: (nombreSquad != null && nombreSquad.isNotEmpty) ? nombreSquad : null,
      tituloEvento: evMap?['titulo_evento']?.toString(),
      tituloPromo: promoMap?['titulo_promocion']?.toString().trim(),
      descripcionPromo: promoMap?['descripcion_promocion']?.toString().trim(),
      tituloEventoPromo: evMap?['titulo_evento']?.toString(),
      fechaFinPromo: fechaFinPromo,
    );
  }
}

class _EntradaHistorial {
  final DateTime cuando;
  final bool ok;
  final String codigo;
  final String? nombre;
  final _TipoValidacion tipo;
  final String? tituloPromo;
  final int? edad;
  final bool esSquad;
  final int cantidadPersonas;

  const _EntradaHistorial({
    required this.cuando,
    required this.ok,
    required this.codigo,
    this.nombre,
    required this.tipo,
    this.tituloPromo,
    this.edad,
    this.esSquad = false,
    this.cantidadPersonas = 1,
  });
}

/// Historial de la sesión de validación por evento (persiste al salir y volver).
class _HistorialQrCache {
  static final Map<String, List<_EntradaHistorial>> _porEvento = {};

  static List<_EntradaHistorial> copiaPara(String idEvento) =>
      List<_EntradaHistorial>.from(_porEvento[idEvento] ?? const []);

  static void registrar(String idEvento, _EntradaHistorial entrada) {
    final lista = _porEvento.putIfAbsent(idEvento, () => []);
    lista.insert(0, entrada);
    if (lista.length > 40) {
      lista.removeRange(40, lista.length);
    }
  }
}

// ─── Pantalla principal (reutilizable: locales, staff, etc.) ─────────────────

/// Validación QR/manual optimizada: bottom sheet, cámara siempre activa, sonido.
class PantallaValidacionCodigo extends StatefulWidget {
  final EventoActivo evento;
  final String tituloAppBar;
  final PermisosStaffValidar? permisosStaff;

  const PantallaValidacionCodigo({
    super.key,
    required this.evento,
    this.tituloAppBar = 'Validar ingreso',
    this.permisosStaff,
  });

  /// Constructor con [ConfigValidacionCodigo] para flujos staff/futuros.
  PantallaValidacionCodigo.conConfig(ConfigValidacionCodigo config, {Key? key})
      : this(
          key: key,
          evento: config.evento,
          tituloAppBar: config.tituloAppBar,
          permisosStaff: config.permisosStaff,
        );

  @override
  State<PantallaValidacionCodigo> createState() =>
      _PantallaValidacionCodigoState();
}

/// Alias histórico — misma pantalla que [PantallaValidacionCodigo].
class LocalesQrValidar extends PantallaValidacionCodigo {
  const LocalesQrValidar({
    super.key,
    required super.evento,
    super.permisosStaff,
  }) : super(tituloAppBar: 'Validar ingreso');
}

class _PantallaValidacionCodigoState extends State<PantallaValidacionCodigo> {
  _Modo _modo = _Modo.qr;
  _TipoValidacion _tipo = _TipoValidacion.lista;
  _FaseValidacion _fase = _FaseValidacion.idle;
  _DatosValidacion? _datos;
  bool _canjeando = false;
  String? _canjeandoAccion;

  List<TextEditingController> _celdaCtrls = [];
  List<FocusNode> _celdaFocus = [];
  late MobileScannerController _camaraCtrl;
  bool _mostrandoSheetResultado = false;
  /// Evita llamadas concurrentes a start()/stop() (causa controllerInitializing).
  Future<void>? _operacionCamara;
  bool _escaneando = false;
  final AudioPlayer _player = AudioPlayer();
  late List<_EntradaHistorial> _historial;

  PermisosStaffValidar get _permisos =>
      widget.permisosStaff ?? PermisosStaffValidar.todos;

  bool get _esStaff => widget.permisosStaff != null;

  bool get _puedePases => !_esStaff || _permisos.canjearPases;

  bool get _puedePromos => !_esStaff || _permisos.canjearPromos;

  bool get _puedeTipoActual =>
      _tipo == _TipoValidacion.lista ? _puedePases : _puedePromos;

  _TipoValidacion get _tipoInicialPermitido {
    if (_puedePases) return _TipoValidacion.lista;
    if (_puedePromos) return _TipoValidacion.promo;
    return _TipoValidacion.lista;
  }

  @override
  void initState() {
    super.initState();
    _tipo = _tipoInicialPermitido;
    _historial = _HistorialQrCache.copiaPara(widget.evento.idEvento);
    _inicializarCeldasCodigo();
    _camaraCtrl = MobileScannerController(
      // normal: permite re-escanear tras cerrar el sheet (noDuplicates bloquea el mismo QR para siempre).
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      autoStart: false,
    );
    if (_modo == _Modo.qr) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_iniciarCamaraSegura());
      });
    }
  }

  @override
  void dispose() {
    unawaited(_detenerCamaraSegura(silent: true));
    _camaraCtrl.dispose();
    _player.dispose();
    _disposeCeldasCodigo();
    super.dispose();
  }

  int get _largoCodigo =>
      _tipo == _TipoValidacion.lista ? 8 : 12;

  void _inicializarCeldasCodigo() {
    _disposeCeldasCodigo();
    _celdaCtrls = List.generate(_largoCodigo, (_) => TextEditingController());
    _celdaFocus = List.generate(_largoCodigo, (_) => FocusNode());
  }

  void _disposeCeldasCodigo() {
    for (final c in _celdaCtrls) {
      c.dispose();
    }
    for (final f in _celdaFocus) {
      f.dispose();
    }
    _celdaCtrls = [];
    _celdaFocus = [];
  }

  void _limpiarCeldasCodigo() {
    for (final c in _celdaCtrls) {
      c.clear();
    }
    if (_celdaFocus.isNotEmpty) {
      _celdaFocus.first.requestFocus();
    }
  }

  String _codigoDesdeCeldas() =>
      _celdaCtrls.map((c) => c.text.toUpperCase()).join();

  bool get _codigoCeldasCompleto {
    final codigo = _codigoDesdeCeldas();
    return codigo.length == _largoCodigo &&
        RegExp(r'^[A-Z0-9]+$').hasMatch(codigo);
  }

  void _onCeldaChanged(int index, String value) {
    final char = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (char.length > 1 && char.isNotEmpty) {
      _celdaCtrls[index].text = char[0];
      _celdaCtrls[index].selection = const TextSelection.collapsed(offset: 1);
    } else if (_celdaCtrls[index].text != char) {
      _celdaCtrls[index].text = char;
      _celdaCtrls[index].selection = const TextSelection.collapsed(offset: 1);
    }
    if (char.isNotEmpty && index < _largoCodigo - 1) {
      _celdaFocus[index + 1].requestFocus();
    }
    if (_codigoCeldasCompleto) {
      unawaited(_procesarCodigo(_codigoDesdeCeldas()));
    }
  }

  KeyEventResult _onCeldaKey(int index, FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        _celdaCtrls[index].text.isEmpty &&
        index > 0) {
      _celdaFocus[index - 1].requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _iniciarCamaraSegura() async {
    if (!mounted || _modo != _Modo.qr) return;

    if (_operacionCamara != null) {
      try {
        await _operacionCamara;
      } catch (_) {}
      if (_camaraCtrl.value.isRunning) return;
    }

    if (_camaraCtrl.value.isRunning) return;

    if (_camaraCtrl.value.isStarting) {
      await Future<void>.delayed(const Duration(milliseconds: 320));
      if (!mounted) return;
      return _iniciarCamaraSegura();
    }

    final op = _camaraCtrl.start();
    _operacionCamara = op;
    try {
      await op;
    } on MobileScannerException catch (e) {
      debugPrint(
        '⚠️ iniciar cámara: ${e.errorCode} — ${e.errorDetails?.message ?? e}',
      );
      if (e.errorCode == MobileScannerErrorCode.controllerInitializing) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        _operacionCamara = null;
        if (mounted) await _iniciarCamaraSegura();
        return;
      }
      if (mounted) {
        _mostrarSnack(
          'No se pudo iniciar la cámara. Revisá los permisos e intentá de nuevo.',
          esError: true,
        );
      }
    } catch (e, st) {
      debugPrint('⚠️ iniciar cámara: $e\n$st');
    } finally {
      if (identical(_operacionCamara, op)) _operacionCamara = null;
    }
  }

  Future<void> _detenerCamaraSegura({bool silent = false}) async {
    if (_operacionCamara != null) {
      try {
        await _operacionCamara;
      } catch (_) {}
    }
    try {
      if (_camaraCtrl.value.isRunning) {
        await _camaraCtrl.stop();
      }
    } catch (e) {
      debugPrint('⚠️ detener cámara: $e');
    }
    if (!silent && mounted) setState(() {});
  }

  Future<void> _setModo(_Modo modo) async {
    if (_modo == modo) return;
    if (modo == _Modo.manual) {
      await _detenerCamaraSegura();
    }
    setState(() => _modo = modo);
    if (modo == _Modo.qr) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_iniciarCamaraSegura());
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _celdaFocus.isNotEmpty) {
          _celdaFocus.first.requestFocus();
        }
      });
    }
  }

  void _mostrarSnackPermisoCanje({required _TipoValidacion tipoIntentado}) {
    if (_puedePases && !_puedePromos) {
      _mostrarSnack('Solo tenés permitido canjear pases', esError: true);
      return;
    }
    if (_puedePromos && !_puedePases) {
      _mostrarSnack('Solo tenés permitido canjear promos', esError: true);
      return;
    }
    _mostrarSnack(
      tipoIntentado == _TipoValidacion.lista
          ? 'No tenés permiso para canjear pases'
          : 'No tenés permiso para canjear promos',
      esError: true,
    );
  }

  Future<void> _setTipo(_TipoValidacion tipo) async {
    if (_tipo == tipo) return;
    final permitido =
        tipo == _TipoValidacion.lista ? _puedePases : _puedePromos;
    if (!permitido) {
      _mostrarSnackPermisoCanje(tipoIntentado: tipo);
      return;
    }
    _disposeCeldasCodigo();
    setState(() => _tipo = tipo);
    _inicializarCeldasCodigo();
  }

  void _feedbackDeteccionQr() {
    HapticFeedback.lightImpact();
    unawaited(SystemSound.play(SystemSoundType.click));
  }

  String _limpiarError(String raw) {
    var msg = raw;
    if (msg.startsWith('Exception: ')) msg = msg.substring(11);
    if (msg.startsWith('EdgeException')) {
      final idx = msg.indexOf(': ');
      if (idx >= 0 && idx + 2 < msg.length) msg = msg.substring(idx + 2);
    }
    return msg.trim();
  }

  void _mostrarSnack(String mensaje, {required bool esError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mensaje,
          style: GoogleFonts.baloo2(
            fontWeight: FontWeight.w700,
            color: ColoresLocales.textoEnBoton,
          ),
        ),
        backgroundColor: esError ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _reproducirSonido({required bool ok}) async {
    try {
      await _player.stop();
      await _player.play(
        AssetSource(ok ? 'audio/validacion_ok.mp3' : 'audio/validacion_error.mp3'),
        volume: 0.85,
      );
    } catch (e) {
      debugPrint('⚠️ audio validación: $e');
      if (ok) {
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.vibrate();
      }
    }
  }

  void _registrarEnHistorial(_DatosValidacion d) {
    final entrada = _EntradaHistorial(
      cuando: DateTime.now(),
      ok: d.ok,
      codigo: d.codigo,
      nombre: d.nombreUsuario,
      tipo: d.tipo,
      tituloPromo: d.tituloPromo,
      edad: d.edad,
      esSquad: d.esSquad,
      cantidadPersonas: d.cantidadPersonas,
    );
    _HistorialQrCache.registrar(widget.evento.idEvento, entrada);
    setState(() {
      _historial.insert(0, entrada);
      if (_historial.length > 40) {
        _historial.removeRange(40, _historial.length);
      }
    });
  }

  void _limpiarYSeguir() {
    if (!mounted) return;
    setState(() {
      _fase = _FaseValidacion.idle;
      _datos = null;
      _limpiarCeldasCodigo();
      _escaneando = false;
      _canjeando = false;
      _canjeandoAccion = null;
    });
  }

  String _mensajeOtroEvento() =>
      _modo == _Modo.manual
          ? 'Este token es de otro evento. Validá desde el evento correcto.'
          : 'Este QR es de otro evento. Escanealo desde el evento al que pertenece.';

  // ── Procesamiento del código ────────────────────────────────────────────────

  Future<void> _procesarCodigo(String raw) async {
    final codigo = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (codigo.isEmpty) {
      if (mounted && _modo == _Modo.qr) setState(() => _escaneando = false);
      return;
    }
    if (_fase == _FaseValidacion.cargando) return;

    if (!_puedeTipoActual) {
      _mostrarSnackPermisoCanje(tipoIntentado: _tipo);
      if (mounted && _modo == _Modo.qr) setState(() => _escaneando = false);
      return;
    }

    final esperado = _tipo == _TipoValidacion.lista ? 8 : 12;
    if (codigo.length != esperado) {
      if (_modo == _Modo.qr && (codigo.length == 8 || codigo.length == 12)) {
        if (codigo.length == 8) {
          if (_puedePases) {
            _mostrarSnack(
              'Cambiá el switch a Lista (código de 8 caracteres)',
              esError: true,
            );
          } else {
            _mostrarSnackPermisoCanje(tipoIntentado: _TipoValidacion.lista);
          }
        } else {
          if (_puedePromos) {
            _mostrarSnack(
              'Cambiá el switch a Promo (código de 12 caracteres)',
              esError: true,
            );
          } else {
            _mostrarSnackPermisoCanje(tipoIntentado: _TipoValidacion.promo);
          }
        }
      } else {
        _mostrarSnack(
          'El código debe tener $esperado caracteres',
          esError: true,
        );
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _escaneando = false);
      return;
    }

    setState(() => _fase = _FaseValidacion.cargando);
    _feedbackDeteccionQr();

    try {
      final datos = _tipo == _TipoValidacion.lista
          ? await _lookupLista(codigo)
          : await _lookupPromo(codigo);

      if (!mounted) return;
      setState(() {
        _datos = datos;
        _fase = _FaseValidacion.resultado;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _datos != null) {
          unawaited(_mostrarResultadoBottomSheet(_datos!));
        }
      });
      unawaited(_reproducirSonido(ok: datos.ok));
      if (!datos.ok) _registrarEnHistorial(datos);
    } catch (e, st) {
      debugPrint('❌ _procesarCodigo: $e\n$st');
      final errorDatos = _DatosValidacion.error(
        tipo: _tipo,
        codigo: codigo,
        mensaje: _limpiarError(e.toString()),
        code: 'lookup_error',
      );
      if (!mounted) return;
      setState(() {
        _datos = errorDatos;
        _fase = _FaseValidacion.resultado;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _datos != null) {
          unawaited(_mostrarResultadoBottomSheet(_datos!));
        }
      });
      unawaited(_reproducirSonido(ok: false));
      _registrarEnHistorial(errorDatos);
    } finally {
      if (mounted && _modo == _Modo.qr) {
        setState(() => _escaneando = false);
      }
    }
  }

  Future<_DatosValidacion> _lookupLista(String codigo) async {
    final sb = ServicioSupabase().cliente;

    final tok = await sb
        .from('tokens_asistencia')
        .select(
          'id_token, id_evento, id_usuario, estado_token, fecha_expiracion, snapshot_squad',
        )
        .eq('codigo_puerta', codigo)
        .eq('id_evento', widget.evento.idEvento)
        .maybeSingle();

    if (tok == null) {
      final enOtroEvento = await sb
          .from('tokens_asistencia')
          .select('id_evento')
          .eq('codigo_puerta', codigo)
          .neq('id_evento', widget.evento.idEvento)
          .limit(1)
          .maybeSingle();

      if (enOtroEvento != null) {
        return _DatosValidacion.error(
          tipo: _TipoValidacion.lista,
          codigo: codigo,
          code: 'wrong_event',
          mensaje: _mensajeOtroEvento(),
        );
      }

      return _DatosValidacion.error(
        tipo: _TipoValidacion.lista,
        codigo: codigo,
        code: 'token_not_found',
        mensaje: 'No existe ningún pase con ese código para este evento.',
      );
    }

    final estado = tok['estado_token']?.toString() ?? '';
    if (estado == 'canjeada') {
      return _DatosValidacion.error(
        tipo: _TipoValidacion.lista,
        codigo: codigo,
        code: 'already_canjeado',
        mensaje: 'Este pase ya fue canjeado.',
      );
    }
    if (estado == 'rechazada') {
      return _DatosValidacion.error(
        tipo: _TipoValidacion.lista,
        codigo: codigo,
        code: 'already_rechazado',
        mensaje: 'Este pase fue rechazado.',
      );
    }
    if (estado != 'aceptada') {
      return _DatosValidacion.error(
        tipo: _TipoValidacion.lista,
        codigo: codigo,
        code: 'invalid_state',
        mensaje: 'El pase no está aceptado (estado: $estado).',
      );
    }

    final expRaw = tok['fecha_expiracion'];
    if (expRaw != null) {
      final exp = expRaw is DateTime ? expRaw : DateTime.tryParse(expRaw.toString());
      if (exp != null && exp.isBefore(DateTime.now())) {
        return _DatosValidacion.error(
          tipo: _TipoValidacion.lista,
          codigo: codigo,
          code: 'expired_token',
          mensaje: 'El código del pase está expirado.',
        );
      }
    }

    String? nombreUsuario;
    String? username;
    int? edad;
    final idUsuario = tok['id_usuario']?.toString();
    if (idUsuario != null && idUsuario.isNotEmpty) {
      final perfil = await _fetchPerfilUsuarioQr(sb, idUsuario);
      nombreUsuario = perfil?.nombre;
      username = perfil?.username;
      edad = perfil?.edad;
    }

    final squad = _parseSquadSnapshot(tok['snapshot_squad']);
    final miembros = squad.uidsMiembros.isNotEmpty
        ? await _nombresMiembrosSquadQr(sb, squad.uidsMiembros)
        : <String>[];

    final tituloEvento = widget.evento.nombre.trim().isNotEmpty
        ? widget.evento.nombre
        : 'Evento';

    return _DatosValidacion(
      ok: true,
      tipo: _TipoValidacion.lista,
      codigo: codigo,
      nombreUsuario: nombreUsuario,
      username: username,
      edad: edad,
      esSquad: squad.esSquad,
      cantidadPersonas: squad.cantidadPersonas,
      miembros: miembros,
      tituloEvento: tituloEvento,
    );
  }

  Future<_DatosValidacion> _lookupPromo(String codigo) async {
    final sb = ServicioSupabase().cliente;

    final tok = await sb
        .from('tokens_promociones')
        .select(
          'id_token, id_promocion, id_usuario, estado_token, fecha_expiracion, snapshot_squad',
        )
        .eq('token_codigo', codigo)
        .maybeSingle();

    if (tok == null) {
      return _DatosValidacion.error(
        tipo: _TipoValidacion.promo,
        codigo: codigo,
        code: 'token_not_found',
        mensaje: 'No existe ninguna promo con ese código.',
      );
    }

    final idPromo = tok['id_promocion']?.toString();
    if (idPromo == null || idPromo.isEmpty) {
      return _DatosValidacion.error(
        tipo: _TipoValidacion.promo,
        codigo: codigo,
        code: 'promo_not_found',
        mensaje: 'Promoción no encontrada.',
      );
    }

    final promo = await sb
        .from('promociones')
        .select(
          'id_promocion, id_local, id_evento, titulo_promocion, descripcion_promocion, '
          'fecha_inicio, fecha_fin, modo_uso',
        )
        .eq('id_promocion', idPromo)
        .maybeSingle();

    if (promo == null) {
      return _DatosValidacion.error(
        tipo: _TipoValidacion.promo,
        codigo: codigo,
        code: 'promo_not_found',
        mensaje: 'Promoción no encontrada.',
      );
    }

    if (promo['id_local']?.toString() != widget.evento.idLocal) {
      return _DatosValidacion.error(
        tipo: _TipoValidacion.promo,
        codigo: codigo,
        code: 'invalid_local_target',
        mensaje: 'Esta promo no pertenece a tu local.',
      );
    }

    final idEventoPromoCheck = promo['id_evento']?.toString();
    if (idEventoPromoCheck != null &&
        idEventoPromoCheck.isNotEmpty &&
        idEventoPromoCheck != widget.evento.idEvento) {
      return _DatosValidacion.error(
        tipo: _TipoValidacion.promo,
        codigo: codigo,
        code: 'wrong_event',
        mensaje: _mensajeOtroEvento(),
      );
    }

    final estado = tok['estado_token']?.toString() ?? '';
    if (estado == 'canjeado') {
      return _DatosValidacion.error(
        tipo: _TipoValidacion.promo,
        codigo: codigo,
        code: 'already_canjeado',
        mensaje: 'Esta promo ya fue canjeada en este evento.',
      );
    }
    if (estado == 'cancelado') {
      return _DatosValidacion.error(
        tipo: _TipoValidacion.promo,
        codigo: codigo,
        code: 'already_cancelado',
        mensaje: 'Esta promo fue cancelada.',
      );
    }
    if (estado != 'activo') {
      return _DatosValidacion.error(
        tipo: _TipoValidacion.promo,
        codigo: codigo,
        code: 'invalid_state',
        mensaje: 'Estado inválido: $estado',
      );
    }

    final exp = _parseFechaUtc(tok['fecha_expiracion']);
    if (exp != null && exp.isBefore(DateTime.now().toUtc())) {
      return _DatosValidacion.error(
        tipo: _TipoValidacion.promo,
        codigo: codigo,
        code: 'expired_token',
        mensaje: 'El código de la promo está expirado.',
      );
    }

    final ahora = DateTime.now().toUtc();
    final inicio = _parseFechaUtc(promo['fecha_inicio']);
    final fin = _parseFechaUtc(promo['fecha_fin']);

    if (inicio != null && inicio.isAfter(ahora)) {
      debugPrint(
        'ℹ️ QR promo canje anticipado: inicio=${inicio.toIso8601String()} '
        'ahora=${ahora.toIso8601String()} codigo=$codigo',
      );
    }
    if (fin != null && fin.isBefore(ahora)) {
      return _DatosValidacion.error(
        tipo: _TipoValidacion.promo,
        codigo: codigo,
        code: 'too_late',
        mensaje: 'La promo finalizó el ${_fmtFechaHoraLocal(fin)} (hora local).',
      );
    }

    String? nombreUsuario;
    String? username;
    final idUsuario = tok['id_usuario']?.toString();
    if (idUsuario != null && idUsuario.isNotEmpty) {
      final perfil = await _fetchPerfilUsuarioQr(sb, idUsuario);
      nombreUsuario = perfil?.nombre;
      username = perfil?.username;
    }

    final tituloPromoRaw = promo['titulo_promocion']?.toString().trim();
    final descripcionPromoRaw = promo['descripcion_promocion']?.toString().trim();
    final tituloPromo = (tituloPromoRaw != null && tituloPromoRaw.isNotEmpty)
        ? tituloPromoRaw
        : descripcionPromoRaw;
    final descripcionPromo =
        (descripcionPromoRaw != null &&
                descripcionPromoRaw.isNotEmpty &&
                descripcionPromoRaw != tituloPromo)
            ? descripcionPromoRaw
            : null;

    final esPromoSquad = promo['modo_uso']?.toString() == 'squad';
    var cantidadSquad = 1;
    if (esPromoSquad) {
      final snap = tok['snapshot_squad'];
      if (snap is Map) {
        final miembros = snap['miembros'];
        if (miembros is List && miembros.isNotEmpty) {
          cantidadSquad = miembros.length;
        }
      }
    }

    return _DatosValidacion(
      ok: true,
      tipo: _TipoValidacion.promo,
      codigo: codigo,
      nombreUsuario: nombreUsuario,
      username: username,
      esSquad: esPromoSquad,
      cantidadPersonas: cantidadSquad,
      tituloPromo: tituloPromo,
      descripcionPromo: descripcionPromo,
      fechaInicioPromo: inicio,
      fechaFinPromo: fin,
    );
  }

  /// Si la promo empieza en más de 24 h, pedir confirmación antes de canjear.
  Future<bool> _confirmarCanjePromoAnticipado(_DatosValidacion d) async {
    final inicio = d.fechaInicioPromo;
    if (inicio == null) return true;

    final ahora = DateTime.now().toUtc();
    if (!inicio.isAfter(ahora)) return true;

    final faltan = inicio.difference(ahora);
    if (faltan <= const Duration(hours: 24)) return true;

    final tituloPromo = (d.tituloPromo?.trim().isNotEmpty == true)
        ? d.tituloPromo!.trim()
        : 'Promoción';
    final cuando = _fmtFechaHoraLocal(inicio);

    if (!mounted) return false;
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(
          'Canje anticipado',
          style: GoogleFonts.baloo2(fontWeight: FontWeight.w900),
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            '«$tituloPromo» comienza el $cuando.\n\n'
            '¿Seguro querés canjear este cupón ahora?',
            style: GoogleFonts.baloo2(fontSize: 14, height: 1.35),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, canjear'),
          ),
        ],
      ),
    );
    return confirm ?? false;
  }

  Future<void> _onSolicitarCanje({required bool validar}) async {
    final datos = _datos;
    if (datos == null || !datos.ok || _canjeando) return;
    if (!_puedeTipoActual) {
      _mostrarSnack(
        _tipo == _TipoValidacion.lista
            ? 'No tenés permiso para canjear pases de lista'
            : 'No tenés permiso para canjear promos',
        esError: true,
      );
      return;
    }

    if (validar &&
        _tipo == _TipoValidacion.promo &&
        !await _confirmarCanjePromoAnticipado(datos)) {
      return;
    }
    await _ejecutarAccion(validar: validar);
  }

  // ── Canje en puerta ─────────────────────────────────────────────────────────

  Future<bool> _canjeYaAplicadoEnDb(String codigo, bool validar) async {
    try {
      final sb = ServicioSupabase().cliente;
      if (_tipo == _TipoValidacion.lista) {
        final row = await sb
            .from('tokens_asistencia')
            .select('estado_token')
            .eq('codigo_puerta', codigo)
            .eq('id_evento', widget.evento.idEvento)
            .maybeSingle();
        if (row == null) return false;
        final estado = row['estado_token']?.toString() ?? '';
        return validar ? estado == 'canjeada' : estado == 'rechazada';
      }
      final row = await sb
          .from('tokens_promociones')
          .select('estado_token, id_promocion')
          .eq('token_codigo', codigo)
          .maybeSingle();
      if (row == null) return false;

      final idPromo = row['id_promocion']?.toString();
      if (idPromo == null || idPromo.isEmpty) return false;

      final promo = await sb
          .from('promociones')
          .select('id_evento, id_local')
          .eq('id_promocion', idPromo)
          .maybeSingle();
      if (promo == null) return false;
      if (promo['id_local']?.toString() != widget.evento.idLocal) return false;

      final idEventoPromo = promo['id_evento']?.toString();
      if (idEventoPromo != null &&
          idEventoPromo.isNotEmpty &&
          idEventoPromo != widget.evento.idEvento) {
        return false;
      }

      final estado = row['estado_token']?.toString() ?? '';
      return validar ? estado == 'canjeado' : estado == 'cancelado';
    } catch (e) {
      debugPrint('⚠️ verificar canje en DB: $e');
      return false;
    }
  }

  Future<void> _finalizarCanjeExito(
    _DatosValidacion datos, {
    required bool validar,
  }) async {
    if (!mounted) return;

    final msg = validar
        ? (_tipo == _TipoValidacion.lista
            ? 'Ingreso canjeado exitosamente'
            : 'Promo canjeada exitosamente')
        : 'Pase rechazado';

    if (_mostrandoSheetResultado) {
      Navigator.of(context).pop();
    } else {
      _limpiarYSeguir();
    }

    _feedbackDeteccionQr();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mostrarSnack('✓ $msg', esError: false);
    });

    unawaited(_reproducirSonido(ok: true));

    try {
      _registrarEnHistorial(datos);
    } catch (e) {
      debugPrint('⚠️ historial canje: $e');
    }
  }

  Future<void> _mostrarErrorCanje({
    required String titulo,
    required String mensaje,
    String? detail,
  }) async {
    if (!mounted) return;
    _mostrarSnack(mensaje, esError: true);
    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(titulo),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            detail != null && detail.isNotEmpty ? '$mensaje\n\n$detail' : mensaje,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _ejecutarAccion({required bool validar}) async {
    final datos = _datos;
    if (datos == null || !datos.ok) return;
    if (_canjeando) return;

    final accion = validar ? 'validar' : 'rechazar';
    setState(() {
      _canjeando = true;
      _canjeandoAccion = accion;
    });

    try {
      final idLocal = widget.evento.idLocal;

      final Map<String, dynamic> edgeData;
      if (_tipo == _TipoValidacion.lista) {
        edgeData = await ServicioEdgesEventos().canjearAsistencia(
          codigoPuerta: datos.codigo,
          idLocal: idLocal,
          idEvento: widget.evento.idEvento,
          accion: accion,
        );
      } else {
        edgeData = await ServicioEdgesEventos().canjearPromocion(
          tokenCodigo: datos.codigo,
          idLocal: idLocal,
          idEvento: widget.evento.idEvento,
          accion: accion,
        );
      }

      final datosFinales = _DatosValidacion.fromEdgeResponse(
        edgeData,
        tipo: _tipo,
        codigo: datos.codigo,
      );
      await _finalizarCanjeExito(datosFinales, validar: validar);
    } on EdgeException catch (e) {
      if (!mounted) return;
      if (e.yaAplicada || await _canjeYaAplicadoEnDb(datos.codigo, validar)) {
        await _finalizarCanjeExito(datos, validar: validar);
        return;
      }
      debugPrint('❌ canje QR EdgeException: $e');
      setState(() {
        _canjeando = false;
        _canjeandoAccion = null;
      });
      await _mostrarErrorCanje(
        titulo: validar ? 'No se pudo confirmar' : 'No se pudo rechazar',
        mensaje: e.mensaje,
        detail: e.detail,
      );
    } catch (e, st) {
      debugPrint('❌ canje QR: $e\n$st');
      if (!mounted) return;
      if (await _canjeYaAplicadoEnDb(datos.codigo, validar)) {
        await _finalizarCanjeExito(datos, validar: validar);
        return;
      }
      final msg = _limpiarError(e.toString());
      setState(() {
        _canjeando = false;
        _canjeandoAccion = null;
      });
      await _mostrarErrorCanje(
        titulo: validar ? 'No se pudo confirmar' : 'No se pudo rechazar',
        mensaje: msg,
      );
    }
  }

  void _onQrDetect(BarcodeCapture capture) {
    if (_modo != _Modo.qr) return;
    if (_escaneando || _mostrandoSheetResultado) return;
    if (_fase == _FaseValidacion.cargando) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final raw = barcodes.first.rawValue;
    if (raw == null || raw.trim().isEmpty) return;

    setState(() => _escaneando = true);
    unawaited(_procesarCodigo(raw));
  }

  // ── Textos de error ─────────────────────────────────────────────────────────

  String _tituloError(String? code) {
    switch (code) {
      case 'token_not_found':
        return 'Pase no encontrado';
      case 'already_canjeado':
        return 'Ya canjeado';
      case 'already_rechazado':
      case 'already_cancelado':
        return 'No válido';
      case 'invalid_state':
        return 'Estado inválido';
      case 'expired_token':
        return 'Código expirado';
      case 'too_early':
        return 'Aún no habilitada';
      case 'too_late':
        return 'Promo finalizada';
      case 'invalid_local_target':
        return 'No autorizado';
      case 'promo_not_found':
        return 'Promo no encontrada';
      case 'wrong_event':
        return 'Otro evento';
      default:
        return 'No válido';
    }
  }

  String _descripcionError(String? code, String fallback) {
    switch (code) {
      case 'token_not_found':
        return 'No existe ningún pase o promo con ese código para este evento.';
      case 'already_canjeado':
        return 'Este código ya fue utilizado anteriormente.';
      case 'already_rechazado':
        return 'Este pase fue rechazado y no puede ingresar.';
      case 'already_cancelado':
        return 'Esta promo fue cancelada.';
      case 'invalid_state':
        return fallback;
      case 'expired_token':
        return 'El tiempo de validez del código ya venció.';
      case 'too_early':
        return fallback.isNotEmpty
            ? fallback
            : 'La promoción todavía no está en su horario de canje.';
      case 'too_late':
        return fallback.isNotEmpty
            ? fallback
            : 'La promoción ya no está vigente.';
      case 'invalid_local_target':
        return 'Este código no corresponde a tu local.';
      case 'wrong_event':
        return _mensajeOtroEvento();
      default:
        return fallback;
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final overlayLookup =
        _fase == _FaseValidacion.cargando && _datos == null;

    // Historial + barra siempre en el árbol: si se sacan, el Expanded de la cámara
    // cambia de tamaño y el preview de MobileScanner queda negro al cerrar el sheet.
    final cuerpo = Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: [
            _buildHistorialSuperior(),
            Expanded(child: _buildContenido()),
            _buildBarraInferior(),
          ],
        ),
        if (overlayLookup)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              minHeight: 3,
              color: ColoresLocales.acentoVioleta,
              backgroundColor: ColoresStaff.progressTrack,
            ),
          ),
      ],
    );

    if (_esStaff) {
      return ScaffoldStaff(
        appBar: _buildAppBar(transparente: true),
        body: cuerpo,
      );
    }

    return Scaffold(
      backgroundColor: ColoresStaff.fondo,
      appBar: _buildAppBar(),
      body: cuerpo,
    );
  }

  PreferredSizeWidget _buildAppBar({bool transparente = false}) {
    final leading = CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () => Navigator.of(context).pop(),
      child: Icon(
        CupertinoIcons.chevron_back,
        color: ColoresLocales.acentoVioleta,
      ),
    );
    final title = Column(
      children: [
        Text(
          widget.tituloAppBar,
          style: GoogleFonts.baloo2(
            fontWeight: FontWeight.w900,
            color: ColoresLocales.acentoVioleta,
            fontSize: 18,
          ),
        ),
        Text(
          widget.evento.nombre,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.baloo2(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: ColoresStaff.textoSecundario,
          ),
        ),
      ],
    );

    if (transparente) {
      return appBarStaff(
        centerTitle: true,
        leading: leading,
        title: title,
      );
    }

    return AppBar(
      backgroundColor: ColoresStaff.fondo,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      leading: leading,
      title: title,
    );
  }

  Future<void> _mostrarResultadoBottomSheet(_DatosValidacion d) async {
    if (!mounted || _mostrandoSheetResultado) return;
    _mostrandoSheetResultado = true;

    final ok = d.ok;
    final verde = const Color(0xFF16A34A);
    final rojo = const Color(0xFFDC2626);
    final bg = ok ? verde : rojo;

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return DraggableScrollableSheet(
            initialChildSize: ok ? 0.78 : 0.58,
            minChildSize: 0.42,
            maxChildSize: 0.92,
            expand: false,
            builder: (context, scrollController) {
              return Material(
                color: bg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                clipBehavior: Clip.antiAlias,
                child: SafeArea(
                  top: false,
                  child: CustomScrollView(
                    controller: scrollController,
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 10),
                            Center(
                              child: Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.45),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                        sliver: SliverToBoxAdapter(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 400),
                              child: ok
                                  ? _buildContenidoOk(d)
                                  : _buildContenidoError(d),
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(20, 8, 20, 20),
                        sliver: SliverToBoxAdapter(
                          child: ok ? _buildBotonesOk() : _buildBotonesError(),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      _mostrandoSheetResultado = false;
      if (mounted) _limpiarYSeguir();
    }
  }

  Widget _buildHistorialSuperior() {
    return Container(
      color: ColoresStaff.fondo,
      padding: EdgeInsets.fromLTRB(0, 6, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.clock_fill,
                  size: 14,
                  color: ColoresLocales.acentoVioleta.withOpacity(0.7),
                ),
                SizedBox(width: 6),
                Text(
                  'Recientes',
                  style: GoogleFonts.baloo2(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: ColoresStaff.textoPrincipal,
                  ),
                ),
                Spacer(),
                if (_historial.isNotEmpty)
                  Text(
                    '${_historial.length}',
                    style: GoogleFonts.baloo2(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: ColoresStaff.textoSecundario,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: 8),
          SizedBox(
            height: 88,
            child: _historial.isEmpty
                ? Center(
                    child: Text(
                      'Acá vas a ver los últimos códigos validados',
                      style: GoogleFonts.baloo2(
                        fontSize: 12,
                        color: ColoresStaff.textoSecundario,
                      ),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    itemCount: _historial.length,
                    separatorBuilder: (_, __) => SizedBox(width: 10),
                    itemBuilder: (context, i) =>
                        _HistorialTile(entrada: _historial[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarraInferior() {
    return ColoredBox(
      color: ColoresStaff.fondo,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildBotonCambioModo(),
              SizedBox(height: 10),
              _buildSegmentoListaPromo(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBotonCambioModo() {
    final esQr = _modo == _Modo.qr;
    return Center(
      child: CupertinoButton(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        minimumSize: Size(0, 34),
        color: ColoresLocales.acentoVioleta,
        borderRadius: BorderRadius.circular(50),
        onPressed: () => _setModo(esQr ? _Modo.manual : _Modo.qr),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              esQr ? CupertinoIcons.keyboard : CupertinoIcons.qrcode_viewfinder,
              size: 16,
              color: ColoresStaff.chipInactivo,
            ),
            SizedBox(width: 6),
            Text(
              esQr ? 'Manual' : 'QR',
              style: GoogleFonts.baloo2(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                color: ColoresStaff.chipInactivo,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentoListaPromo() {
    final esLista = _tipo == _TipoValidacion.lista;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return Container(
          height: 48,
          decoration: BoxDecoration(
            color: ColoresStaff.card,
            borderRadius: BorderRadius.circular(50),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: esLista ? 4 : w / 2 + 2,
                top: 4,
                bottom: 4,
                width: w / 2 - 6,
                child: Container(
                  decoration: BoxDecoration(
                    color: ColoresLocales.acentoVioleta,
                    borderRadius: BorderRadius.circular(50),
                    boxShadow: [
                      BoxShadow(
                        color: ColoresLocales.acentoVioleta.withOpacity(0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _SegmentoOpcion(
                      label: 'Lista',
                      icon: CupertinoIcons.ticket_fill,
                      activo: esLista && _puedePases,
                      habilitado: _puedePases,
                      onTap: () => _setTipo(_TipoValidacion.lista),
                    ),
                  ),
                  Expanded(
                    child: _SegmentoOpcion(
                      label: 'Promo',
                      icon: CupertinoIcons.gift_fill,
                      activo: !esLista && _puedePromos,
                      habilitado: _puedePromos,
                      onTap: () => _setTipo(_TipoValidacion.promo),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContenido() {
    return ColoredBox(
      color: ColoresStaff.fondo,
      child: _modo == _Modo.manual ? _buildModoManual() : _buildModoQr(),
    );
  }

  Widget _buildModoManual() {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Ingresá el código ($_largoCodigo caracteres)',
            textAlign: TextAlign.center,
            style: GoogleFonts.baloo2(
              color: ColoresStaff.textoPrincipal,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          SizedBox(height: 6),
          Text(
            _tipo == _TipoValidacion.lista ? 'Pase de lista' : 'Código de promo',
            textAlign: TextAlign.center,
            style: GoogleFonts.baloo2(
              color: ColoresStaff.textoSecundario,
              fontSize: 12,
            ),
          ),
          SizedBox(height: 20),
          _buildCeldasCodigo(),
          SizedBox(height: 24),
          Opacity(
            opacity: _codigoCeldasCompleto && _puedeTipoActual ? 1 : 0.38,
            child: IgnorePointer(
              ignoring: !(_codigoCeldasCompleto && _puedeTipoActual),
              child: SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _codigoCeldasCompleto && _puedeTipoActual
                      ? () => unawaited(_procesarCodigo(_codigoDesdeCeldas()))
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ColoresLocales.acentoVioleta,
                    disabledBackgroundColor:
                        ColoresLocales.acentoVioleta.withOpacity(0.35),
                    foregroundColor: ColoresLocales.textoEnBoton,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Validar código',
                    style: GoogleFonts.baloo2(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCeldasCodigo() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final esPromo = _largoCodigo > 8;
        final gap = esPromo ? 3.0 : 8.0;
        final maxCellW = esPromo ? 26.0 : 44.0;
        final minCellW = esPromo ? 18.0 : 26.0;
        final cellH = esPromo ? 42.0 : 52.0;
        final fontSize = esPromo ? 14.0 : 22.0;
        final radius = esPromo ? 8.0 : 12.0;
        final cellW =
            (constraints.maxWidth - gap * (_largoCodigo - 1)) / _largoCodigo;

        final fila = Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: List.generate(_largoCodigo, (i) {
            return Padding(
              padding: EdgeInsets.only(right: i == _largoCodigo - 1 ? 0 : gap),
              child: SizedBox(
                width: cellW.clamp(minCellW, maxCellW),
                height: cellH,
                child: Focus(
                  onKeyEvent: (node, e) => _onCeldaKey(i, node, e),
                  child: TextField(
                    controller: _celdaCtrls[i],
                    focusNode: _celdaFocus[i],
                    textAlign: TextAlign.center,
                    maxLength: 1,
                    style: GoogleFonts.baloo2(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w900,
                      color: ColoresStaff.textoPrincipal,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '·',
                      filled: true,
                      fillColor: ColoresStaff.rellenoInput,
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(radius),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(radius),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(radius),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) => _onCeldaChanged(i, v),
                  ),
                ),
              ),
            );
          }),
        );

        if (esPromo) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: fila,
          );
        }
        return fila;
      },
    );
  }

  Widget _buildModoQr() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Colors.black),
                  MobileScanner(
                    controller: _camaraCtrl,
                    onDetect: _onQrDetect,
                    errorBuilder: (context, error) => _buildErrorCamara(error),
                  ),
                  const RepaintBoundary(
                    child: Center(child: _MarcoEscaneoQr()),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
                    child: Text(
                      'Centrá el QR en el recuadro',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.baloo2(
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        shadows: [
                          Shadow(
                            blurRadius: 6,
                            color: Colors.black54,
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
      ],
    );
  }

  Widget _buildErrorCamara(MobileScannerException error) {
    return ColoredBox(
      color: ColoresStaff.fondo,
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.exclamationmark_triangle_fill,
            size: 44,
            color: ColoresLocales.acentoVioleta,
          ),
          SizedBox(height: 12),
          Text(
            'No se pudo usar la cámara',
            textAlign: TextAlign.center,
            style: GoogleFonts.baloo2(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: ColoresStaff.textoPrincipal,
            ),
          ),
          SizedBox(height: 16),
          CupertinoButton(
            color: ColoresLocales.acentoVioleta,
            borderRadius: BorderRadius.circular(50),
            onPressed: () => unawaited(_iniciarCamaraSegura()),
            child: Text(
              'Reintentar',
              style: GoogleFonts.baloo2(
                fontWeight: FontWeight.w800,
                color: ColoresStaff.chipInactivo,
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  String _tituloValidacionOk(_DatosValidacion d) {
    if (d.tipo == _TipoValidacion.promo) return 'Promo válida';
    final handle = d.username?.trim();
    if (handle != null && handle.isNotEmpty) {
      final fmt = handle.startsWith('@') ? handle : '@$handle';
      return '$fmt válido';
    }
    if (d.nombreUsuario != null && d.nombreUsuario!.trim().isNotEmpty) {
      return '${d.nombreUsuario!.trim()} válido';
    }
    return d.esSquad ? 'Asistencia squad válida' : 'Asistencia individual válida';
  }

  String? _subtituloSquadValidacion(_DatosValidacion d) {
    if (!d.esSquad) return null;
    final total = d.cantidadTotalSquad ?? d.cantidadPersonas;
    final indice = d.indiceSquad;
    final nombre = d.nombreSquad?.trim();
    if (indice != null && total > 0) {
      final base = '$indice/$total del squad';
      if (nombre != null && nombre.isNotEmpty) return '$base "$nombre"';
      return base;
    }
    if (nombre != null && nombre.isNotEmpty) return 'Squad "$nombre" · $total personas';
    if (total > 1) return 'Squad · $total personas';
    return null;
  }

  Widget _panelOverlayResultado({
    required IconData icono,
    required String titulo,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icono, size: 16, color: Colors.white.withOpacity(0.9)),
              const SizedBox(width: 8),
              Text(
                titulo.toUpperCase(),
                style: GoogleFonts.baloo2(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withOpacity(0.8),
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildContenidoOk(_DatosValidacion d) {
    if (d.tipo == _TipoValidacion.promo) {
      return _buildContenidoOkPromo(d);
    }

    final username = d.username?.trim();
    final usernameFmt = (username == null || username.isEmpty)
        ? null
        : (username.startsWith('@') ? username : '@$username');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            CupertinoIcons.checkmark_alt,
            color: ColoresStaff.card,
            size: 36,
          ),
        ),
        SizedBox(height: 16),
        Text(
          _tituloValidacionOk(d),
          textAlign: TextAlign.center,
          style: GoogleFonts.baloo2(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: ColoresStaff.chipInactivo,
            height: 1.15,
          ),
        ),
        if (_subtituloSquadValidacion(d) != null) ...[
          const SizedBox(height: 8),
          Text(
            _subtituloSquadValidacion(d)!,
            textAlign: TextAlign.center,
            style: GoogleFonts.baloo2(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white.withOpacity(0.92),
              height: 1.2,
            ),
          ),
        ],
        SizedBox(height: 16),
        _panelOverlayResultado(
          icono: CupertinoIcons.qrcode,
          titulo: 'Código',
          child: Text(
            d.codigo,
            textAlign: TextAlign.center,
            style: GoogleFonts.baloo2(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 5,
              color: ColoresStaff.chipInactivo,
            ),
          ),
        ),
        if (d.nombreUsuario != null ||
            usernameFmt != null ||
            (d.edad != null && d.edad! > 0)) ...[
          SizedBox(height: 14),
          _panelOverlayResultado(
            icono: CupertinoIcons.person_crop_circle,
            titulo: 'Asistente',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (d.nombreUsuario != null)
                  Text(
                    d.nombreUsuario!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.baloo2(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: ColoresStaff.chipInactivo,
                      height: 1.1,
                    ),
                  ),
                if (usernameFmt != null) ...[
                  SizedBox(height: 4),
                  Text(
                    usernameFmt,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.baloo2(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withOpacity(0.88),
                    ),
                  ),
                ],
                if (d.edad != null && d.edad! > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: ColoresStaff.card,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          CupertinoIcons.calendar,
                          size: 18,
                          color: Color(0xFF166534),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${d.edad} años',
                          style: GoogleFonts.baloo2(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF166534),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (d.tipo == _TipoValidacion.lista && d.tituloEvento != null) ...[
          SizedBox(height: 14),
          _panelOverlayResultado(
            icono: CupertinoIcons.calendar,
            titulo: 'Evento',
            child: Text(
              d.tituloEvento!,
              textAlign: TextAlign.center,
              style: GoogleFonts.baloo2(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: ColoresStaff.chipInactivo,
                height: 1.3,
              ),
            ),
          ),
        ],
        if (d.tipo == _TipoValidacion.lista &&
            d.esSquad &&
            d.miembros.isNotEmpty) ...[
          const SizedBox(height: 14),
          _panelOverlayResultado(
            icono: CupertinoIcons.person_3_fill,
            titulo: 'Squad · ${d.cantidadPersonas}',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: d.miembros.map((nombre) {
                return Container(
                  width: double.infinity,
                  margin: EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.person_fill,
                        size: 14,
                        color: Colors.white.withOpacity(0.85),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          nombre,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.baloo2(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: ColoresStaff.chipInactivo,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildContenidoOkPromo(_DatosValidacion d) {
    final username = d.username?.trim();
    final usernameFmt = (username == null || username.isEmpty)
        ? null
        : (username.startsWith('@') ? username : '@$username');
    final titulo = d.tituloPromo?.trim();
    final descripcion = d.descripcionPromo?.trim();
    final ahoraUtc = DateTime.now().toUtc();
    final muestraInicio = d.fechaInicioPromo != null &&
        d.fechaInicioPromo!.isAfter(ahoraUtc);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            CupertinoIcons.gift_fill,
            color: ColoresStaff.card,
            size: 32,
          ),
        ),
        SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: BoxDecoration(
            color: ColoresStaff.card,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.tag_fill,
                    size: 15,
                    color: ColoresLocales.acentoVioleta,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'QUÉ INCLUYE',
                    style: GoogleFonts.baloo2(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: ColoresStaff.textoSecundario,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              if (titulo != null && titulo.isNotEmpty)
                Text(
                  titulo,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.baloo2(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: ColoresStaff.textoPrincipal,
                    height: 1.15,
                  ),
                ),
              if (descripcion != null && descripcion.isNotEmpty) ...[
                if (titulo != null && titulo.isNotEmpty) SizedBox(height: 10),
                Text(
                  descripcion,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.baloo2(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: ColoresStaff.textoSecundario,
                    height: 1.45,
                  ),
                ),
              ],
              if ((titulo == null || titulo.isEmpty) &&
                  (descripcion == null || descripcion.isEmpty))
                Text(
                  'Promoción sin detalle',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.baloo2(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: ColoresStaff.textoSecundario,
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: 12),
        Text(
          'Promo válida',
          textAlign: TextAlign.center,
          style: GoogleFonts.baloo2(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: Colors.white.withOpacity(0.95),
            height: 1.1,
          ),
        ),
        if (d.esSquad) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
            decoration: BoxDecoration(
              color: ColoresStaff.card,
              borderRadius: BorderRadius.circular(50),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.person_3_fill,
                  size: 18,
                  color: Color(0xFF166534),
                ),
                const SizedBox(width: 8),
                Text(
                  'Squad · ${d.cantidadPersonas} '
                  '${d.cantidadPersonas == 1 ? 'persona' : 'personas'}',
                  style: GoogleFonts.baloo2(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF166534),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (d.nombreUsuario != null || usernameFmt != null) ...[
          const SizedBox(height: 14),
          _panelOverlayResultado(
            icono: CupertinoIcons.person_crop_circle,
            titulo: 'Cliente',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (d.nombreUsuario != null)
                  Text(
                    d.nombreUsuario!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.baloo2(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: ColoresStaff.chipInactivo,
                      height: 1.1,
                    ),
                  ),
                if (usernameFmt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    usernameFmt,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.baloo2(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withOpacity(0.88),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (muestraInicio || d.fechaFinPromo != null) ...[
          const SizedBox(height: 14),
          _panelOverlayResultado(
            icono: CupertinoIcons.clock,
            titulo: 'Vigencia',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (muestraInicio)
                  Text(
                    'Comienza: ${_fmtFechaHoraLocal(d.fechaInicioPromo!)}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.baloo2(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withOpacity(0.92),
                    ),
                  ),
                if (muestraInicio && d.fechaFinPromo != null)
                  SizedBox(height: 6),
                if (d.fechaFinPromo != null)
                  Text(
                    'Válida hasta: ${_fmtFechaHoraLocal(d.fechaFinPromo!)}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.baloo2(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: ColoresStaff.chipInactivo,
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        _panelOverlayResultado(
          icono: CupertinoIcons.qrcode,
          titulo: 'Código',
          child: Text(
            d.codigo,
            textAlign: TextAlign.center,
            style: GoogleFonts.baloo2(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: Colors.white.withOpacity(0.92),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContenidoError(_DatosValidacion d) {
    final descripcion =
        _descripcionError(d.errorCode, d.errorMensaje ?? 'Error desconocido');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            CupertinoIcons.xmark,
            color: ColoresStaff.card,
            size: 34,
          ),
        ),
        SizedBox(height: 16),
        Text(
          _tituloError(d.errorCode),
          textAlign: TextAlign.center,
          style: GoogleFonts.baloo2(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: ColoresStaff.chipInactivo,
            height: 1.1,
          ),
        ),
        SizedBox(height: 12),
        Text(
          descripcion,
          textAlign: TextAlign.center,
          style: GoogleFonts.baloo2(
            fontSize: 15,
            color: Colors.white.withOpacity(0.88),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        _panelOverlayResultado(
          icono: CupertinoIcons.qrcode,
          titulo: 'Código leído',
          child: Text(
            d.codigo,
            textAlign: TextAlign.center,
            style: GoogleFonts.baloo2(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: ColoresStaff.chipInactivo,
            ),
          ),
        ),
      ],
    );
  }

  Widget _contenidoBotonCanje({
    required bool cargando,
    required String label,
    required Color colorLoader,
  }) {
    if (cargando) {
      return SizedBox(
        height: 22,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: colorLoader,
            ),
          ),
        ),
      );
    }
    return Text(
      label,
      style: GoogleFonts.baloo2(fontWeight: FontWeight.w900, fontSize: 16),
    );
  }

  Widget _buildBotonesOk() {
    final cargandoValidar = _canjeando && _canjeandoAccion == 'validar';
    final cargandoRechazar = _canjeando && _canjeandoAccion == 'rechazar';
    final sinPermiso = !_puedeTipoActual;
    final bloqueado = _canjeando || sinPermiso;

    return Opacity(
      opacity: sinPermiso ? 0.38 : 1,
      child: IgnorePointer(
        ignoring: sinPermiso,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: bloqueado ? null : () => unawaited(_onSolicitarCanje(validar: true)),
            style: ElevatedButton.styleFrom(
              backgroundColor: ColoresStaff.card,
              disabledBackgroundColor: ColoresStaff.chipInactivo,
              foregroundColor: ColoresLocales.acentoVioleta,
              disabledForegroundColor: ColoresLocales.acentoVioleta,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50),
              ),
              elevation: 0,
            ),
            child: _contenidoBotonCanje(
              cargando: cargandoValidar,
              label: _tipo == _TipoValidacion.lista
                  ? 'Confirmar ingreso'
                  : 'Canjear promo',
              colorLoader: ColoresLocales.acentoVioleta,
            ),
          ),
        ),
        SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: bloqueado ? null : () => unawaited(_onSolicitarCanje(validar: false)),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.06),
              foregroundColor: ColoresLocales.textoEnBoton,
              disabledForegroundColor: Colors.white.withOpacity(0.5),
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50),
              ),
            ),
            child: _contenidoBotonCanje(
              cargando: cargandoRechazar,
              label: 'Rechazar',
              colorLoader: ColoresStaff.chipInactivo,
            ),
          ),
        ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotonesError() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: () {
          if (_mostrandoSheetResultado) {
            Navigator.of(context).pop();
          } else {
            _limpiarYSeguir();
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: ColoresStaff.card,
          foregroundColor: const Color(0xFFDC2626),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
          elevation: 0,
        ),
        child: Text(
          'Continuar escaneando',
          style: GoogleFonts.baloo2(fontWeight: FontWeight.w900, fontSize: 16),
        ),
      ),
    );
  }
}

// ─── Marco QR liviano (4×4, aislado para hot reload) ────────────────────────

class _MarcoEscaneoQr extends StatefulWidget {
  const _MarcoEscaneoQr();

  @override
  State<_MarcoEscaneoQr> createState() => _MarcoEscaneoQrState();
}

class _MarcoEscaneoQrState extends State<_MarcoEscaneoQr>
    with SingleTickerProviderStateMixin {
  static const double _size = 210;
  static const double _inset = 16;
  static const int _gridN = 4;
  static const double _dotSize = 5.5;

  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _ctrl.value;
        final bordeOp = 0.55 + 0.3 * ((math.sin(t * math.pi * 2) + 1) / 2);
        final inner = _size - _inset * 2;
        final step = _gridN > 1 ? (inner - _dotSize) / (_gridN - 1) : 0.0;

        return SizedBox(
          width: _size,
          height: _size,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withOpacity(bordeOp.clamp(0.0, 1.0)),
                    width: 2,
                  ),
                ),
              ),
              for (var row = 0; row < _gridN; row++)
                for (var col = 0; col < _gridN; col++)
                  Positioned(
                    left: _inset + col * step,
                    top: _inset + row * step,
                    child: Container(
                      width: _dotSize,
                      height: _dotSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(
                          _opacidadPuntoMarcoQr(t, row * _gridN + col),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Historial tile ────────────────────────────────────────────────────────────

class _HistorialTile extends StatelessWidget {
  final _EntradaHistorial entrada;

  const _HistorialTile({required this.entrada});

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final hora = _fmtHoraStatic(entrada.cuando);
    final color = entrada.ok ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final bg = entrada.ok ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2);
    final esPromo = entrada.tipo == _TipoValidacion.promo;
    final tituloPromo = entrada.tituloPromo?.trim();
    final nombre = entrada.nombre?.trim();

    final tituloPrincipal = esPromo
        ? ((tituloPromo != null && tituloPromo.isNotEmpty)
            ? tituloPromo
            : (entrada.ok ? 'Promo' : 'Promo no válida'))
        : ((nombre != null && nombre.isNotEmpty)
            ? nombre
            : entrada.codigo);

    return Container(
      width: 148,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                entrada.ok
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.xmark_circle_fill,
                size: 12,
                color: color,
              ),
              SizedBox(width: 4),
              Text(
                hora,
                style: GoogleFonts.baloo2(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: ColoresStaff.textoSecundario,
                ),
              ),
            ],
          ),
          SizedBox(height: 5),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    esPromo
                        ? CupertinoIcons.gift_fill
                        : CupertinoIcons.ticket_fill,
                    size: 23,
                    color: ColoresLocales.acentoVioleta,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        tituloPrincipal,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.baloo2(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                          color: ColoresStaff.textoPrincipal,
                        ),
                      ),
                      SizedBox(height: 3),
                      if (esPromo) ...[
                        Text(
                          entrada.codigo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.baloo2(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            height: 1.1,
                            color: ColoresStaff.textoSecundario,
                          ),
                        ),
                        if (nombre != null && nombre.isNotEmpty) ...[
                          SizedBox(height: 1),
                          Text(
                            nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.baloo2(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              height: 1.1,
                              color: ColoresStaff.textoSecundario
                                  .withOpacity(0.85),
                            ),
                          ),
                        ],
                      ] else
                        Row(
                          children: [
                            Icon(
                              entrada.esSquad
                                  ? CupertinoIcons.person_3_fill
                                  : CupertinoIcons.person_fill,
                              size: 12,
                              color: ColoresLocales.acentoVioleta.withOpacity(0.8),
                            ),
                            SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                entrada.esSquad && entrada.cantidadPersonas > 1
                                    ? '${entrada.cantidadPersonas} personas'
                                    : (entrada.edad != null && entrada.edad! > 0)
                                        ? '${entrada.edad} años'
                                        : 'Individual',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.baloo2(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  height: 1.1,
                                  color: ColoresStaff.textoSecundario,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
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

// ─── Widgets auxiliares ───────────────────────────────────────────────────────

class _SegmentoOpcion extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool activo;
  final bool habilitado;
  final VoidCallback onTap;

  const _SegmentoOpcion({
    required this.label,
    required this.icon,
    required this.activo,
    this.habilitado = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final colorActivo = Colors.white;
    final colorInactivo = habilitado
        ? ColoresLocales.acentoVioleta
        : ColoresStaff.textoSecundario.withOpacity(0.45);
    return Opacity(
      opacity: habilitado ? 1 : 0.38,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 17,
                color: activo ? colorActivo : colorInactivo,
              ),
              SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.baloo2(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: activo ? colorActivo : colorInactivo,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
