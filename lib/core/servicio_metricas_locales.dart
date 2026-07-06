library;

import 'package:flutter/cupertino.dart';

import '../models/actividad_metrica.dart';
import '../models/datos_impresiones.dart';
import 'constants.dart';
import 'supabase_client.dart';

class ServicioMetricasLocales {
  static final ServicioMetricasLocales _instancia = ServicioMetricasLocales._interno();
  factory ServicioMetricasLocales() => _instancia;
  ServicioMetricasLocales._interno();

  String? get _uid => ServicioSupabase().usuarioActual?.id;

  DateTime? _parseUtc(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw.toUtc();
    return DateTime.tryParse(raw.toString())?.toUtc();
  }

  Future<List<ActorMetricaOpcion>> cargarActoresFiltro() async {
    final uid = _uid;
    if (uid == null) return const [ActorMetricaOpcion.todos];

    final opciones = <ActorMetricaOpcion>[ActorMetricaOpcion.todos];

    try {
      final local = await ServicioSupabase()
          .cliente
          .from('perfiles_locales')
          .select('local_username, nombre_local')
          .eq('id', uid)
          .maybeSingle();
      final nombreLocal = (local?['nombre_local'] as String?)?.trim();
      final usernameLocal = (local?['local_username'] as String?)?.trim();
      final etiquetaLocal = (nombreLocal != null && nombreLocal.isNotEmpty)
          ? '$nombreLocal (mi cuenta)'
          : (usernameLocal != null && usernameLocal.isNotEmpty
              ? '@$usernameLocal (mi cuenta)'
              : 'Mi cuenta (local)');
      opciones.add(
        ActorMetricaOpcion(id: uid, etiqueta: etiquetaLocal, esLocal: true),
      );
    } catch (_) {
      opciones.add(
        ActorMetricaOpcion(id: uid, etiqueta: 'Mi cuenta (local)', esLocal: true),
      );
    }

    try {
      final filas = await ServicioSupabase()
          .cliente
          .from('local_staff')
          .select('id_staff, activo')
          .eq('id_local', uid)
          .order('fecha_creacion', ascending: false);

      final rows = (filas as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) return opciones;

      final ids = rows
          .map((r) => r['id_staff']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      final activoPorId = {
        for (final r in rows)
          r['id_staff']?.toString() ?? '': r['activo'] == true,
      };

      final nombres = await _nombresActores(ids);

      for (final id in ids) {
        final nombre = nombres[id] ?? 'Staff';
        final activo = activoPorId[id] ?? true;
        opciones.add(
          ActorMetricaOpcion(
            id: id,
            etiqueta: activo ? nombre : '$nombre · pausado',
            activo: activo,
          ),
        );
      }
    } catch (e) {
      debugPrint('⚠️ cargarActoresFiltro métricas: $e');
    }

    return opciones;
  }

  Future<Map<String, String>> _nombresActores(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final map = <String, String>{};

    try {
      final ps = await ServicioSupabase()
          .cliente
          .from('perfiles_staff')
          .select('id, username, nombre')
          .inFilter('id', ids);
      for (final p in (ps as List).cast<Map<String, dynamic>>()) {
        final id = p['id']?.toString() ?? '';
        if (id.isNotEmpty) map[id] = _displayDesdePerfil(p);
      }
    } catch (_) {}

    final faltan = ids.where((id) => !map.containsKey(id)).toList();
    if (faltan.isNotEmpty) {
      try {
        final pu = await ServicioSupabase()
            .cliente
            .from('perfiles_usuarios')
            .select('id, username, nombre')
            .inFilter('id', faltan);
        for (final p in (pu as List).cast<Map<String, dynamic>>()) {
          final id = p['id']?.toString() ?? '';
          if (id.isNotEmpty) map[id] = _displayDesdePerfil(p);
        }
      } catch (_) {}
    }
    return map;
  }

  Future<List<ActividadMetricaItem>> cargarActividad() async {
    final uid = _uid;
    if (uid == null) return const [];

    try {
      final sb = ServicioSupabase().cliente;
      final results = await Future.wait([
        sb
            .from('eventos')
            .select(
              'id_evento, titulo_evento, estado_publicacion, fecha_subida, fecha_fin, fecha_borrado',
            )
            .eq('id_local', uid)
            .inFilter('estado_publicacion', ['publicado', 'finalizado', 'cancelado']),
        sb
            .from('tokens_asistencia')
            .select(
              'id_token, estado_token, codigo_puerta, fecha_creacion, fecha_respuesta, '
              'fecha_canje, fecha_expiracion, id_invitacion_rrpp, id_rrpp, '
              'respondido_por, canjeado_por, '
              'eventos!inner(titulo_evento, id_local)',
            )
            .eq('eventos.id_local', uid)
            .inFilter('estado_token', ['aceptada', 'canjeada', 'rechazada', 'expirada'])
            .order('fecha_creacion', ascending: false)
            .limit(400),
        sb
            .from('tokens_promociones')
            .select(
              'id_token, estado_token, token_codigo, fecha_creacion, fecha_canje, '
              'fecha_expiracion, canjeado_por, '
              'promociones!inner(titulo_promocion, id_local, eventos(titulo_evento))',
            )
            .eq('promociones.id_local', uid)
            .inFilter('estado_token', ['canjeado', 'expirado', 'cancelado'])
            .order('fecha_creacion', ascending: false)
            .limit(400),
      ]);

      final items = <ActividadMetricaItem>[];
      _agregarActividadEventos(
        (results[0] as List).cast<Map<String, dynamic>>(),
        items,
        idLocal: uid,
      );
      final tokensAsist = (results[1] as List).cast<Map<String, dynamic>>();
      final tokensPromo = (results[2] as List).cast<Map<String, dynamic>>();
      final actorIds = <String>{uid};
      for (final t in tokensAsist) {
        for (final k in ['respondido_por', 'canjeado_por', 'id_rrpp']) {
          final id = t[k]?.toString();
          if (id != null && id.isNotEmpty) actorIds.add(id);
        }
      }
      for (final t in tokensPromo) {
        final id = t['canjeado_por']?.toString();
        if (id != null && id.isNotEmpty) actorIds.add(id);
      }
      final nombresActores = await _nombresActores(actorIds.toList());
      final localRow = await ServicioSupabase()
          .cliente
          .from('perfiles_locales')
          .select('local_username, nombre_local')
          .eq('id', uid)
          .maybeSingle();
      final nombreLocal = _nombreLocalDesdeRow(localRow, uid);
      nombresActores[uid] = nombreLocal;

      _agregarActividadAsistencias(
        tokensAsist,
        items,
        idLocal: uid,
        nombresActores: nombresActores,
      );
      _agregarActividadPromos(tokensPromo, items, nombresActores: nombresActores);

      items.sort((a, b) => b.fecha.compareTo(a.fecha));
      return items;
    } catch (e, st) {
      debugPrint('⚠️ cargarActividad métricas: $e\n$st');
      rethrow;
    }
  }

  String _nombreLocalDesdeRow(Map<String, dynamic>? row, String uid) {
    final nombre = (row?['nombre_local'] as String?)?.trim();
    final username = (row?['local_username'] as String?)?.trim();
    if (nombre != null && nombre.isNotEmpty) return nombre;
    if (username != null && username.isNotEmpty) return '@$username';
    return 'Local';
  }

  void _agregarActividadEventos(
    List<Map<String, dynamic>> eventos,
    List<ActividadMetricaItem> out, {
    required String idLocal,
  }) {
    for (final e in eventos) {
      final id = e['id_evento']?.toString() ?? '';
      final titulo = (e['titulo_evento']?.toString().trim().isNotEmpty == true)
          ? e['titulo_evento'].toString().trim()
          : 'Evento';
      final estado = e['estado_publicacion']?.toString() ?? '';
      final fechaSubida = _parseUtc(e['fecha_subida']);
      final fechaFin = _parseUtc(e['fecha_fin']);
      final fechaBorrado = _parseUtc(e['fecha_borrado']);

      if (estado == 'publicado' ||
          estado == 'finalizado' ||
          estado == 'cancelado') {
        if (fechaSubida != null) {
          out.add(
            ActividadMetricaItem(
              id: 'ev_pub_$id',
              tipo: TipoActividadMetrica.evento,
              categoria: CategoriaActividadMetrica.eventoPublicado,
              fecha: fechaSubida,
              titulo: titulo,
              subtitulo: 'Se publicó en Fernecito',
              estadoLabel: 'Publicado',
              icono: CupertinoIcons.calendar_badge_plus,
              colorEstado: ColoresMetricas.publicado,
              idActor: idLocal,
            ),
          );
        }
      }

      if (estado == 'finalizado') {
        final f = fechaFin ?? fechaSubida;
        if (f != null) {
          out.add(
            ActividadMetricaItem(
              id: 'ev_fin_$id',
              tipo: TipoActividadMetrica.evento,
              categoria: CategoriaActividadMetrica.eventoFinalizado,
              fecha: f,
              titulo: titulo,
              subtitulo: 'El evento finalizó',
              estadoLabel: 'Finalizado',
              icono: CupertinoIcons.flag_fill,
              colorEstado: ColoresMetricas.finalizado,
              idActor: idLocal,
            ),
          );
        }
      }

      if (estado == 'cancelado') {
        final f = fechaBorrado ?? fechaFin ?? fechaSubida;
        if (f != null) {
          out.add(
            ActividadMetricaItem(
              id: 'ev_can_$id',
              tipo: TipoActividadMetrica.evento,
              categoria: CategoriaActividadMetrica.eventoCancelado,
              fecha: f,
              titulo: titulo,
              subtitulo: 'El evento fue cancelado',
              estadoLabel: 'Cancelado',
              icono: CupertinoIcons.xmark_circle_fill,
              colorEstado: ColoresMetricas.rechazado,
              idActor: idLocal,
            ),
          );
        }
      }
    }
  }

  String _subtituloInvitacionRrpp(
    Map<String, dynamic> t,
    Map<String, String> nombresActores,
  ) {
    final idRrpp = t['id_rrpp']?.toString();
    final actor = idRrpp != null ? nombresActores[idRrpp] : null;
    final codigo = t['codigo_puerta']?.toString().trim() ?? '';
    final base = actor != null
        ? 'Lista vía QR de $actor'
        : 'Lista vía invitación QR RRPP';
    if (codigo.isNotEmpty) return '$base · Pase $codigo';
    return base;
  }

  String _displayDesdePerfil(Map<String, dynamic> p) {
    final nombre = (p['nombre'] as String?)?.trim();
    final username = (p['username'] as String?)?.trim();
    if (nombre != null && nombre.isNotEmpty) return nombre;
    if (username != null && username.isNotEmpty) return '@$username';
    return 'Staff';
  }

  bool _esInvitacionRrpp(Map<String, dynamic> t) {
    final idInv = t['id_invitacion_rrpp'];
    return idInv != null && idInv.toString().trim().isNotEmpty;
  }

  String? _idActorLista(Map<String, dynamic> t) {
    if (_esInvitacionRrpp(t)) return t['id_rrpp']?.toString();
    return t['respondido_por']?.toString();
  }

  ActividadMetricaItem _itemAsistencia({
    required String id,
    required CategoriaActividadMetrica categoria,
    required DateTime fecha,
    required String tituloEvento,
    required String subtitulo,
    required String estadoLabel,
    required IconData icono,
    required Color colorEstado,
    String? idActor,
    String? idLocal,
    Map<String, String> nombresActores = const {},
  }) {
    final actorId = idActor?.trim();
    final tieneActor = actorId != null && actorId.isNotEmpty;
    final esListaAuto =
        categoria == CategoriaActividadMetrica.listaAceptada && !tieneActor;

    return ActividadMetricaItem(
      id: id,
      tipo: TipoActividadMetrica.asistencia,
      categoria: categoria,
      fecha: fecha,
      titulo: tituloEvento,
      subtitulo: subtitulo,
      estadoLabel: estadoLabel,
      icono: icono,
      colorEstado: colorEstado,
      idActor: tieneActor
          ? actorId
          : (esListaAuto ? idLocal : null),
      nombreActor: tieneActor ? nombresActores[actorId] : null,
      etiquetaActor: esListaAuto ? 'Autoaceptada por mi local' : null,
    );
  }

  void _agregarActividadAsistencias(
    List<Map<String, dynamic>> tokens,
    List<ActividadMetricaItem> out, {
    required String idLocal,
    Map<String, String> nombresActores = const {},
  }) {
    for (final t in tokens) {
      final id = t['id_token']?.toString() ?? '';
      final estado = t['estado_token']?.toString() ?? '';
      final codigo = t['codigo_puerta']?.toString() ?? '';
      final ev = t['eventos'];
      final tituloEvento = ev is Map
          ? (ev['titulo_evento']?.toString().trim().isNotEmpty == true
              ? ev['titulo_evento'].toString().trim()
              : 'Evento')
          : 'Evento';

      switch (estado) {
        case 'aceptada':
          final f = _parseUtc(t['fecha_respuesta']) ?? _parseUtc(t['fecha_creacion']);
          if (f == null) break;
          if (_esInvitacionRrpp(t)) {
            out.add(
              _itemAsistencia(
                id: 'as_inv_$id',
                categoria: CategoriaActividadMetrica.invitacionQr,
                fecha: f,
                tituloEvento: tituloEvento,
                subtitulo: _subtituloInvitacionRrpp(t, nombresActores),
                estadoLabel: 'Invitación QR',
                icono: CupertinoIcons.qrcode,
                colorEstado: ColoresMetricas.invitacionQr,
                idActor: _idActorLista(t),
                idLocal: idLocal,
                nombresActores: nombresActores,
              ),
            );
            break;
          }
          out.add(
            _itemAsistencia(
              id: 'as_acc_$id',
              categoria: CategoriaActividadMetrica.listaAceptada,
              fecha: f,
              tituloEvento: tituloEvento,
              subtitulo: codigo.isNotEmpty
                  ? 'Pase $codigo aceptado en lista'
                  : 'Reserva aceptada en lista',
              estadoLabel: 'Aceptada',
              icono: IconosLocales.exito,
              colorEstado: ColoresMetricas.aceptado,
              idActor: _idActorLista(t),
              idLocal: idLocal,
              nombresActores: nombresActores,
            ),
          );
        case 'canjeada':
          final fCanje = _parseUtc(t['fecha_canje']);
          if (fCanje != null) {
            out.add(
              _itemAsistencia(
                id: 'as_can_$id',
                categoria: CategoriaActividadMetrica.qrPase,
                fecha: fCanje,
                tituloEvento: tituloEvento,
                subtitulo: codigo.isNotEmpty
                    ? 'Ingreso canjeado · $codigo'
                    : 'Ingreso canjeado en puerta',
                estadoLabel: 'Canjeada',
                icono: CupertinoIcons.qrcode_viewfinder,
                colorEstado: ColoresMetricas.canje,
              idActor: t['canjeado_por']?.toString(),
              idLocal: idLocal,
              nombresActores: nombresActores,
              ),
            );
          }
          final fAcc = _parseUtc(t['fecha_respuesta']);
          if (fAcc != null) {
            if (_esInvitacionRrpp(t)) {
              out.add(
                _itemAsistencia(
                  id: 'as_inv2_$id',
                  categoria: CategoriaActividadMetrica.invitacionQr,
                  fecha: fAcc,
                  tituloEvento: tituloEvento,
                  subtitulo: _subtituloInvitacionRrpp(t, nombresActores),
                  estadoLabel: 'Invitación QR',
                  icono: CupertinoIcons.qrcode,
                  colorEstado: ColoresMetricas.invitacionQr,
                  idActor: _idActorLista(t),
                  idLocal: idLocal,
                  nombresActores: nombresActores,
                ),
              );
            } else {
              out.add(
                _itemAsistencia(
                  id: 'as_acc2_$id',
                  categoria: CategoriaActividadMetrica.listaAceptada,
                  fecha: fAcc,
                  tituloEvento: tituloEvento,
                  subtitulo: codigo.isNotEmpty
                      ? 'Pase $codigo aceptado'
                      : 'Reserva aceptada',
                  estadoLabel: 'Aceptada',
                  icono: IconosLocales.exito,
                  colorEstado: ColoresMetricas.aceptado,
                  idActor: _idActorLista(t),
                  idLocal: idLocal,
                  nombresActores: nombresActores,
                ),
              );
            }
          }
        case 'rechazada':
          final f = _parseUtc(t['fecha_respuesta']) ?? _parseUtc(t['fecha_creacion']);
          if (f == null) break;
          out.add(
            _itemAsistencia(
              id: 'as_rech_$id',
              categoria: CategoriaActividadMetrica.listaRechazada,
              fecha: f,
              tituloEvento: tituloEvento,
              subtitulo: codigo.isNotEmpty
                  ? 'Pase $codigo rechazado'
                  : 'Solicitud rechazada',
              estadoLabel: 'Rechazada',
              icono: CupertinoIcons.hand_thumbsdown_fill,
              colorEstado: ColoresMetricas.rechazado,
              idActor: _idActorLista(t),
              idLocal: idLocal,
              nombresActores: nombresActores,
            ),
          );
        case 'expirada':
          final f = _parseUtc(t['fecha_expiracion']) ?? _parseUtc(t['fecha_creacion']);
          if (f == null) break;
          out.add(
            _itemAsistencia(
              id: 'as_exp_$id',
              categoria: CategoriaActividadMetrica.listaRechazada,
              fecha: f,
              tituloEvento: tituloEvento,
              subtitulo: codigo.isNotEmpty ? 'Pase $codigo expiró' : 'Pase expirado',
              estadoLabel: 'Expirada',
              icono: CupertinoIcons.clock_fill,
              colorEstado: ColoresMetricas.finalizado,
              idLocal: idLocal,
            ),
          );
      }
    }
  }

  void _agregarActividadPromos(
    List<Map<String, dynamic>> tokens,
    List<ActividadMetricaItem> out, {
    Map<String, String> nombresActores = const {},
  }) {
    for (final t in tokens) {
      final id = t['id_token']?.toString() ?? '';
      final estado = t['estado_token']?.toString() ?? '';
      final codigo = t['token_codigo']?.toString() ?? '';
      final promo = t['promociones'];
      String tituloPromo = 'Promoción';
      String? tituloEvento;
      if (promo is Map) {
        final tp = promo['titulo_promocion']?.toString().trim();
        if (tp != null && tp.isNotEmpty) tituloPromo = tp;
        final ev = promo['eventos'];
        if (ev is Map) {
          tituloEvento = ev['titulo_evento']?.toString().trim();
        }
      }

      switch (estado) {
        case 'canjeado':
          final f = _parseUtc(t['fecha_canje']);
          if (f == null) break;
          final actorId = t['canjeado_por']?.toString();
          out.add(
            ActividadMetricaItem(
              id: 'pr_can_$id',
              tipo: TipoActividadMetrica.promo,
              categoria: CategoriaActividadMetrica.qrPromo,
              fecha: f,
              titulo: tituloPromo,
              subtitulo: [
                if (tituloEvento != null && tituloEvento.isNotEmpty) tituloEvento,
                if (codigo.isNotEmpty) 'Token $codigo',
                'Promo canjeada',
              ].join(' · '),
              estadoLabel: 'Canjeada',
              icono: CupertinoIcons.gift_fill,
              colorEstado: ColoresMetricas.canje,
              idActor: actorId,
              nombreActor: actorId != null ? nombresActores[actorId] : null,
            ),
          );
        case 'expirado':
          final f = _parseUtc(t['fecha_expiracion']) ?? _parseUtc(t['fecha_creacion']);
          if (f == null) break;
          out.add(
            ActividadMetricaItem(
              id: 'pr_exp_$id',
              tipo: TipoActividadMetrica.promo,
              categoria: CategoriaActividadMetrica.qrPromo,
              fecha: f,
              titulo: tituloPromo,
              subtitulo: tituloEvento ?? 'Promo expirada sin canje',
              estadoLabel: 'Expirada',
              icono: CupertinoIcons.hourglass_bottomhalf_fill,
              colorEstado: ColoresMetricas.finalizado,
            ),
          );
        case 'cancelado':
          final f = _parseUtc(t['fecha_expiracion']) ?? _parseUtc(t['fecha_creacion']);
          if (f == null) break;
          out.add(
            ActividadMetricaItem(
              id: 'pr_canc_$id',
              tipo: TipoActividadMetrica.promo,
              categoria: CategoriaActividadMetrica.qrPromo,
              fecha: f,
              titulo: tituloPromo,
              subtitulo: tituloEvento ?? 'Promo cancelada',
              estadoLabel: 'Cancelada',
              icono: CupertinoIcons.xmark_octagon_fill,
              colorEstado: ColoresMetricas.rechazado,
            ),
          );
      }
    }
  }

  Future<DatosRendimientoMetricas> cargarRendimiento({required int dias}) async {
    final uid = _uid;
    if (uid == null) return DatosRendimientoMetricas.vacio;

    final desde = DateTime.now().toUtc().subtract(Duration(days: dias));

    try {
      final sb = ServicioSupabase().cliente;
      final results = await Future.wait([
        sb
            .from('eventos')
            .select(
              'id_evento, titulo_evento, estado_publicacion, metric_visitas, metric_reservas_aceptadas, metric_canjeos',
            )
            .eq('id_local', uid)
            .inFilter('estado_publicacion', ['publicado', 'finalizado', 'cancelado']),
        sb
            .from('tokens_asistencia')
            .select(
              'estado_token, fecha_respuesta, fecha_canje, eventos!inner(id_evento, titulo_evento, id_local)',
            )
            .eq('eventos.id_local', uid)
            .inFilter('estado_token', ['aceptada', 'canjeada'])
            .gte('fecha_creacion', desde.toIso8601String()),
        sb
            .from('tokens_promociones')
            .select(
              'estado_token, fecha_canje, promociones!inner(id_local, id_evento, eventos(titulo_evento))',
            )
            .eq('promociones.id_local', uid)
            .eq('estado_token', 'canjeado')
            .gte('fecha_creacion', desde.toIso8601String()),
      ]);

      final eventos = (results[0] as List).cast<Map<String, dynamic>>();
      final asistencias = (results[1] as List).cast<Map<String, dynamic>>();
      final promos = (results[2] as List).cast<Map<String, dynamic>>();

      var totalVisitas = 0;
      var totalReservasMetric = 0;
      var totalCanjesMetric = 0;
      var eventosActivos = 0;
      final canjesPorEvento = <String, _TopEventoAcum>{};

      for (final e in eventos) {
        totalVisitas += _asInt(e['metric_visitas']);
        totalReservasMetric += _asInt(e['metric_reservas_aceptadas']);
        totalCanjesMetric += _asInt(e['metric_canjeos']);
        if (e['estado_publicacion']?.toString() == 'publicado') {
          eventosActivos++;
        }
        final idEv = e['id_evento']?.toString() ?? '';
        final titulo = e['titulo_evento']?.toString().trim() ?? 'Evento';
        final canjes = _asInt(e['metric_canjeos']);
        if (idEv.isNotEmpty && canjes > 0) {
          canjesPorEvento[idEv] = _TopEventoAcum(titulo: titulo, canjes: canjes);
        }
      }

      final canjesEntradasFechas = <DateTime>[];
      final reservasFechas = <DateTime>[];
      final promosFechas = <DateTime>[];

      for (final t in asistencias) {
        final ev = t['eventos'];
        final idEv = ev is Map ? ev['id_evento']?.toString() ?? '' : '';
        final tituloEv = ev is Map
            ? (ev['titulo_evento']?.toString().trim().isNotEmpty == true
                ? ev['titulo_evento'].toString().trim()
                : 'Evento')
            : 'Evento';

        if (t['estado_token']?.toString() == 'canjeada') {
          final f = _parseUtc(t['fecha_canje']);
          if (f != null && !f.isBefore(desde)) {
            canjesEntradasFechas.add(f);
            if (idEv.isNotEmpty) {
              final prev = canjesPorEvento[idEv];
              canjesPorEvento[idEv] = _TopEventoAcum(
                titulo: tituloEv,
                canjes: (prev?.canjes ?? 0) + 1,
              );
            }
          }
        }

        final fRes = _parseUtc(t['fecha_respuesta']);
        if (fRes != null && !fRes.isBefore(desde)) {
          reservasFechas.add(fRes);
        }
      }

      for (final t in promos) {
        final f = _parseUtc(t['fecha_canje']);
        if (f != null && !f.isBefore(desde)) {
          promosFechas.add(f);
        }
      }

      final topEventos = canjesPorEvento.values.toList()
        ..sort((a, b) => b.canjes.compareTo(a.canjes));

      final agrupar = dias >= 60 ? _agruparPorSemana : _agruparPorDia;

      final reservasSerie = agrupar(reservasFechas, dias);
      final ingresosSerie = agrupar(canjesEntradasFechas, dias);
      final promosSerie = agrupar(promosFechas, dias);
      final traficoSerie = _sumarSeries([reservasSerie, ingresosSerie, promosSerie]);

      final totalReservas = reservasFechas.length;
      final totalIngresos = canjesEntradasFechas.length;
      final totalPromos = promosFechas.length;

      return DatosRendimientoMetricas(
        traficoPorDia: traficoSerie,
        canjesEntradasPorDia: ingresosSerie,
        reservasPorDia: reservasSerie,
        promosCanjeadasPorDia: promosSerie,
        topEventosCanjes: topEventos
            .take(5)
            .map((e) => PuntoRendimiento(etiqueta: e.titulo, valor: e.canjes.toDouble()))
            .toList(),
        totalTrafico: totalReservas + totalIngresos + totalPromos,
        totalCanjesEntradas: totalIngresos > 0 ? totalIngresos : totalCanjesMetric,
        totalReservas: totalReservas > 0 ? totalReservas : totalReservasMetric,
        totalPromosCanjeadas: totalPromos,
        totalVisitas: totalVisitas,
        eventosActivos: eventosActivos,
      );
    } catch (e, st) {
      debugPrint('⚠️ cargarRendimiento métricas: $e\n$st');
      rethrow;
    }
  }

  List<PuntoRendimiento> _agruparPorDia(List<DateTime> fechas, int dias) {
    final hoy = DateTime.now().toUtc();
    final buckets = <DateTime, int>{};
    for (var i = dias - 1; i >= 0; i--) {
      final d = DateTime.utc(hoy.year, hoy.month, hoy.day).subtract(Duration(days: i));
      buckets[d] = 0;
    }
    for (final f in fechas) {
      final key = DateTime.utc(f.year, f.month, f.day);
      if (buckets.containsKey(key)) {
        buckets[key] = (buckets[key] ?? 0) + 1;
      }
    }
    return buckets.entries
        .map(
          (e) => PuntoRendimiento(
            etiqueta: '${e.key.day}/${e.key.month}',
            valor: e.value.toDouble(),
          ),
        )
        .toList();
  }

  /// Agrupa en bloques de 7 días (mejor legibilidad en rangos de 90 días).
  List<PuntoRendimiento> _agruparPorSemana(List<DateTime> fechas, int dias) {
    final hoy = DateTime.utc(
      DateTime.now().toUtc().year,
      DateTime.now().toUtc().month,
      DateTime.now().toUtc().day,
    );
    final inicio = hoy.subtract(Duration(days: dias - 1));

    final bucketStarts = <DateTime>[];
    var cursor = inicio;
    while (!cursor.isAfter(hoy)) {
      bucketStarts.add(cursor);
      final next = cursor.add(const Duration(days: 7));
      if (next.isAfter(hoy)) break;
      cursor = next;
    }

    final buckets = {for (final b in bucketStarts) b: 0};

    for (final f in fechas) {
      final day = DateTime.utc(f.year, f.month, f.day);
      if (day.isBefore(inicio) || day.isAfter(hoy)) continue;
      for (final start in bucketStarts) {
        final end = start.add(const Duration(days: 6));
        if (!day.isBefore(start) && !day.isAfter(end)) {
          buckets[start] = (buckets[start] ?? 0) + 1;
          break;
        }
      }
    }

    return bucketStarts
        .map(
          (start) => PuntoRendimiento(
            etiqueta: '${start.day}/${start.month}',
            valor: (buckets[start] ?? 0).toDouble(),
          ),
        )
        .toList();
  }

  List<PuntoRendimiento> _sumarSeries(List<List<PuntoRendimiento>> series) {
    if (series.isEmpty) return const [];
    final base = series.firstWhere((s) => s.isNotEmpty, orElse: () => const []);
    if (base.isEmpty) return const [];
    return List.generate(base.length, (i) {
      var sum = 0.0;
      for (final s in series) {
        if (i < s.length) sum += s[i].valor;
      }
      return PuntoRendimiento(etiqueta: base[i].etiqueta, valor: sum);
    });
  }

  int _asInt(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  static const _sentinelEvento = '00000000-0000-0000-0000-000000000000';

  Future<DatosImpresionesMetricas> cargarImpresiones({
    required int dias,
    AlcanceFiltroMetricas filtro = const AlcanceFiltroMetricas(),
  }) async {
    final uid = _uid;
    if (uid == null) return DatosImpresionesMetricas.vacio;

    final hoy = DateTime.now();
    final desde = DateTime.utc(hoy.year, hoy.month, hoy.day)
        .subtract(Duration(days: dias - 1));
    final desdeStr =
        '${desde.year.toString().padLeft(4, '0')}-${desde.month.toString().padLeft(2, '0')}-${desde.day.toString().padLeft(2, '0')}';

    try {
      final sb = ServicioSupabase().cliente;
      final rows = (await sb
              .from('impresiones_diarias')
              .select('fecha, seccion, id_evento, conteo')
              .eq('id_local', uid)
              .gte('fecha', desdeStr)
          as List)
          .cast<Map<String, dynamic>>();

      final filtradas = rows.where((r) {
        final seccion = r['seccion']?.toString() ?? '';
        final idEv = r['id_evento']?.toString() ?? '';
        switch (filtro.tipo) {
          case AlcanceFiltroTipo.perfil:
            return seccion == 'perfil_local';
          case AlcanceFiltroTipo.evento:
            return idEv == filtro.idEvento && idEv != _sentinelEvento;
          case AlcanceFiltroTipo.todas:
            return true;
        }
      }).toList();

      final buckets = <DateTime, int>{};
      for (var i = dias - 1; i >= 0; i--) {
        final d = DateTime.utc(hoy.year, hoy.month, hoy.day)
            .subtract(Duration(days: i));
        buckets[d] = 0;
      }

      var totalPerfil = 0;
      var totalClicks = 0;
      final porEvento = <String, _EventoImpAcum>{};

      for (final r in filtradas) {
        final conteo = _asInt(r['conteo']);
        final seccion = r['seccion']?.toString() ?? '';
        final idEv = r['id_evento']?.toString() ?? '';
        final fechaRaw = r['fecha'];
        DateTime? f;
        if (fechaRaw is DateTime) {
          f = fechaRaw.toUtc();
        } else {
          f = DateTime.tryParse(fechaRaw?.toString() ?? '')?.toUtc();
        }
        if (f != null) {
          final key = DateTime.utc(f.year, f.month, f.day);
          if (buckets.containsKey(key)) {
            buckets[key] = (buckets[key] ?? 0) + conteo;
          }
        }
        if (seccion == 'perfil_local') totalPerfil += conteo;
        if (seccion == 'click_evento') totalClicks += conteo;
        if (idEv.isNotEmpty && idEv != _sentinelEvento) {
          final prev = porEvento[idEv];
          porEvento[idEv] = _EventoImpAcum(
            titulo: prev?.titulo ?? 'Evento',
            conteo: (prev?.conteo ?? 0) + conteo,
          );
        }
      }

      if (porEvento.isNotEmpty) {
        try {
          final ids = porEvento.keys.toList();
          final titulosRows = await sb
              .from('eventos')
              .select('id_evento, titulo_evento')
              .eq('id_local', uid)
              .inFilter('id_evento', ids);
          for (final row in (titulosRows as List).cast<Map<String, dynamic>>()) {
            final id = row['id_evento']?.toString() ?? '';
            if (id.isEmpty || !porEvento.containsKey(id)) continue;
            final titulo = row['titulo_evento']?.toString().trim();
            if (titulo != null && titulo.isNotEmpty) {
              final prev = porEvento[id]!;
              porEvento[id] = _EventoImpAcum(
                titulo: titulo,
                conteo: prev.conteo,
              );
            }
          }
        } catch (e) {
          debugPrint('⚠️ cargarImpresiones titulos eventos: $e');
        }
      }

      final total =
          filtradas.fold<int>(0, (s, r) => s + _asInt(r['conteo']));

      final eventos = porEvento.entries
          .map(
            (e) => EventoImpresionResumen(
              idEvento: e.key,
              titulo: e.value.titulo,
              conteo: e.value.conteo,
            ),
          )
          .toList()
        ..sort((a, b) => b.conteo.compareTo(a.conteo));

      final serie = buckets.entries
          .map(
            (e) => PuntoRendimiento(
              etiqueta: '${e.key.day}/${e.key.month}',
              valor: e.value.toDouble(),
            ),
          )
          .toList();

      return DatosImpresionesMetricas(
        seriePorDia: serie,
        totalImpresiones: total,
        totalPerfil: totalPerfil,
        totalClicks: totalClicks,
        eventos: eventos,
      );
    } catch (e, st) {
      debugPrint('⚠️ cargarImpresiones: $e\n$st');
      rethrow;
    }
  }
}

class _EventoImpAcum {
  const _EventoImpAcum({required this.titulo, required this.conteo});
  final String titulo;
  final int conteo;
}

class _TopEventoAcum {
  const _TopEventoAcum({required this.titulo, required this.canjes});
  final String titulo;
  final int canjes;
}

/// Colores semánticos del feed de actividad.
class ColoresMetricas {
  static const publicado = Color(0xFF7C3AED);
  static const aceptado = Color(0xFF16A34A);
  static const invitacionQr = Color(0xFFDB2777);
  static const canje = Color(0xFF0891B2);
  static const finalizado = Color(0xFF64748B);
  static const rechazado = Color(0xFFDC2626);
}
