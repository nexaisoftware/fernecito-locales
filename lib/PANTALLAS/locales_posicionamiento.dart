library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants.dart';
import '../widgets/tema_locales_scope.dart';
import '../core/navegacion_posicionamiento.dart';
import '../core/servicio_edges_eventos.dart';
import '../core/supabase_client.dart';
import '../core/suscripcion_locales.dart';

// ─── Modelo ──────────────────────────────────────────────────────────────────

class _EventoPos {
  final String idEvento;
  final String titulo;
  final String urlFlyer;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;
  /// Hasta cuándo aparece el evento en cartelera (min fechaFin, subida+30d).
  final DateTime? fechaFinPublicacion;
  /// Hasta cuándo dura el boost de posicionamiento (min fechaFin, now+N días).
  final DateTime? fechaFinJerarquia;
  final String jerarquia;

  const _EventoPos({
    required this.idEvento,
    required this.titulo,
    required this.urlFlyer,
    required this.fechaInicio,
    required this.fechaFin,
    required this.fechaFinPublicacion,
    required this.fechaFinJerarquia,
    required this.jerarquia,
  });

  bool get posicionamientoVencido =>
      fechaFinJerarquia != null && fechaFinJerarquia!.isBefore(DateTime.now());

  bool get posicionLimitadaPorEvento {
    if (fechaFinJerarquia == null || fechaFin == null) return false;
    return !fechaFinJerarquia!.isAfter(
      fechaFin!.add(const Duration(minutes: 1)),
    );
  }

  int? get diasBoostRegla => switch (jerarquia) {
    'recomendado_fernecito' => 15,
    'top' => 10,
    'top_ultra' => 10,
    _ => null,
  };

  int get diasRestantesPosicionamiento {
    if (fechaFinJerarquia == null) return 0;
    return fechaFinJerarquia!.difference(DateTime.now()).inDays.clamp(0, 999);
  }

  _EventoPos copyWith({String? jerarquia, DateTime? fechaFinJerarquia}) => _EventoPos(
    idEvento: idEvento,
    titulo: titulo,
    urlFlyer: urlFlyer,
    fechaInicio: fechaInicio,
    fechaFin: fechaFin,
    fechaFinPublicacion: fechaFinPublicacion,
    fechaFinJerarquia: fechaFinJerarquia ?? this.fechaFinJerarquia,
    jerarquia: jerarquia ?? this.jerarquia,
  );

  factory _EventoPos.fromMap(Map<String, dynamic> m) => _EventoPos(
    idEvento: m['id_evento'].toString(),
    titulo: ((m['titulo_evento'] as String?) ?? '').trim().isEmpty
        ? 'Evento sin título'
        : (m['titulo_evento'] as String).trim(),
    urlFlyer: (m['url_flyer'] as String?) ?? '',
    fechaInicio: _parseDate(m['fecha_inicio']),
    fechaFin: _parseDate(m['fecha_fin']),
    fechaFinPublicacion: _parseDate(m['fecha_fin_publicacion'] ?? m['fecha_fin']),
    fechaFinJerarquia: _parseDate(m['fecha_fin_jerarquia']),
    jerarquia: (m['jerarquia'] as String?) ?? 'gratis',
  );

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }
}

// ─── Pantalla principal ──────────────────────────────────────────────────────

class LocalesPosicionamiento extends StatefulWidget {
  final int tabInicial;

  const LocalesPosicionamiento({super.key, this.tabInicial = 0});

  @override
  State<LocalesPosicionamiento> createState() => LocalesPosicionamientoState();
}

class LocalesPosicionamientoState extends State<LocalesPosicionamiento> {
  int _tab = 0;

  bool _localVerificado = false;
  String? _tipoSuscripcionRaw;
  bool _cargandoPerfil = true;
  String? _uid;

  // Créditos reales desde perfiles_locales
  int _credRecomendados = 0;
  int _credTop = 0;
  int _credTopUltra = 0;

  List<_EventoPos> _eventosPos = [];
  List<_EventoPos> _eventosSinPos = [];
  bool _cargandoEventos = true;
  final Set<String> _cancelando = {};

  /// Card que recibe el flash violeta al venir desde Mis eventos.
  String? _pulsoResaltado;
  final Set<String> _posicionando = {};

  final Map<String, GlobalKey> _cardKeys = {};

  GlobalKey _keyForCard(String id) =>
      _cardKeys.putIfAbsent(id, () => GlobalKey());

