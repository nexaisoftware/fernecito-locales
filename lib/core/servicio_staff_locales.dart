library;

import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../models/actividad_staff.dart';
import '../models/empleado_staff.dart';
import '../models/perfil_staff.dart';
import '../models/vinculo_staff_local.dart';
import 'constants.dart';
import 'servicio_edges_eventos.dart';
import 'supabase_client.dart';

class ServicioStaffLocales {
  static final ServicioStaffLocales _instancia = ServicioStaffLocales._interno();
  factory ServicioStaffLocales() => _instancia;
  ServicioStaffLocales._interno();

  String? get _uid => ServicioSupabase().usuarioActual?.id;

  // ── Dueño del local ────────────────────────────────────────────────────────

  Future<String?> cargarUsernameLocal() async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final row = await ServicioSupabase()
          .cliente
          .from('perfiles_locales')
          .select('local_username')
          .eq('id', uid)
          .maybeSingle();
      return (row?['local_username'] as String?)?.trim();
    } catch (e) {
      debugPrint('⚠️ cargarUsernameLocal staff: $e');
      rethrow;
    }
  }

  Future<List<EmpleadoStaff>> listarEmpleados() async {
    final uid = _uid;
    if (uid == null) return const [];

    try {
      // 1) Filas crudas de local_staff (sin embed: no hay FK formal hacia
      //    perfiles_staff porque un id_staff puede vivir en perfiles_staff
      //    o en perfiles_usuarios — opción B del proyecto).
      final filas = await ServicioSupabase().cliente.from('local_staff').select(
            'id_staff, activo, fecha_creacion, '
            'habilitado_qr_promos, habilitado_qr_pases, habilitado_aceptar_listas, habilitado_ver_lista_aceptados, '
            'habilitado_qr_invitacion, qr_invitacion_pasar_cupo',
          ).eq('id_local', uid).order('fecha_creacion', ascending: false);

      final rows = (filas as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) return const [];

      // 2) Recolectar uids para hacer 2 queries batch a los perfiles.
      final ids = rows
          .map((r) => r['id_staff']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();

      // 3) Map id → perfil. Prioridad: perfiles_staff > perfiles_usuarios.
      final Map<String, Map<String, dynamic>> perfilStaffPorId = {};
      final Map<String, Map<String, dynamic>> perfilUsuarioPorId = {};

      try {
        final ps = await ServicioSupabase()
            .cliente
            .from('perfiles_staff')
            .select('id, username, nombre, foto_perfil_url')
            .inFilter('id', ids);
        for (final p in (ps as List).cast<Map<String, dynamic>>()) {
          final id = p['id']?.toString() ?? '';
          if (id.isNotEmpty) perfilStaffPorId[id] = p;
        }
      } catch (e) {
        debugPrint('⚠️ batch perfiles_staff: $e');
      }

      // RLS bloquea perfiles_usuarios para el local en general — esto puede
      // devolver vacío y está OK: solo se usa como fallback.
      try {
        final pu = await ServicioSupabase()
            .cliente
            .from('perfiles_usuarios')
            .select('id, username, nombre, foto_perfil_url')
            .inFilter('id', ids);
        for (final p in (pu as List).cast<Map<String, dynamic>>()) {
          final id = p['id']?.toString() ?? '';
          if (id.isNotEmpty) perfilUsuarioPorId[id] = p;
        }
      } catch (e) {
        debugPrint('⚠️ batch perfiles_usuarios (no crítico): $e');
      }

      // 4) Inyectar el perfil resuelto al raw antes de fromMap.
      return rows.map((r) {
        final id = r['id_staff']?.toString() ?? '';
        final raw = Map<String, dynamic>.from(r);
        final ps = perfilStaffPorId[id];
        final pu = perfilUsuarioPorId[id];
        if (ps != null) raw['perfiles_staff'] = ps;
        if (pu != null) raw['perfiles_usuarios'] = pu;
        return EmpleadoStaff.fromMap(raw);
      }).where((e) => e.idStaff.isNotEmpty).toList();
    } catch (e, st) {
      debugPrint('⚠️ listarEmpleados staff: $e\n$st');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> generarClaveVinculacion() async {
    return ServicioEdgesEventos().gestionarStaff(accion: 'generar_clave_vinculacion');
  }

  Future<void> toggleActivo({
    required String idStaff,
    required bool activo,
  }) async {
    await ServicioEdgesEventos().gestionarStaff(
      accion: 'toggle_activo',
      idStaff: idStaff,
      activo: activo,
    );
  }

  Future<void> eliminarEmpleado({required String idStaff}) async {
    await ServicioEdgesEventos().gestionarStaff(
      accion: 'eliminar',
      idStaff: idStaff,
    );
  }

  Future<void> actualizarPermisos({
    required String idStaff,
    bool? habilitadoQrPromos,
    bool? habilitadoQrPases,
    bool? habilitadoAceptarListas,
    bool? habilitadoVerListaAceptados,
    bool? habilitadoQrInvitacion,
    bool? qrInvitacionPasarCupo,
  }) async {
    await ServicioEdgesEventos().gestionarStaff(
      accion: 'actualizar_permisos',
      idStaff: idStaff,
      habilitadoQrPromos: habilitadoQrPromos,
      habilitadoQrPases: habilitadoQrPases,
      habilitadoAceptarListas: habilitadoAceptarListas,
      habilitadoVerListaAceptados: habilitadoVerListaAceptados,
      habilitadoQrInvitacion: habilitadoQrInvitacion,
      qrInvitacionPasarCupo: qrInvitacionPasarCupo,
    );
  }

  /// Staff sale por su cuenta de un local (sin permiso del local owner).
  Future<void> desvincularDelLocal({required String idLocal}) async {
    await ServicioEdgesEventos().gestionarStaff(
      accion: 'desvincular_solo',
      idLocal: idLocal,
    );
  }

  // ── Staff (empleado) ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> vincularStaff({
    required String localUsername,
    required String clave,
  }) async {
    return ServicioEdgesEventos().gestionarStaff(
      accion: 'vincular',
      localUsername: localUsername,
      claveVinculacion: clave,
    );
  }

  Future<PerfilStaff?> cargarMiPerfilStaff({bool sincronizarFoto = true}) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final row = await ServicioSupabase()
          .cliente
          .from('perfiles_staff')
          .select(
            'id, username, nombre, dni, edad, fecha_nacimiento, foto_perfil_url, perfil_completo',
          )
          .eq('id', uid)
          .maybeSingle();
      if (row == null) return null;

      final staffMap = Map<String, dynamic>.from(row as Map);
      final pu = await cargarPerfilUsuarioPropio();

      final fotoStaff = (staffMap['foto_perfil_url'] as String?)?.trim();
      final fotoUsuario = pu?['foto_perfil_url']?.toString().trim();
      if ((fotoStaff == null || fotoStaff.isEmpty) &&
          fotoUsuario != null &&
          fotoUsuario.isNotEmpty) {
        staffMap['foto_perfil_url'] = fotoUsuario;
        if (sincronizarFoto) {
          unawaited(_persistirFotoStaff(fotoUsuario));
        }
      }

      final usernameStaff = (staffMap['username'] as String?)?.trim();
      final usernameUsuario = pu?['username']?.toString().trim();
      if ((usernameStaff == null || usernameStaff.isEmpty) &&
          usernameUsuario != null &&
          usernameUsuario.isNotEmpty) {
        staffMap['username'] = usernameUsuario;
      }

      final nombreStaff = (staffMap['nombre'] as String?)?.trim();
      final nombreUsuario = pu?['nombre']?.toString().trim();
      if ((nombreStaff == null || nombreStaff.isEmpty) &&
          nombreUsuario != null &&
          nombreUsuario.isNotEmpty) {
        staffMap['nombre'] = nombreUsuario;
      }

      return PerfilStaff.fromMap(staffMap);
    } catch (e) {
      debugPrint('⚠️ cargarMiPerfilStaff: $e');
      rethrow;
    }
  }

  /// Convierte path de Storage (`avatars/...`) o URL absoluta en URL pública.
  String? resolverUrlFotoPerfil(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final path = raw.trim();
    if (path.startsWith('http')) return path;
    return ServicioSupabase()
        .cliente
        .storage
        .from('avatars')
        .getPublicUrl(path);
  }

  Future<void> _persistirFotoStaff(String fotoPath) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await ServicioSupabase().cliente.from('perfiles_staff').update({
        'foto_perfil_url': fotoPath,
        'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid);
    } catch (e) {
      debugPrint('⚠️ backfill foto staff: $e');
    }
  }

  Future<bool> perfilStaffCompleto() async {
    final p = await cargarMiPerfilStaff();
    return p?.estaCompleto ?? false;
  }

  /// Si la cuenta auth tiene perfil_usuarios, intentamos leer username, nombre
  /// y foto_perfil_url para sugerirlos como defaults al crear perfil_staff.
  /// Devuelve null si no existe perfil_usuarios o RLS bloquea (no es bloqueante).
  Future<Map<String, dynamic>?> cargarPerfilUsuarioPropio() async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final row = await ServicioSupabase()
          .cliente
          .from('perfiles_usuarios')
          .select('id, username, nombre, edad, foto_perfil_url')
          .eq('id', uid)
          .maybeSingle();
      return row == null ? null : Map<String, dynamic>.from(row as Map);
    } catch (e) {
      debugPrint('⚠️ cargarPerfilUsuarioPropio: $e');
      return null;
    }
  }

  Future<void> guardarPerfilStaff({
    required String username,
    required String nombre,
    String? dni,
    int? edad,
    DateTime? fechaNacimiento,
    String? fotoPerfilUrl,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Sin sesión');

    final payload = <String, dynamic>{
      'id': uid,
      'username': username.trim().toLowerCase(),
      'nombre': nombre.trim(),
      if (dni != null && dni.trim().isNotEmpty) 'dni': dni.trim(),
      'edad': ?edad,
      if (fechaNacimiento != null)
        'fecha_nacimiento':
            '${fechaNacimiento.year.toString().padLeft(4, '0')}-${fechaNacimiento.month.toString().padLeft(2, '0')}-${fechaNacimiento.day.toString().padLeft(2, '0')}',
      if (fotoPerfilUrl != null && fotoPerfilUrl.trim().isNotEmpty)
        'foto_perfil_url': fotoPerfilUrl.trim(),
      'perfil_completo': true,
      'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
    };

    await ServicioSupabase().cliente.from('perfiles_staff').upsert(payload);
  }

  Future<List<VinculoStaffLocal>> listarMisLocales() async {
    final uid = _uid;
    if (uid == null) return const [];

    try {
      final data = await ServicioSupabase().cliente.from('local_staff').select(
            'id_local, activo, '
            'habilitado_qr_promos, habilitado_qr_pases, habilitado_aceptar_listas, habilitado_ver_lista_aceptados, '
            'habilitado_qr_invitacion, '
            'perfiles_locales(nombre_local, local_username, foto_perfil_url, estado_cuenta)',
          ).eq('id_staff', uid).order('fecha_creacion', ascending: false);

      return (data as List)
          .cast<Map<String, dynamic>>()
          .map(VinculoStaffLocal.fromMap)
          .toList();
    } catch (e, st) {
      debugPrint('⚠️ listarMisLocales: $e\n$st');
      rethrow;
    }
  }

  Future<VinculoStaffLocal?> buscarVinculoLocal(String idLocal) async {
    final lista = await listarMisLocales();
    for (final v in lista) {
      if (v.idLocal == idLocal) return v;
    }
    return null;
  }

  Map<String, dynamic>? _perfilUsuarioDesdeRaw(Map<String, dynamic> raw) {
    final perfilRaw = raw['perfiles_usuarios'];
    if (perfilRaw is Map) return Map<String, dynamic>.from(perfilRaw);
    if (perfilRaw is List && perfilRaw.isNotEmpty) {
      final first = perfilRaw.first;
      if (first is Map) return Map<String, dynamic>.from(first);
    }
    return null;
  }

  ({String? nombre, String? username}) _usuarioDesdeRaw(Map<String, dynamic> raw) {
    final perfil = _perfilUsuarioDesdeRaw(raw);
    return (
      nombre: perfil?['nombre']?.toString().trim(),
      username: perfil?['username']?.toString().trim(),
    );
  }

  Map<String, dynamic>? _snapshotDesdeRaw(Map<String, dynamic> raw) {
    final snap = raw['snapshot_squad'];
    if (snap is Map<String, dynamic>) return snap;
    if (snap is Map) return snap.cast<String, dynamic>();
    return null;
  }

  ({String? idGrupo, int? cantidad}) _squadDesdeRaw(Map<String, dynamic> raw) {
    final snap = _snapshotDesdeRaw(raw);
    final idReserva = raw['id_reserva_grupal']?.toString();
    final idGrupo = raw['id_grupo']?.toString() ?? snap?['id_grupo']?.toString();

    int? cantidad;
    if (snap != null) {
      final c = snap['cantidad'];
      if (c is num) {
        cantidad = c.toInt();
      } else if (snap['miembros'] is List) {
        cantidad = (snap['miembros'] as List).length;
      }
    }

    final esSquad = (idReserva != null && idReserva.isNotEmpty) ||
        (cantidad != null && cantidad > 1) ||
        (idGrupo != null && idGrupo.isNotEmpty);
    if (!esSquad) return (idGrupo: null, cantidad: null);

    return (idGrupo: idGrupo, cantidad: cantidad ?? 1);
  }

  String _infoGrupoProvisional(int cantidad) =>
      'Squad · $cantidad ${cantidad == 1 ? 'persona' : 'personas'}';

  Future<Map<String, String>> _nombresGrupos(Set<String> ids) async {
    if (ids.isEmpty) return const {};
    try {
      final rows = await ServicioSupabase()
          .cliente
          .from('grupos_salidas')
          .select('id_grupo, nombre_grupo')
          .inFilter('id_grupo', ids.toList());
      final map = <String, String>{};
      for (final raw in (rows as List).cast<Map<String, dynamic>>()) {
        final id = raw['id_grupo']?.toString() ?? '';
        final nombre = raw['nombre_grupo']?.toString().trim() ?? '';
        if (id.isNotEmpty && nombre.isNotEmpty) map[id] = nombre;
      }
      return map;
    } catch (e) {
      debugPrint('⚠️ nombres grupos actividad staff: $e');
      return const {};
    }
  }

  List<ActividadStaffItem> _enriquecerInfoGrupo(
    List<({ActividadStaffItem item, String? idGrupo, int? cantidad})> pendientes,
    Map<String, String> nombresGrupos,
  ) {
    return pendientes.map((p) {
      final cant = p.cantidad;
      String? infoGrupo;
      if (cant != null) {
        final idGrupo = p.idGrupo;
        final nombre = idGrupo != null ? nombresGrupos[idGrupo] : null;
        infoGrupo = (nombre != null && nombre.isNotEmpty)
            ? '$nombre · $cant ${cant == 1 ? 'persona' : 'personas'}'
            : _infoGrupoProvisional(cant);
      }
      return ActividadStaffItem(
        tipo: p.item.tipo,
        titulo: p.item.titulo,
        subtitulo: p.item.subtitulo,
        fecha: p.item.fecha,
        estadoLabel: p.item.estadoLabel,
        colorEstado: p.item.colorEstado,
        icono: p.item.icono,
        usuarioNombre: p.item.usuarioNombre,
        usuarioUsername: p.item.usuarioUsername,
        codigoToken: p.item.codigoToken,
        infoGrupo: infoGrupo,
      );
    }).toList();
  }

  Future<List<ActividadStaffItem>> listarActividadReciente({
    String? idLocal,
    String? idStaff,
    int limite = 40,
  }) async {
    final actorId = idStaff ?? _uid;
    if (actorId == null) return const [];

    // Dueño del local filtra acciones de un empleado solo en su local.
    final filtroLocal = idLocal ?? (idStaff != null ? _uid : null);

    final pendientes = <({ActividadStaffItem item, String? idGrupo, int? cantidad})>[];
    final idsGrupo = <String>{};

    try {
      final pasesRaw = await ServicioSupabase()
          .cliente
          .from('tokens_asistencia')
          .select(
            'id_token, id_evento, id_usuario, id_grupo, id_reserva_grupal, '
            'estado_token, fecha_canje, codigo_puerta, snapshot_squad, '
            'eventos(id_local, titulo_evento), '
            'perfiles_usuarios:id_usuario(username, nombre)',
          )
          .eq('canjeado_por', actorId)
          .not('fecha_canje', 'is', null)
          .order('fecha_canje', ascending: false)
          .limit(limite);

      for (final raw in (pasesRaw as List).cast<Map<String, dynamic>>()) {
        final ev = raw['eventos'];
        Map<String, dynamic>? evMap;
        if (ev is Map<String, dynamic>) evMap = ev;
        if (filtroLocal != null && evMap?['id_local']?.toString() != filtroLocal) {
          continue;
        }
        final fechaStr = raw['fecha_canje'] as String?;
        final fecha = fechaStr != null
            ? DateTime.tryParse(fechaStr) ?? DateTime.now()
            : DateTime.now();
        final tituloEv =
            (evMap?['titulo_evento'] as String?)?.trim() ?? 'Evento';
        final estado = (raw['estado_token'] as String?) ?? '';
        final usuario = _usuarioDesdeRaw(raw);
        final squad = _squadDesdeRaw(raw);
        if (squad.idGrupo != null) idsGrupo.add(squad.idGrupo!);
        final codigo = raw['codigo_puerta']?.toString().trim();
        pendientes.add((
          item: ActividadStaffItem(
            tipo: TipoActividadStaff.pase,
            titulo: tituloEv,
            subtitulo: 'Canje en puerta',
            fecha: fecha,
            estadoLabel: estado == 'canjeada' ? 'Canjeado' : estado,
            colorEstado: estado == 'canjeada'
                ? ColoresFeaturesLocales.flyersIa
                : ColoresLocales.textoSecundarioOnFondoClaro,
            icono: CupertinoIcons.ticket_fill,
            usuarioNombre: usuario.nombre,
            usuarioUsername: usuario.username,
            codigoToken: codigo?.isNotEmpty == true ? codigo : null,
          ),
          idGrupo: squad.idGrupo,
          cantidad: squad.cantidad,
        ));
      }
    } catch (e) {
      debugPrint('⚠️ actividad pases staff: $e');
    }

    try {
      final promosRaw = await ServicioSupabase()
          .cliente
          .from('tokens_promociones')
          .select(
            'id_token, id_usuario, id_grupo, id_reserva_grupal, estado_token, '
            'fecha_canje, token_codigo, snapshot_squad, '
            'promociones(id_local, titulo_promocion, id_evento, eventos(titulo_evento)), '
            'perfiles_usuarios:id_usuario(username, nombre)',
          )
          .eq('canjeado_por', actorId)
          .not('fecha_canje', 'is', null)
          .order('fecha_canje', ascending: false)
          .limit(limite);

      for (final raw in (promosRaw as List).cast<Map<String, dynamic>>()) {
        final promo = raw['promociones'];
        Map<String, dynamic>? promoMap;
        if (promo is Map<String, dynamic>) promoMap = promo;
        if (filtroLocal != null && promoMap?['id_local']?.toString() != filtroLocal) {
          continue;
        }
        final fechaStr = raw['fecha_canje'] as String?;
        final fecha = fechaStr != null
            ? DateTime.tryParse(fechaStr) ?? DateTime.now()
            : DateTime.now();
        final evNested = promoMap?['eventos'];
        final tituloEv = (evNested is Map
                ? evNested['titulo_evento'] as String?
                : null)
            ?.trim();
        final tituloPromo =
            (promoMap?['titulo_promocion'] as String?)?.trim() ?? 'Promo';
        final usuario = _usuarioDesdeRaw(raw);
        final squad = _squadDesdeRaw(raw);
        if (squad.idGrupo != null) idsGrupo.add(squad.idGrupo!);
        final codigo = raw['token_codigo']?.toString().trim();
        pendientes.add((
          item: ActividadStaffItem(
            tipo: TipoActividadStaff.promo,
            titulo: tituloEv ?? tituloPromo,
            subtitulo: tituloPromo,
            fecha: fecha,
            estadoLabel: 'Canjeada',
            colorEstado: ColoresLocales.jerarquiaTop,
            icono: CupertinoIcons.tag_fill,
            usuarioNombre: usuario.nombre,
            usuarioUsername: usuario.username,
            codigoToken: codigo?.isNotEmpty == true ? codigo : null,
          ),
          idGrupo: squad.idGrupo,
          cantidad: squad.cantidad,
        ));
      }
    } catch (e) {
      debugPrint('⚠️ actividad promos staff: $e');
    }

    // ── Listas aceptadas/rechazadas (tokens_asistencia.respondido_por = uid)
    try {
      final listasRaw = await ServicioSupabase()
          .cliente
          .from('tokens_asistencia')
          .select(
            'id_token, id_evento, id_usuario, id_grupo, id_reserva_grupal, '
            'estado_token, fecha_respuesta, codigo_puerta, snapshot_squad, '
            'eventos(id_local, titulo_evento), '
            'perfiles_usuarios:id_usuario(username, nombre)',
          )
          .eq('respondido_por', actorId)
          .isFilter('id_invitacion_rrpp', null)
          .inFilter('estado_token', ['aceptada', 'rechazada', 'canjeada'])
          .not('fecha_respuesta', 'is', null)
          .order('fecha_respuesta', ascending: false)
          .limit(limite);

      for (final raw in (listasRaw as List).cast<Map<String, dynamic>>()) {
        final ev = raw['eventos'];
        Map<String, dynamic>? evMap;
        if (ev is Map<String, dynamic>) evMap = ev;
        if (filtroLocal != null && evMap?['id_local']?.toString() != filtroLocal) {
          continue;
        }
        final fechaStr = raw['fecha_respuesta'] as String?;
        final fecha = fechaStr != null
            ? DateTime.tryParse(fechaStr) ?? DateTime.now()
            : DateTime.now();
        final tituloEv =
            (evMap?['titulo_evento'] as String?)?.trim() ?? 'Evento';
        final estado = (raw['estado_token'] as String?) ?? '';
        if (estado == 'canjeada') continue;
        final esAceptada = estado == 'aceptada';
        final usuario = _usuarioDesdeRaw(raw);
        final squad = _squadDesdeRaw(raw);
        if (squad.idGrupo != null) idsGrupo.add(squad.idGrupo!);
        final codigo = raw['codigo_puerta']?.toString().trim();
        pendientes.add((
          item: ActividadStaffItem(
            tipo: TipoActividadStaff.lista,
            titulo: tituloEv,
            subtitulo: esAceptada ? 'Lista aceptada' : 'Lista rechazada',
            fecha: fecha,
            estadoLabel: esAceptada ? 'Aceptada' : 'Rechazada',
            colorEstado: esAceptada
                ? ColoresFeaturesLocales.recomendadoFernecito
                : ColoresLocales.textoSecundarioOnFondoClaro,
            icono: esAceptada
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.xmark_circle_fill,
            usuarioNombre: usuario.nombre,
            usuarioUsername: usuario.username,
            codigoToken: codigo?.isNotEmpty == true ? codigo : null,
          ),
          idGrupo: squad.idGrupo,
          cantidad: squad.cantidad,
        ));
      }
    } catch (e) {
      debugPrint('⚠️ actividad listas staff: $e');
    }

    // ── Listas vía invitación QR (atribuidas a id_rrpp del staff/local)
    try {
      final invRaw = await ServicioSupabase()
          .cliente
          .from('tokens_asistencia')
          .select(
            'id_token, id_evento, id_usuario, id_grupo, id_reserva_grupal, '
            'estado_token, fecha_respuesta, fecha_creacion, codigo_puerta, snapshot_squad, '
            'eventos(id_local, titulo_evento), '
            'perfiles_usuarios:id_usuario(username, nombre)',
          )
          .eq('id_rrpp', actorId)
          .not('id_invitacion_rrpp', 'is', null)
          .inFilter('estado_token', ['aceptada', 'canjeada'])
          .order('fecha_respuesta', ascending: false)
          .limit(limite);

      for (final raw in (invRaw as List).cast<Map<String, dynamic>>()) {
        final ev = raw['eventos'];
        Map<String, dynamic>? evMap;
        if (ev is Map<String, dynamic>) evMap = ev;
        if (filtroLocal != null && evMap?['id_local']?.toString() != filtroLocal) {
          continue;
        }
        final fechaStr = (raw['fecha_respuesta'] ?? raw['fecha_creacion'])?.toString();
        final fecha = fechaStr != null
            ? DateTime.tryParse(fechaStr) ?? DateTime.now()
            : DateTime.now();
        final tituloEv =
            (evMap?['titulo_evento'] as String?)?.trim() ?? 'Evento';
        final estado = (raw['estado_token'] as String?) ?? '';
        final usuario = _usuarioDesdeRaw(raw);
        final squad = _squadDesdeRaw(raw);
        if (squad.idGrupo != null) idsGrupo.add(squad.idGrupo!);
        final codigo = raw['codigo_puerta']?.toString().trim();
        pendientes.add((
          item: ActividadStaffItem(
            tipo: TipoActividadStaff.invitacion,
            titulo: tituloEv,
            subtitulo: 'Sumó a lista escaneando tu QR',
            fecha: fecha,
            estadoLabel: 'Invitación QR',
            colorEstado: ColoresFeaturesLocales.recomendadoFernecito,
            icono: CupertinoIcons.qrcode,
            usuarioNombre: usuario.nombre,
            usuarioUsername: usuario.username,
            codigoToken: codigo?.isNotEmpty == true ? codigo : null,
          ),
          idGrupo: squad.idGrupo,
          cantidad: squad.cantidad,
        ));
      }
    } catch (e) {
      debugPrint('⚠️ actividad invitaciones staff: $e');
    }

    final nombresGrupos = await _nombresGrupos(idsGrupo);
    final items = _enriquecerInfoGrupo(pendientes, nombresGrupos);
    items.sort((a, b) => b.fecha.compareTo(a.fecha));
    if (items.length > limite) return items.sublist(0, limite);
    return items;
  }

  /// Historial de un empleado para el dueño del local (aceptaciones + canjes).
  Future<List<ActividadStaffItem>> listarActividadEmpleado({
    required String idStaff,
    int limite = 50,
  }) {
    return listarActividadReciente(idStaff: idStaff, limite: limite);
  }
}