  /// Desde [LocalesHome] / Mis eventos: tab Posición + scroll + flash violeta.
  Future<void> resaltarEventoPorId(String idEvento) async {
    if (!mounted) return;
    final enPos = _eventosPos.any((e) => e.idEvento == idEvento);
    final enSin = _eventosSinPos.any((e) => e.idEvento == idEvento);
    setState(() {
      if (enPos) {
        _tab = 0;
      } else if (enSin) {
        _tab = 1;
      } else {
        _tab = 1;
      }
    });
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollYAnimarResaltado(idEvento);
      });
    });
  }

  Future<void> _scrollYAnimarResaltado(String idEvento) async {
    final key = _keyForCard(idEvento);
    final ctx = key.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.35,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOutCubic,
      );
    }
    if (!mounted) return;
    setState(() => _pulsoResaltado = idEvento);
    // 80 ms violeta fijo + ~4000 ms fade a blanco + margen
    await Future<void>.delayed(const Duration(milliseconds: 4180));
    if (!mounted) return;
    setState(() => _pulsoResaltado = null);
  }

  @override
  void initState() {
    super.initState();
    _tab = widget.tabInicial.clamp(0, 1);
    _init();
  }

  Future<void> _init() async {
    await _cargarPerfil();
    await _cargarEventos();
  }

  Future<void> _cargarPerfil() async {
    try {
      final uid = ServicioSupabase().usuarioActual?.id;
      if (uid == null) return;
      _uid = uid;
      final data = await ServicioSupabase().cliente
          .from('perfiles_locales')
          .select(
            'local_verificado, cupos_recomendado, cupos_top_cartelera, cupos_top_ultra',
          )
          .eq('id', uid)
          .maybeSingle();
      final tipoRaw = await SuscripcionLocales.leerTipoRawDesdePerfil(uid);
      if (!mounted) return;
      setState(() {
        if (data != null) {
          _localVerificado = data['local_verificado'] == true;
          _credRecomendados = (data['cupos_recomendado'] as num?)?.toInt() ?? 0;
          _credTop = (data['cupos_top_cartelera'] as num?)?.toInt() ?? 0;
          _credTopUltra = (data['cupos_top_ultra'] as num?)?.toInt() ?? 0;
        }
        _tipoSuscripcionRaw = tipoRaw;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _cargandoPerfil = false);
    }
  }

  Future<void> _cargarEventos() async {
    if (_uid == null) return;
    try {
      final data = await ServicioSupabase().cliente
          .from('eventos')
          .select(
            'id_evento, titulo_evento, url_flyer, fecha_inicio, fecha_fin, fecha_fin_publicacion, fecha_fin_jerarquia, jerarquia',
          )
          .eq('id_local', _uid!)
          .eq('estado_publicacion', 'publicado')
          .order('fecha_inicio', ascending: true);

      final eventos = (data as List)
          .cast<Map<String, dynamic>>()
          .map(_EventoPos.fromMap)
          .toList();

      if (mounted) {
        setState(() {
          const nivelesConPos = {
            'recomendado_fernecito',
            'top',
            'top_ultra',
          };
          _eventosPos =
              eventos.where((e) => nivelesConPos.contains(e.jerarquia)).toList();
          _eventosSinPos =
              eventos.where((e) => !nivelesConPos.contains(e.jerarquia)).toList();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _cargandoEventos = false);
    }
  }

  // ── Lógica de posicionamiento ─────────────────────────────────────────────

  static const Map<String, int> _ordenJerarquia = {
    'gratis': 0,
    'normal': 1,
    'recomendado_fernecito': 2,
    'top': 3,
    'top_ultra': 4,
  };

  List<String> _nivelesSuperiores(String jerarquiaActual) {
    final actual = _ordenJerarquia[jerarquiaActual] ?? 0;
    const candidatos = ['recomendado_fernecito', 'top', 'top_ultra'];
    return candidatos
        .where((nivel) => (_ordenJerarquia[nivel] ?? 0) > actual)
        .toList();
  }

  int _creditosPorNivel(String nivel) {
    return switch (nivel) {
      'recomendado_fernecito' => _credRecomendados,
      'top' => _credTop,
      'top_ultra' => _credTopUltra,
      _ => 0,
    };
  }

  ({String label, Color color, IconData icon}) _metaNivel(String nivel) {
    return switch (nivel) {
      'recomendado_fernecito' => (
        label: 'Rec. Fernecito',
        color: ColoresLocales.jerarquiaRecomendado,
        icon: CupertinoIcons.hand_thumbsup_fill,
      ),
      'top' => (
        label: 'Top Cartelera',
        color: ColoresLocales.jerarquiaTop,
        icon: CupertinoIcons.star_fill,
      ),
      'top_ultra' => (
        label: 'Top Ultra',
        color: ColoresLocales.jerarquiaUltra,
        icon: CupertinoIcons.rosette,
      ),
      _ => (
        label: nivel,
        color: Colors.grey,
        icon: CupertinoIcons.question_circle,
      ),
    };
  }

  Future<void> _abrirOpcionesMejora(_EventoPos evento) async {
    if (_posicionando.contains(evento.idEvento)) return;

    final opciones = _nivelesSuperiores(evento.jerarquia);
    if (opciones.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Este evento ya está en la jerarquía máxima.')),
      );
      return;
    }

    String seleccionado = opciones.first;

    final String? destinoSeleccionado = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ColoresLocales.superficie,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final creditosSel = _creditosPorNivel(seleccionado);
            final metaSel = _metaNivel(seleccionado);
            final bloqueado = _posicionando.contains(evento.idEvento);

            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Color(0xFFD1D5DB),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    SizedBox(height: 14),
                    Text(
                      'Mejorar posicionamiento',
                      style: GoogleFonts.baloo2(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: ColoresLocales.textoOnFondoClaro,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      evento.titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.baloo2(
                        fontSize: 13,
                        color: ColoresLocales.textoSecundarioOnFondoClaro,
                      ),
                    ),
                    SizedBox(height: 14),
                    ...opciones.map((nivel) {
                      final meta = _metaNivel(nivel);
                      final seleccionadoNivel = seleccionado == nivel;
                      final creditos = _creditosPorNivel(nivel);
                      final habilitado = creditos > 0 && !bloqueado;

                      return Container(
                        margin: EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: habilitado
                              ? () => setModalState(() => seleccionado = nivel)
                              : null,
                          borderRadius: BorderRadius.circular(14),
                          child: AnimatedContainer(
                            duration: Duration(milliseconds: 160),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: seleccionadoNivel
                                  ? meta.color.withOpacity(0.12)
                                  : ColoresLocales.cardInput,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: seleccionadoNivel
                                    ? meta.color.withOpacity(0.45)
                                    : ColoresLocales.acentoVioleta.withOpacity(0.16),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(meta.icon, color: meta.color, size: 18),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Mejorar a ${meta.label}',
                                        style: GoogleFonts.baloo2(
                                          fontWeight: FontWeight.w900,
                                          color: ColoresLocales.textoOnFondoClaro,
                                        ),
                                      ),
                                      Text(
                                        'Costo: 1 crédito · Disponibles: $creditos',
                                        style: GoogleFonts.baloo2(
                                          fontSize: 12,
                                          color: habilitado
                                              ? ColoresLocales.textoSecundarioOnFondoClaro
                                              : const Color(0xFFDC2626),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (seleccionadoNivel)
                                  Icon(CupertinoIcons.check_mark_circled_solid,
                                      color: meta.color, size: 18),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: bloqueado ? null : () => Navigator.pop(ctx),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: (creditosSel <= 0 || bloqueado)
                                ? null
                                : () => Navigator.pop(ctx, seleccionado),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: metaSel.color,
                              foregroundColor: ColoresLocales.textoEnBoton,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(50),
                              ),
                            ),
                            child: Text(
                              'Confirmar mejora',
                              style: GoogleFonts.baloo2(fontWeight: FontWeight.w900),
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

    if (destinoSeleccionado == null || !mounted) return;

    await _posicionarEvento(
      context,
      evento,
      destinoSeleccionado,
      solicitarConfirmacion: false,
    );
  }


  Future<void> _posicionarEvento(
    BuildContext context,
    _EventoPos evento,
    String jerarquiaDestino, {
    bool solicitarConfirmacion = true,
  }) async {
    final (int credDisp, String labelNivel, Color colorNivel, IconData iconNivel) =
        switch (jerarquiaDestino) {
      'recomendado_fernecito' => (
        _credRecomendados,
        'Rec. Fernecito',
        ColoresLocales.jerarquiaRecomendado,
        CupertinoIcons.hand_thumbsup_fill,
      ),
      'top' => (
        _credTop,
        'Top Cartelera',
        ColoresLocales.jerarquiaTop,
        CupertinoIcons.star_fill,
      ),
      'top_ultra' => (
        _credTopUltra,
        'Top Ultra',
        ColoresLocales.jerarquiaUltra,
        CupertinoIcons.rosette,
      ),
      _ => (0, jerarquiaDestino, Colors.grey, CupertinoIcons.question_circle),
    };

    if (credDisp <= 0) {
      if (!context.mounted) return;
      _mostrarError(
        context,
        'Sin créditos',
        'No tenés créditos disponibles para $labelNivel.',
      );
      return;
    }

    if (solicitarConfirmacion) {
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: colorNivel.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(iconNivel, color: colorNivel, size: 26),
                ),
                SizedBox(height: 14),
                Text(
                  'Posicionar en $labelNivel',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.baloo2(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: ColoresLocales.textoOnFondoClaro,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '"${evento.titulo}"',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.baloo2(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ColoresLocales.textoSecundarioOnFondoClaro,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colorNivel.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(iconNivel, size: 14, color: colorNivel),
                      const SizedBox(width: 6),
                      Text(
                        'Usa 1 crédito · Te quedarán ${credDisp - 1}',
                        style: GoogleFonts.baloo2(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colorNivel,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50),
                          ),
                        ),
                        child: Text(
                          'Cancelar',
                          style: GoogleFonts.baloo2(
                            fontWeight: FontWeight.w700,
                            color: ColoresLocales.textoSecundarioOnFondoClaro,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: TextButton.styleFrom(
                          backgroundColor: colorNivel,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50),
                          ),
                        ),
                        child: Text(
                          'Confirmar',
                          style: GoogleFonts.baloo2(
                            fontWeight: FontWeight.w800,
                            color: ColoresLocales.textoEnBoton,
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

      if (confirmado != true) return;
    }

    setState(() => _posicionando.add(evento.idEvento));
    try {
      final res = await ServicioEdgesEventos().mejorarJerarquia(
        idEvento: evento.idEvento,
        jerarquiaDestino: jerarquiaDestino,
      );

      if (!mounted) return;

      final creditosRestantes = (res['creditos_restantes'] as num?)?.toInt();
      setState(() {
        if (creditosRestantes != null) {
          if (jerarquiaDestino == 'recomendado_fernecito') {
            _credRecomendados = creditosRestantes;
          } else if (jerarquiaDestino == 'top') {
            _credTop = creditosRestantes;
          } else if (jerarquiaDestino == 'top_ultra') {
            _credTopUltra = creditosRestantes;
          }
        }

        _eventosSinPos.removeWhere((e) => e.idEvento == evento.idEvento);

        final idxPos = _eventosPos.indexWhere((e) => e.idEvento == evento.idEvento);
        final finJerarquiaRaw = res['fecha_fin_jerarquia'];
        final finJerarquia = finJerarquiaRaw != null
            ? DateTime.tryParse(finJerarquiaRaw.toString())?.toLocal()
            : null;
        final actualizado = evento.copyWith(
          jerarquia: jerarquiaDestino,
          fechaFinJerarquia: finJerarquia,
        );
        if (idxPos >= 0) {
          _eventosPos[idxPos] = actualizado;
        } else {
          _eventosPos.add(actualizado);
        }

        _posicionando.remove(evento.idEvento);
      });

      NavegacionPosicionamiento.notificarActualizacion();
    } catch (e) {
      if (!mounted) return;
      setState(() => _posicionando.remove(evento.idEvento));
      final msg = e
          .toString()
          .replaceAll('Exception: ', '')
          .replaceAll('Edge "mejorar_jerarquia" respondio HTTP', '')
          .trim();
      _mostrarError(this.context, 'No se pudo posicionar', msg);
    }
  }

  void _mostrarError(BuildContext context, String titulo, String mensaje) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          titulo,
          style: GoogleFonts.baloo2(fontWeight: FontWeight.w900),
        ),
        content: Text(mensaje, style: GoogleFonts.baloo2()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Entendido',
              style: GoogleFonts.baloo2(
                fontWeight: FontWeight.w700,
                color: ColoresLocales.acentoVioleta,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Cancelar / despublicar evento ─────────────────────────────────────────

  Future<void> _cancelarEvento(_EventoPos evento) async {
    if (_cancelando.contains(evento.idEvento)) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Despublicar evento',
          style: GoogleFonts.baloo2(fontWeight: FontWeight.w900),
        ),
        content: Text(
          '¿Querés quitar "${evento.titulo}" de la cartelera?\n\nPasará al historial con estado cancelado. No podés volver a publicarlo si ya finalizó.',
          style: GoogleFonts.baloo2(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No, mantener'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: Text(
              'Sí, despublicar',
              style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _cancelando.add(evento.idEvento));
    try {
      await ServicioEdgesEventos().cancelarEvento(idEvento: evento.idEvento);
      if (!mounted) return;
      setState(() {
        _eventosPos.removeWhere((e) => e.idEvento == evento.idEvento);
        _eventosSinPos.removeWhere((e) => e.idEvento == evento.idEvento);
        _cancelando.remove(evento.idEvento);
      });
      NavegacionPosicionamiento.notificarActualizacion();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '"${evento.titulo}" fue despublicado y movido al historial.',
              style: GoogleFonts.baloo2(),
            ),
            backgroundColor: Color(0xFF374151),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancelando.remove(evento.idEvento));
      _mostrarError(context, 'No se pudo despublicar', e.toString().replaceAll('Exception: ', ''));
    }
  }

  // ── Estado de cuenta ──────────────────────────────────────────────────────

  String get _estadoCuenta => _localVerificado ? 'Verificado' : 'Gratuita';

  Color get _colorEstado => _localVerificado
      ? ColoresLocales.acentoVioleta
      : ColoresLocales.textoSecundarioOnFondoClaro;

  IconData get _iconEstado => _localVerificado
      ? CupertinoIcons.checkmark_seal_fill
      : CupertinoIcons.lock_open_fill;

  // ── Dialog info crédito ───────────────────────────────────────────────────

  void _mostrarDialogoCredito({
    required BuildContext ctx,
    required IconData icono,
    required Color color,
    required String titulo,
    required int valor,
    required String descripcion,
  }) {
    showDialog<void>(
      context: ctx,
      builder: (_) => Dialog(
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
              Text(
                '$valor',
                textAlign: TextAlign.center,
                style: GoogleFonts.baloo2(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              Text(
                'créditos disponibles',
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
                    padding: const EdgeInsets.symmetric(vertical: 12),
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

  Future<void> _refreshPantalla() async {
    if (!mounted) return;
    setState(() {
      _cargandoPerfil = true;
      _cargandoEventos = true;
    });
    await _init();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    TemaLocalesScope.of(context);
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Center(
              child: Text(
                'Posicionamiento',
                style: GoogleFonts.baloo2(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: ColoresLocales.acentoVioleta,
                ),
              ),
            ),
          ),
          GestureDetector(
            onVerticalDragEnd: (details) {
              final speed = details.primaryVelocity ?? 0;
              if (speed > 220) {
                _refreshPantalla();
              }
            },
            child: _buildPanelEstado(context),
          ),
          SizedBox(height: 12),
          _buildSwitch(),
          SizedBox(height: 10),
          Divider(height: 1, thickness: 1, color: ColoresLocales.separador),
          Expanded(
            child: RefreshIndicator(
              color: ColoresLocales.acentoVioleta,
              onRefresh: _refreshPantalla,
              child: _cargandoEventos
                  ? ListView(
                      physics: AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(height: 140),
                        Center(
                          child: CircularProgressIndicator(
                            color: ColoresLocales.acentoVioleta,
                            strokeWidth: 2,
                          ),
                        ),
                      ],
                    )
                  : IndexedStack(
                      index: _tab,
                      children: [
                        _TabPosicionados(
                          eventos: _eventosPos,
                          posicionando: _posicionando,
                          cancelando: _cancelando,
                          cardKeyFor: _keyForCard,
                          idResaltar: _pulsoResaltado,
                          onMejorar: _abrirOpcionesMejora,
                          onCancelar: _cancelarEvento,
                        ),
                        _TabSinPosicion(
                          eventos: _eventosSinPos,
                          credRecomendados: _credRecomendados,
                          credTop: _credTop,
                          credTopUltra: _credTopUltra,
                          posicionando: _posicionando,
                          cancelando: _cancelando,
                          localVerificado: _localVerificado,
                          cardKeyFor: _keyForCard,
                          idResaltar: _pulsoResaltado,
                          onPositionar: (ev, nivel) =>
                              _posicionarEvento(context, ev, nivel),
                          onCancelar: _cancelarEvento,
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Panel estado + créditos ───────────────────────────────────────────────

  Widget _buildPanelEstado(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Container(
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
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: _cargandoPerfil
            ? Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: ColoresLocales.acentoVioleta,
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_iconEstado, size: 14, color: _colorEstado),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _colorEstado.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(
                            color: _colorEstado.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          _estadoCuenta,
                          style: GoogleFonts.baloo2(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _colorEstado,
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
                            color: ColoresLocales.acentoVioleta.withOpacity(
                              0.1,
                            ),
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(
                              color: ColoresLocales.acentoVioleta.withOpacity(
                                0.28,
                              ),
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
                            _CreditoTexto(
                              icono: CupertinoIcons.hand_thumbsup_fill,
                              label: 'Rec.Fernecito:',
                              valor: _credRecomendados,
                              color: ColoresLocales.jerarquiaRecomendado,
                              onTap: () => _mostrarDialogoCredito(
                                ctx: context,
                                icono: CupertinoIcons.hand_thumbsup_fill,
                                color: ColoresLocales.jerarquiaRecomendado,
                                titulo: 'Recomendaciones Fernecito',
                                valor: _credRecomendados,
                                descripcion:
                                    'Tus eventos aparecen destacados en la sección de recomendaciones de Fernecito, con mayor visibilidad frente a usuarios afines a tu propuesta.',
                              ),
                            ),
                            _CreditoTexto(
                              icono: CupertinoIcons.star_fill,
                              label: 'Top:',
                              valor: _credTop,
                              color: ColoresLocales.jerarquiaTop,
                              onTap: () => _mostrarDialogoCredito(
                                ctx: context,
                                icono: CupertinoIcons.star_fill,
                                color: ColoresLocales.jerarquiaTop,
                                titulo: 'Top Cartelera',
                                valor: _credTop,
                                descripcion:
                                    'Posicionás tu evento en el top de la cartelera principal de Fernecito. Máxima visibilidad para todos los usuarios que navegan la app.',
                              ),
                            ),
                            _CreditoTexto(
                              icono: CupertinoIcons.rosette,
                              label: 'Top Ultra:',
                              valor: _credTopUltra,
                              color: ColoresLocales.jerarquiaUltra,
                              onTap: () => _mostrarDialogoCredito(
                                ctx: context,
                                icono: CupertinoIcons.rosette,
                                color: ColoresLocales.jerarquiaUltra,
                                titulo: 'Top Ultra',
                                valor: _credTopUltra,
                                descripcion:
                                    'Top Ultra — máxima exposición en cartelera',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSwitch() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: ColoresLocales.cardLavanda,
          borderRadius: BorderRadius.circular(50),
        ),
        child: Row(
          children: [
            _SwitchTab(
              label: 'Posicionados',
              activo: _tab == 0,
              onTap: () => setState(() => _tab = 0),
            ),
            _SwitchTab(
              label: 'Sin posición',
              activo: _tab == 1,
              onTap: () => setState(() => _tab = 1),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Switch tab ───────────────────────────────────────────────────────────────

class _SwitchTab extends StatelessWidget {
  final String label;
  final bool activo;
  final VoidCallback onTap;

  const _SwitchTab({
    required this.label,
    required this.activo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 200),
          margin: EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: activo ? ColoresLocales.acentoVioleta : Colors.transparent,
            borderRadius: BorderRadius.circular(50),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.baloo2(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: activo
                  ? ColoresLocales.textoEnBoton
                  : ColoresLocales.textoSecundarioOnFondoClaro,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Crédito texto plano tappable ────────────────────────────────────────────

class _CreditoTexto extends StatelessWidget {
  final IconData icono;
  final String label;
  final int valor;
  final Color color;
  final VoidCallback onTap;

  const _CreditoTexto({
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

// ─── Tab: Posicionados ────────────────────────────────────────────────────────

class _TabPosicionados extends StatelessWidget {
  final List<_EventoPos> eventos;
  final Set<String> posicionando;
  final Set<String> cancelando;
  final GlobalKey Function(String id) cardKeyFor;
  final String? idResaltar;
  final void Function(_EventoPos evento) onMejorar;
  final void Function(_EventoPos evento) onCancelar;

  const _TabPosicionados({
    required this.eventos,
    required this.posicionando,
    required this.cancelando,
    required this.cardKeyFor,
    required this.idResaltar,
    required this.onMejorar,
    required this.onCancelar,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    if (eventos.isEmpty) {
      return _EmptyState(
        icono: CupertinoIcons.rocket_fill,
        titulo: 'Sin posicionamiento activo',
        subtitulo:
            'Usá tus créditos para destacar tus eventos en la cartelera.',
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: eventos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final ev = eventos[i];
        return KeyedSubtree(
          key: cardKeyFor(ev.idEvento),
          child: _CardPosicionado(
            evento: ev,
            resaltar: idResaltar == ev.idEvento,
            cargando: posicionando.contains(ev.idEvento),
            cancelando: cancelando.contains(ev.idEvento),
            onMejorar: onMejorar,
            onCancelar: onCancelar,
          ),
        );
      },
    );
  }
}

// ─── Tab: Sin posición ────────────────────────────────────────────────────────

class _TabSinPosicion extends StatelessWidget {
  final List<_EventoPos> eventos;
  final int credRecomendados;
  final int credTop;
  final int credTopUltra;
  final Set<String> posicionando;
  final Set<String> cancelando;
  final bool localVerificado;
  final GlobalKey Function(String id) cardKeyFor;
  final String? idResaltar;
  final void Function(_EventoPos evento, String nivel) onPositionar;
  final void Function(_EventoPos evento) onCancelar;

  const _TabSinPosicion({
    required this.eventos,
    required this.credRecomendados,
    required this.credTop,
    required this.credTopUltra,
    required this.posicionando,
    required this.cancelando,
    required this.localVerificado,
    required this.cardKeyFor,
    required this.idResaltar,
    required this.onPositionar,
    required this.onCancelar,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    if (eventos.isEmpty) {
      return _EmptyState(
        icono: CupertinoIcons.checkmark_seal_fill,
        titulo: '¡Todos tus eventos están posicionados!',
        subtitulo:
            'Todos tus eventos activos ya tienen posicionamiento. ¡Excelente trabajo!',
      );
    }

    final banner = !localVerificado
        ? Container(
            margin: EdgeInsets.fromLTRB(16, 16, 16, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ColoresLocales.mostazaDestacado.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Color(0xFFF59E0B), size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Verificá tu local para acceder al posicionamiento en cartelera',
                    style: GoogleFonts.baloo2(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: ColoresLocales.textoOnFondoClaro,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/administrar_subscripciones'),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: ColoresLocales.textoEnBoton,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  child: Text(
                    'Ver planes',
                    style: GoogleFonts.baloo2(fontWeight: FontWeight.w800, fontSize: 11),
                  ),
                ),
              ],
            ),
          )
        : const SizedBox(height: 16);

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      itemCount: eventos.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        if (i == 0) return banner;
        final ev = eventos[i - 1];
        return KeyedSubtree(
          key: cardKeyFor(ev.idEvento),
          child: _CardSinPosicion(
            evento: ev,
            credRecomendados: credRecomendados,
            credTop: credTop,
            credTopUltra: credTopUltra,
            posicionando: posicionando,
            cancelando: cancelando,
            resaltar: idResaltar == ev.idEvento,
            onPositionar: onPositionar,
            onCancelar: onCancelar,
          ),
        );
      },
    );

  }
}

// ─── Envoltorio: fondo animado (violeta → blanco) ────────────────────────────

class _CardConResaltado extends StatefulWidget {
  final bool resaltar;
  final Color borderColor;
  final Color shadowColor;
  final Widget child;

  const _CardConResaltado({
    required this.resaltar,
    required this.borderColor,
    required this.shadowColor,
    required this.child,
  });

  @override
  State<_CardConResaltado> createState() => _CardConResaltadoState();
}

class _CardConResaltadoState extends State<_CardConResaltado> {
  bool _animandoResaltado = false;
  Color? _bgAnimacion;
  Duration _duracionColor = Duration.zero;

  @override
  void didUpdateWidget(_CardConResaltado oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resaltar && !oldWidget.resaltar) {
      _iniciarResaltado();
    }
  }

  void _iniciarResaltado() {
    setState(() {
      _animandoResaltado = true;
      _duracionColor = Duration.zero;
      _bgAnimacion = ColoresLocales.acentoVioletaMarca.withOpacity(0.26);
    });
    Future.delayed(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      setState(() {
        _duracionColor = const Duration(seconds: 4);
        _bgAnimacion = ColoresLocales.superficie;
      });
      Future.delayed(const Duration(seconds: 4), () {
        if (!mounted) return;
        setState(() {
          _animandoResaltado = false;
          _bgAnimacion = null;
          _duracionColor = Duration.zero;
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final color = _animandoResaltado && _bgAnimacion != null
        ? _bgAnimacion!
        : ColoresLocales.superficie;
    return AnimatedContainer(
      duration: _duracionColor,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: widget.borderColor),
        boxShadow: [
          BoxShadow(
            color: widget.shadowColor,
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: widget.child,
    );
  }
}

// ─── Card: evento posicionado ────────────────────────────────────────────────

class _CardPosicionado extends StatelessWidget {
  final _EventoPos evento;
  final bool resaltar;
  final bool cargando;
  final bool cancelando;
  final void Function(_EventoPos evento) onMejorar;
  final void Function(_EventoPos evento) onCancelar;

  const _CardPosicionado({
    required this.evento,
    this.resaltar = false,
    required this.cargando,
    required this.cancelando,
    required this.onMejorar,
    required this.onCancelar,
  });

  String get _nivelLabel => switch (evento.jerarquia) {
    'recomendado_fernecito' => 'Rec. Fernecito',
    'top' => 'Top Cartelera',
    'top_ultra' => 'Top Ultra',
    'normal' => 'Verificado',
    _ => 'Estándar',
  };

  Color get _nivelColor => switch (evento.jerarquia) {
    'recomendado_fernecito' => ColoresLocales.jerarquiaRecomendado,
    'top' => ColoresLocales.jerarquiaTop,
    'top_ultra' => ColoresLocales.jerarquiaUltra,
    _ => ColoresLocales.textoSecundarioOnFondoClaro,
  };

  IconData get _nivelIcon => switch (evento.jerarquia) {
    'recomendado_fernecito' => CupertinoIcons.hand_thumbsup_fill,
    'top' => CupertinoIcons.star_fill,
    'top_ultra' => CupertinoIcons.rosette,
    _ => CupertinoIcons.checkmark_circle,
  };

  // Fin del boost según fecha_fin_jerarquia (10/15 días o fin del evento).
  String get _etiquetaTiempo {
    if (evento.posicionamientoVencido) return 'Posicionamiento finalizado';
    final dias = evento.diasRestantesPosicionamiento;
    if (dias == 0) return 'Último día';
    if (dias == 1) return '1 día restante';
    return '$dias días restantes';
  }

  Color get _colorTiempo {
    if (evento.posicionamientoVencido) return const Color(0xFF6B7280);
    return _nivelColor;
  }

  String get _encabezadoFinPosicionamiento {
    if (evento.posicionamientoVencido) {
      return '$_nivelLabel · Posicionamiento finalizado';
    }
    return '$_nivelLabel · Fin de posicionamiento';
  }

  String? get _subtituloFinPosicionamiento {
    if (evento.posicionLimitadaPorEvento && evento.fechaFin != null) {
      return 'Termina con el evento el ${_fmtFecha(evento.fechaFin)}';
    }
    final dias = evento.diasBoostRegla;
    if (dias != null) {
      return 'Duración: $dias días o fin del evento (lo que ocurra primero)';
    }
    return null;
  }

  String get _textoFinPosicionamiento {
    if (evento.fechaFinJerarquia == null) {
      return 'Según fin del evento';
    }
    final fecha = _fmtFecha(evento.fechaFinJerarquia);
    if (evento.posicionamientoVencido) {
      return 'Finalizó el $fecha';
    }
    return '$fecha · $_etiquetaTiempo';
  }

  List<String> get _opcionesSuperiores => switch (evento.jerarquia) {
    'recomendado_fernecito' => ['top', 'top_ultra'],
    'top' => ['top_ultra'],
    _ => const [],
  };

  String _labelNivel(String nivel) => switch (nivel) {
    'recomendado_fernecito' => 'Rec. Fernecito',
    'top' => 'Top Cartelera',
    'top_ultra' => 'Top Ultra',
    _ => nivel,
  };

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return _CardConResaltado(
      resaltar: resaltar,
      borderColor: _nivelColor.withOpacity(0.2),
      shadowColor: _nivelColor.withOpacity(0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FlyerThumb(url: evento.urlFlyer),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        evento.titulo,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.baloo2(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: ColoresLocales.textoOnFondoClaro,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _nivelColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(
                            color: _nivelColor.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_nivelIcon, size: 11, color: _nivelColor),
                            const SizedBox(width: 4),
                            Text(
                              _nivelLabel,
                              style: GoogleFonts.baloo2(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: _nivelColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (evento.fechaInicio != null)
                        _InfoRow(
                          icono: CupertinoIcons.calendar,
                          texto: _fmtFecha(evento.fechaInicio),
                        ),
                      SizedBox(height: 10),
                      if (_opcionesSuperiores.isNotEmpty)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: cargando ? null : () => onMejorar(evento),
                            icon: cargando
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Icon(CupertinoIcons.arrow_up_right_circle_fill, size: 15),
                            label: Text(
                              'Mejorar a ${_labelNivel(_opcionesSuperiores.first)}',
                              style: GoogleFonts.baloo2(
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _nivelColor,
                              foregroundColor: ColoresLocales.textoEnBoton,
                              minimumSize: const Size.fromHeight(34),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(50),
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: ColoresLocales.superficieElevada,
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: Text(
                            'Jerarquía máxima alcanzada',
                            style: GoogleFonts.baloo2(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: ColoresLocales.textoSecundarioOnFondoClaro,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: _colorTiempo.withValues(alpha: 0.07),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(18),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _colorTiempo.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    evento.posicionamientoVencido
                        ? CupertinoIcons.checkmark_circle_fill
                        : _nivelIcon,
                    size: 13,
                    color: _colorTiempo,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _encabezadoFinPosicionamiento,
                        style: GoogleFonts.baloo2(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _colorTiempo,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _textoFinPosicionamiento,
                        style: GoogleFonts.baloo2(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: _colorTiempo,
                          height: 1.25,
                        ),
                      ),
                      if (_subtituloFinPosicionamiento != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          _subtituloFinPosicionamiento!,
                          style: GoogleFonts.baloo2(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: _colorTiempo.withValues(alpha: 0.88),
                            height: 1.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!evento.posicionamientoVencido)
                  GestureDetector(
                    onTap: cancelando ? null : () => onCancelar(evento),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(
                          color: const Color(0xFFDC2626).withValues(alpha: 0.3),
                        ),
                      ),
                      child: cancelando
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFDC2626)),
                              ),
                            )
                          : Text(
                              'Despublicar',
                              style: GoogleFonts.baloo2(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFFDC2626),
                              ),
                            ),
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

// ─── Card: evento sin posición ───────────────────────────────────────────────

class _CardSinPosicion extends StatelessWidget {
  final _EventoPos evento;
  final int credRecomendados;
  final int credTop;
  final int credTopUltra;
  final Set<String> posicionando;
  final Set<String> cancelando;
  final bool resaltar;
  final void Function(_EventoPos, String) onPositionar;
  final void Function(_EventoPos) onCancelar;

  const _CardSinPosicion({
    required this.evento,
    required this.credRecomendados,
    required this.credTop,
    required this.credTopUltra,
    required this.posicionando,
    required this.cancelando,
    this.resaltar = false,
    required this.onPositionar,
    required this.onCancelar,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return _CardConResaltado(
      resaltar: resaltar,
      borderColor: ColoresLocales.acentoVioleta.withOpacity(0.15),
      shadowColor: ColoresLocales.acentoVioleta.withOpacity(0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cuerpo ───────────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FlyerThumb(url: evento.urlFlyer),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        evento.titulo,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.baloo2(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: ColoresLocales.textoOnFondoClaro,
                          height: 1.2,
                        ),
                      ),
                      SizedBox(height: 6),
                      if (evento.fechaInicio != null)
                        _InfoRow(
                          icono: CupertinoIcons.calendar,
                          texto: _fmtFecha(evento.fechaInicio),
                        ),
                      if (evento.fechaFin != null)
                        _InfoRow(
                          icono: CupertinoIcons.calendar_badge_minus,
                          texto: 'Hasta el ${_fmtFecha(evento.fechaFin)}',
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Divider ───────────────────────────────────────────────────────
          Divider(height: 1, thickness: 1, color: ColoresLocales.separador),

          // ── Botones de acción ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              children: [
                _BotonPositionar(
                  icono: CupertinoIcons.hand_thumbsup_fill,
                  label: 'Rec. Fernecito',
                  credLabel: '−1',
                  credIcono: CupertinoIcons.hand_thumbsup_fill,
                  color: ColoresLocales.jerarquiaRecomendado,
                  habilitado: credRecomendados > 0,
                  cargando: posicionando.contains(evento.idEvento),
                  onTap: () => onPositionar(evento, 'recomendado_fernecito'),
                ),
                const SizedBox(height: 7),
                _BotonPositionar(
                  icono: CupertinoIcons.star_fill,
                  label: 'Top Cartelera',
                  credLabel: '−1',
                  credIcono: CupertinoIcons.star_fill,
                  color: ColoresLocales.jerarquiaTop,
                  habilitado: credTop > 0,
                  cargando: posicionando.contains(evento.idEvento),
                  onTap: () => onPositionar(evento, 'top'),
                ),
                const SizedBox(height: 7),
                _BotonPositionar(
                  icono: CupertinoIcons.rosette,
                  label: 'Top Ultra',
                  credLabel: '−1',
                  credIcono: CupertinoIcons.rosette,
                  color: ColoresLocales.jerarquiaUltra,
                  habilitado: credTopUltra > 0,
                  cargando: posicionando.contains(evento.idEvento),
                  onTap: () => onPositionar(evento, 'top_ultra'),
                ),
                const SizedBox(height: 10),
                // ── Despublicar ───────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: cancelando.contains(evento.idEvento)
                        ? null
                        : () => onCancelar(evento),
                    icon: cancelando.contains(evento.idEvento)
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFDC2626)),
                            ),
                          )
                        : const Icon(CupertinoIcons.eye_slash_fill, size: 15, color: Color(0xFFDC2626)),
                    label: Text(
                      'Despublicar evento',
                      style: GoogleFonts.baloo2(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: const Color(0xFFDC2626),
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      backgroundColor: const Color(0xFFDC2626).withOpacity(0.06),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                        side: BorderSide(
                          color: const Color(0xFFDC2626).withOpacity(0.3),
                        ),
                      ),
                      minimumSize: const Size.fromHeight(38),
                    ),
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

// ─── Botón de posicionar ──────────────────────────────────────────────────────

class _BotonPositionar extends StatelessWidget {
  final IconData icono;
  final String label;
  final String credLabel;
  final IconData credIcono;
  final Color color;
  final bool habilitado;
  final bool cargando;
  final VoidCallback onTap;

  const _BotonPositionar({
    required this.icono,
    required this.label,
    required this.credLabel,
    required this.credIcono,
    required this.color,
    required this.habilitado,
    required this.cargando,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final effectiveColor = habilitado ? color : Colors.grey.shade400;

    return GestureDetector(
      onTap: habilitado && !cargando ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: habilitado
              ? LinearGradient(
                  colors: [effectiveColor, effectiveColor.withOpacity(0.75)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: habilitado ? null : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(50),
          boxShadow: habilitado
              ? [
                  BoxShadow(
                    color: effectiveColor.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icono,
              size: 14,
              color: habilitado ? Colors.white : Colors.grey,
            ),
            const SizedBox(width: 7),
            cargando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    'Posicionar en $label',
                    style: GoogleFonts.baloo2(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: habilitado ? Colors.white : Colors.grey,
                    ),
                  ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: habilitado
                    ? Colors.white.withOpacity(0.2)
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(50),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    credLabel,
                    style: GoogleFonts.baloo2(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: habilitado ? Colors.white : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    credIcono,
                    size: 11,
                    color: habilitado ? Colors.white : Colors.grey,
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

// ─── Flyer thumbnail ──────────────────────────────────────────────────────────

class _FlyerThumb extends StatelessWidget {
  final String url;
  const _FlyerThumb({required this.url});

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: url.isNotEmpty
          ? Image.network(
              url,
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _placeholder(),
            )
          : _placeholder(),
    );
  }

  Widget _placeholder() => Container(
    width: 72,
    height: 72,
    decoration: BoxDecoration(
      color: ColoresLocales.acentoVioleta.withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(
      CupertinoIcons.photo,
      color: ColoresLocales.acentoVioleta,
      size: 28,
    ),
  );
}

// ─── Info row ─────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icono;
  final String texto;
  const _InfoRow({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(
            icono,
            size: 11,
            color: ColoresLocales.textoSecundarioOnFondoClaro,
          ),
          SizedBox(width: 4),
          Text(
            texto,
            style: GoogleFonts.baloo2(
              fontSize: 11,
              color: ColoresLocales.textoSecundarioOnFondoClaro,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String subtitulo;
  const _EmptyState({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return ListView(
      physics: AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: 340,
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icono,
                    size: 56,
                    color: ColoresLocales.acentoVioleta.withOpacity(0.35),
                  ),
                  SizedBox(height: 16),
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
                  Text(
                    subtitulo,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.baloo2(
                      fontSize: 13,
                      color: ColoresLocales.textoSecundarioOnFondoClaro,
                      height: 1.5,
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
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _fmtFecha(DateTime? d) {
  if (d == null) return '—';
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';
}
