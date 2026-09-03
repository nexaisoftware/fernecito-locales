/// Planes comunidad — API para la app de locales (solo planes del venue).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'comprimir_imagen_storage.dart';
import 'supabase_client.dart';

class PlanLocalItem {
  const PlanLocalItem({
    required this.id,
    required this.titulo,
    required this.descripcion,
    required this.ciudad,
    required this.fechaInicio,
    required this.modoLista,
    required this.cupoUsados,
    required this.nombreOrganizador,
    required this.tipoOrganizador,
    this.provincia,
    this.fechaFin,
    this.cupoMax,
    this.fotoOrganizador,
    this.nombreSquad,
    this.nombreLocal,
    this.portadaPath,
    this.colorHex = '#C084FC',
    this.estado = 'abierto',
    this.beneficioLocal,
    this.beneficioEstado = 'ninguno',
    this.beneficioContraoferta,
    this.pedidoBeneficio,
    this.pedidoVotos = 0,
    this.personasAceptadas = 0,
    this.contactoAnfitrion,
    this.contactoTitulo,
    this.contactoModo = 'contactar',
    this.ingresoAbierto = true,
  });

  final String id;
  final String titulo;
  final String descripcion;
  final String ciudad;
  final String? provincia;
  final DateTime fechaInicio;
  final DateTime? fechaFin;
  final String modoLista;
  final int? cupoMax;
  final int cupoUsados;
  final String nombreOrganizador;
  final String? fotoOrganizador;
  final String tipoOrganizador;
  final String? nombreSquad;

  /// Nombre del venue (para badge LOCAL / @menciones).
  final String? nombreLocal;
  final String? portadaPath;
  final String colorHex;
  final String estado;
  final String? beneficioLocal;
  final String beneficioEstado;
  final String? beneficioContraoferta;
  final String? pedidoBeneficio;
  final int pedidoVotos;
  final int personasAceptadas;
  final String? contactoAnfitrion;
  final String? contactoTitulo;
  final String contactoModo;
  final bool ingresoAbierto;

  bool get estaAbierto => estado == 'abierto';
  bool get estaFinalizado =>
      estado == 'cancelado' || estado == 'finalizado' || estado == 'eliminado';
  bool get hayPedidoPendiente => beneficioEstado == 'pedido';
  bool get beneficioAceptado =>
      beneficioEstado == 'aceptado' || beneficioEstado == 'contraoferta';
  bool get sinPedido =>
      beneficioEstado == 'ninguno' || beneficioEstado == 'rechazado';

  String? get textoPedidoActivo {
    if (beneficioEstado == 'contraoferta') {
      return beneficioContraoferta?.trim().isNotEmpty == true
          ? beneficioContraoferta
          : pedidoBeneficio;
    }
    if (beneficioEstado == 'pedido') return pedidoBeneficio;
    if (beneficioEstado == 'aceptado') return beneficioLocal;
    return null;
  }

  String? get portadaUrl {
    final p = portadaPath;
    if (p == null || p.isEmpty) return null;
    if (p.startsWith('http') || p.startsWith('assets/')) return p;
    return ServicioSupabase().cliente.storage
        .from('planes-portadas')
        .getPublicUrl(p);
  }

  String? get fotoOrganizadorUrl {
    final p = fotoOrganizador;
    if (p == null || p.isEmpty) return null;
    if (p.startsWith('http')) return p;
    if (tipoOrganizador == 'squad') {
      return ServicioSupabase().cliente.storage
          .from('squad-banners')
          .getPublicUrl(p);
    }
    if (tipoOrganizador == 'local') {
      return ServicioSupabase().cliente.storage
          .from('avatars_locales')
          .getPublicUrl(p);
    }
    return ServicioSupabase().cliente.storage.from('avatars').getPublicUrl(p);
  }

  factory PlanLocalItem.fromMap(Map<String, dynamic> m) {
    DateTime? dt(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString())?.toLocal();
    }

    int? n(dynamic v) =>
        v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');

    final beneficioEstadoRaw = m['beneficio_estado']?.toString() ?? 'ninguno';
    final beneficioEstado = beneficioEstadoRaw == 'rechazado'
        ? 'ninguno'
        : beneficioEstadoRaw;

    return PlanLocalItem(
      id: m['id']?.toString() ?? '',
      titulo: m['titulo']?.toString() ?? '',
      descripcion: m['descripcion']?.toString() ?? '',
      ciudad: m['ciudad']?.toString() ?? '',
      provincia: m['provincia']?.toString(),
      fechaInicio: dt(m['fecha_inicio']) ?? DateTime.now(),
      fechaFin: dt(m['fecha_fin']),
      modoLista: m['modo_lista']?.toString() ?? 'auto',
      cupoMax: n(m['cupo_max']),
      cupoUsados: n(m['cupo_usados']) ?? n(m['personas_aceptadas']) ?? 0,
      nombreOrganizador: m['nombre_organizador']?.toString() ?? 'Alguien',
      fotoOrganizador: m['foto_organizador']?.toString(),
      tipoOrganizador: m['tipo_organizador']?.toString() ?? 'usuario',
      nombreSquad: m['nombre_squad']?.toString(),
      nombreLocal: m['nombre_local']?.toString(),
      portadaPath: m['portada_path']?.toString(),
      colorHex: m['color_hex']?.toString() ?? '#C084FC',
      estado: m['estado']?.toString() ?? 'abierto',
      beneficioLocal: m['beneficio_local']?.toString(),
      beneficioEstado: beneficioEstado,
      beneficioContraoferta: m['beneficio_contraoferta']?.toString(),
      pedidoBeneficio: m['pedido_beneficio']?.toString(),
      pedidoVotos: n(m['pedido_votos']) ?? 0,
      personasAceptadas: n(m['personas_aceptadas']) ?? n(m['cupo_usados']) ?? 0,
      contactoAnfitrion: m['contacto_anfitrion']?.toString(),
      contactoTitulo: m['contacto_titulo']?.toString(),
      contactoModo: () {
        final mdo = m['contacto_modo']?.toString().toLowerCase() ?? '';
        if (mdo == 'vaquita' || mdo == 'colaborar') return 'vaquita';
        return 'contactar';
      }(),
      ingresoAbierto: m['ingreso_abierto'] != false,
    );
  }
}

class LocalDestinoParaPlan {
  const LocalDestinoParaPlan({
    required this.id,
    required this.nombreLocal,
    this.ciudad,
    this.fotoPerfilUrl,
  });

  final String id;
  final String nombreLocal;
  final String? ciudad;
  final String? fotoPerfilUrl;

  factory LocalDestinoParaPlan.fromMap(Map<String, dynamic> m) =>
      LocalDestinoParaPlan(
        id: m['id']?.toString() ?? '',
        nombreLocal: m['nombre_local']?.toString() ?? 'Local',
        ciudad: m['ciudad']?.toString(),
        fotoPerfilUrl: m['foto_perfil_url']?.toString(),
      );
}

class PlanLocalMiembro {
  const PlanLocalMiembro({
    required this.idUsuario,
    required this.nombre,
    required this.estado,
    this.username,
    this.fotoPath,
    this.rol = 'miembro',
    this.nombreSquad,
  });

  final String idUsuario;
  final String nombre;
  final String? username;
  final String? fotoPath;
  final String rol;
  final String estado;
  final String? nombreSquad;

  String? get fotoUrl {
    final p = fotoPath;
    if (p == null || p.isEmpty) return null;
    if (p.startsWith('http')) return p;
    return ServicioSupabase().cliente.storage.from('avatars').getPublicUrl(p);
  }

  factory PlanLocalMiembro.fromMap(Map<String, dynamic> m) => PlanLocalMiembro(
    idUsuario: m['id_usuario']?.toString() ?? '',
    nombre: m['nombre']?.toString() ?? 'Alguien',
    username: m['username']?.toString(),
    fotoPath: m['foto_perfil_url']?.toString(),
    rol: m['rol']?.toString() ?? 'miembro',
    estado: m['estado']?.toString() ?? 'aceptado',
    nombreSquad: m['nombre_squad']?.toString(),
  );
}

class PlanLocalDetalle {
  const PlanLocalDetalle({required this.plan, required this.miembros});
  final PlanLocalItem plan;
  final List<PlanLocalMiembro> miembros;
}

class PlanLocalMensaje {
  const PlanLocalMensaje({
    required this.id,
    required this.cuerpo,
    required this.creadoEn,
    this.idAutor,
    this.idAutorLocal,
    this.autorTipo = 'usuario',
    this.tipo = 'mensaje',
  });

  final int id;
  final String? idAutor;
  final String? idAutorLocal;
  final String autorTipo;
  final String tipo;
  final String cuerpo;
  final DateTime creadoEn;

  bool get esSistema =>
      autorTipo == 'sistema' || tipo == 'sistema' || tipo == 'beneficio';
  bool get esLocal => autorTipo == 'local';

  factory PlanLocalMensaje.fromMap(Map<String, dynamic> m) {
    final idRaw = m['id'];
    final id = idRaw is num
        ? idRaw.toInt()
        : int.tryParse(idRaw?.toString() ?? '') ?? 0;
    return PlanLocalMensaje(
      id: id,
      idAutor: m['id_autor']?.toString(),
      idAutorLocal: m['id_autor_local']?.toString(),
      autorTipo: m['autor_tipo']?.toString() ?? 'usuario',
      tipo: m['tipo']?.toString() ?? 'mensaje',
      cuerpo: m['cuerpo']?.toString() ?? '',
      creadoEn:
          DateTime.tryParse(m['creado_en']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }
}

class ServicioPlanesLocales {
  ServicioPlanesLocales._();
  static final instancia = ServicioPlanesLocales._();

  SupabaseClient get _c => ServicioSupabase().cliente;
  String? get miUid => _c.auth.currentUser?.id;

  /// Busca locales activos para que un organizador pueda elegir “local adherido”.
  /// Si [q] viene vacío, devuelve una grilla corta (prioriza verificados si existe la columna).
  Future<List<LocalDestinoParaPlan>> buscarLocalesActivos({
    String? q,
    int limit = 8,
  }) async {
    try {
      final query = (q ?? '').trim();
      final base = _c
          .from('perfiles_locales')
          .select('id, nombre_local, ciudad, foto_perfil_url')
          .eq('estado_cuenta', 'activa');

      final res = query.isEmpty
          ? await base
              .order('local_verificado', ascending: false)
              .limit(limit)
          : await base.ilike('nombre_local', '%$query%').limit(limit);

      final rows = res is List ? res : const <dynamic>[];
      return rows
          .whereType<Map>()
          .map((e) => LocalDestinoParaPlan.fromMap(Map<String, dynamic>.from(e)))
          .where((x) => x.id.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      debugPrint('⚠️ buscarLocalesActivos: $e');
      return const [];
    }
  }

  Future<({List<PlanLocalItem> items, bool hayMas, String? error})> hub({
    int limit = 30,
    int offset = 0,
    String? q,
  }) async {
    try {
      // Siempre enviar la firma completa (incl. p_q) para evitar PGRST203
      // si quedaran sobrecargas viejas de planes_hub en Postgres.
      final res = await _c.rpc(
        'planes_hub',
        params: {
          'p_ciudades': null,
          'p_provincia': null,
          'p_modo': 'local',
          'p_limit': limit,
          'p_offset': offset,
          'p_q': (q == null || q.trim().isEmpty) ? null : q.trim(),
        },
      );
      if (res is! Map) {
        return (items: <PlanLocalItem>[], hayMas: false, error: null);
      }
      final raw = res['items'];
      final list = raw is List
          ? raw
                .whereType<Map>()
                .map((e) => PlanLocalItem.fromMap(Map<String, dynamic>.from(e)))
                .where((p) => p.id.isNotEmpty)
                .toList()
          : <PlanLocalItem>[];
      return (items: list, hayMas: res['hay_mas'] == true, error: null);
    } catch (e) {
      debugPrint('⚠️ planes_hub local: $e');
      return (items: <PlanLocalItem>[], hayMas: false, error: e.toString());
    }
  }

  Future<PlanLocalDetalle?> detalle(String idPlan) async {
    try {
      final res = await _c.rpc('planes_detalle', params: {'p_id_plan': idPlan});
      if (res is! Map) return null;
      final planRaw = res['plan'];
      if (planRaw is! Map) return null;
      final plan = PlanLocalItem.fromMap(Map<String, dynamic>.from(planRaw));
      final miembrosRaw = res['miembros'];
      final miembros = miembrosRaw is List
          ? miembrosRaw
                .whereType<Map>()
                .map(
                  (e) => PlanLocalMiembro.fromMap(Map<String, dynamic>.from(e)),
                )
                .toList()
          : <PlanLocalMiembro>[];
      return PlanLocalDetalle(plan: plan, miembros: miembros);
    } catch (e) {
      debugPrint('⚠️ planes_detalle local: $e');
      return null;
    }
  }

  Future<bool> pedidoResponder({
    required String idPlan,
    required String accion,
    String? contraoferta,
  }) async {
    try {
      final res = await _c.rpc(
        'planes_pedido_responder',
        params: {
          'p_id_plan': idPlan,
          'p_accion': accion,
          'p_contraoferta': contraoferta,
        },
      );
      if (res is Map && res['ok'] == true) return true;
      throw Exception(
        res is Map
            ? (res['error']?.toString() ?? 'respuesta_invalida')
            : 'respuesta_invalida',
      );
    } catch (e) {
      debugPrint('⚠️ planes_pedido_responder: $e');
      rethrow;
    }
  }

  Future<bool> cancelar(String idPlan) async {
    try {
      final res = await _c.rpc(
        'planes_cancelar',
        params: {'p_id_plan': idPlan},
      );
      if (res is Map && res['ok'] == true) return true;
      throw Exception(
        res is Map
            ? (res['error']?.toString() ?? 'respuesta_invalida')
            : 'respuesta_invalida',
      );
    } catch (e) {
      debugPrint('⚠️ planes_cancelar: $e');
      rethrow;
    }
  }

  /// Acepta o rechaza una solicitud pendiente de ingreso en una lista manual.
  Future<bool> gestionarMiembro({
    required String idPlan,
    required String idUsuario,
    required String accion,
  }) async {
    try {
      final res = await _c.rpc(
        'planes_gestionar_miembro',
        params: {
          'p_id_plan': idPlan,
          'p_id_usuario': idUsuario,
          'p_accion': accion,
        },
      );
      if (res is Map && res['ok'] == true) return true;
      throw Exception(
        res is Map
            ? (res['error']?.toString() ?? 'respuesta_invalida')
            : 'respuesta_invalida',
      );
    } catch (e) {
      debugPrint('⚠️ planes_gestionar_miembro: $e');
      rethrow;
    }
  }

  Future<String?> crear({
    required String titulo,
    required String descripcion,
    required DateTime fechaInicio,
    DateTime? fechaFin,
    String modoLista = 'auto',
    int? cupoMax,
    String? contactoAnfitrion,
    String? contactoTitulo,
    String contactoModo = 'contactar',
    String? portadaPath,
    String colorHex = '#C084FC',
    bool permiteSquads = true,
    int? edadMinima,
    String tipoOrganizador = 'local',
    String? idLocalDestino,
    bool esUbicacionCustom = false,
    String? ubicacionCustom,
    String? urlMapsCustom,
  }) async {
    final uid = miUid;
    if (uid == null) return null;
    try {
      final res = await _c.rpc(
        'planes_crear',
        params: {
          'p_titulo': titulo,
          'p_descripcion': descripcion,
          'p_id_local': (idLocalDestino ?? uid),
          'p_fecha_inicio': fechaInicio.toUtc().toIso8601String(),
          'p_fecha_fin': fechaFin?.toUtc().toIso8601String(),
          'p_modo_lista': modoLista,
          'p_cupo_max': cupoMax,
          'p_tipo_organizador': tipoOrganizador,
          'p_creador_tipo': 'local',
          'p_contacto_anfitrion': contactoAnfitrion,
          'p_contacto_titulo': contactoTitulo,
          'p_contacto_modo': (contactoModo == 'vaquita' || contactoModo == 'colaborar') ? 'vaquita' : 'contactar',
          'p_portada_path': portadaPath,
          'p_color_hex': colorHex,
          'p_permite_squads': permiteSquads,
          'p_edad_minima': edadMinima,
          'p_es_ubicacion_custom': esUbicacionCustom,
          'p_ubicacion_custom':
              esUbicacionCustom ? ubicacionCustom?.trim() : null,
          'p_url_maps_custom': esUbicacionCustom ? urlMapsCustom?.trim() : null,
        },
      );
      if (res is Map && res['ok'] == true) return res['id']?.toString();
      return null;
    } catch (e) {
      debugPrint('⚠️ planes_crear local: $e');
      rethrow;
    }
  }

  Future<bool> actualizarBasico({
    required String idPlan,
    String? descripcion,
    DateTime? fechaInicio,
    DateTime? fechaFin,
    int? cupoMax,
    bool sinCupo = false,
    bool? ingresoAbierto,
    String? contactoAnfitrion,
    String? contactoTitulo,
    String? contactoModo,
    bool limpiarContacto = false,
  }) async {
    try {
      final res = await _c.rpc(
        'planes_actualizar_basico',
        params: {
          'p_id_plan': idPlan,
          'p_descripcion': descripcion,
          'p_fecha_inicio': fechaInicio?.toUtc().toIso8601String(),
          'p_fecha_fin': fechaFin?.toUtc().toIso8601String(),
          'p_cupo_max': cupoMax,
          'p_sin_cupo': sinCupo,
          'p_ingreso_abierto': ingresoAbierto,
          'p_contacto_anfitrion': contactoAnfitrion,
          'p_contacto_titulo': contactoTitulo,
          'p_contacto_modo': contactoModo,
          'p_limpiar_contacto': limpiarContacto,
        },
      );
      if (res is Map && res['ok'] == true) return true;
      throw Exception(
        res is Map
            ? (res['error']?.toString() ?? 'respuesta_invalida')
            : 'respuesta_invalida',
      );
    } catch (e) {
      debugPrint('⚠️ planes_actualizar_basico local: $e');
      rethrow;
    }
  }

  Future<String?> subirPortada({
    required String idTemporal,
    required Uint8List bytes,
    String ext = 'jpg',
  }) async {
    final uid = miUid;
    if (uid == null) return null;
    try {
      final path = '$uid/$idTemporal.jpg';
      await _c.storage
          .from('planes-portadas')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: contentTypeDesdeExtension(
                ext == 'webp' ? 'jpg' : ext,
              ),
            ),
          );
      return path;
    } catch (e) {
      debugPrint('⚠️ subirPortada plan local: $e');
      return null;
    }
  }

  String mensajeError(Object error, {String accion = 'procesar el plan'}) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('no_auth') || msg.contains('jwt')) {
      return 'Tu sesión expiró. Cerrá sesión y volvé a entrar.';
    }
    if (msg.contains('rate') || msg.contains('demasiad')) {
      return 'Estás haciendo muchas acciones seguidas. Esperá un ratito y probá de nuevo.';
    }
    if (msg.contains('no_local')) {
      return 'Solo el local dueño puede crear o gestionar este plan.';
    }
    if (msg.contains('titulo_invalido')) {
      return 'El título tiene que tener entre 3 y 80 caracteres.';
    }
    if (msg.contains('descripcion_invalida')) {
      return 'La descripción es demasiado larga o corta.';
    }
    if (msg.contains('fecha_fin_invalida')) {
      return 'La fecha de fin no puede ser antes del inicio.';
    }
    if (msg.contains('fecha_fuera_ventana')) {
      return 'La fecha del plan está fuera de la ventana permitida.';
    }
    if (msg.contains('local_inactivo') || msg.contains('local_inexistente')) {
      return 'Tu local no está disponible para publicar planes.';
    }
    if (msg.contains('beneficio_ya_en_juego')) {
      return 'Este plan ya tiene un beneficio confirmado o pendiente.';
    }
    if (msg.contains('pedido_invalido')) {
      return 'El beneficio tiene que tener entre 3 y 120 caracteres.';
    }
    if (msg.contains('no_autorizado')) {
      return 'No tenés permisos para $accion en este plan.';
    }
    if (msg.contains('miembro_inexistente')) {
      return 'No encontramos esa solicitud. Actualizá el plan e intentá de nuevo.';
    }
    if (msg.contains('accion_invalida')) {
      return 'Esa acción no está disponible para este plan.';
    }
    if (msg.contains('plan_finalizado')) {
      return 'Este plan ya está finalizado y quedó archivado.';
    }
    if (msg.contains('plan_cerrado')) {
      return 'Este plan está cerrado y ya no permite acciones.';
    }
    if (msg.contains('plan_inexistente')) {
      return 'No encontramos ese plan.';
    }
    if (msg.contains('estado_invalido') || msg.contains('estado_invalida')) {
      return 'El estado del plan no permite esta acción.';
    }
    if (msg.contains('respuesta_invalida')) {
      return 'El servidor no confirmó la acción. Actualizá el plan y probá de nuevo.';
    }
    return 'No se pudo $accion. Revisá conexión y probá de nuevo.';
  }

  Future<List<PlanLocalMensaje>> historial(String idPlan) async {
    final rows = await _c
        .from('planes_mensajes')
        .select(
          'id, id_autor, id_autor_local, autor_tipo, tipo, cuerpo, creado_en',
        )
        .eq('id_plan', idPlan)
        .order('id', ascending: true)
        .limit(300);
    return (rows as List)
        .map(
          (e) => PlanLocalMensaje.fromMap(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  Future<int?> enviarMensaje(String idPlan, String cuerpo) async {
    final res = await _c.rpc(
      'planes_enviar_mensaje',
      params: {'p_id_plan': idPlan, 'p_cuerpo': cuerpo},
    );
    if (res is Map && res['id'] != null) {
      final id = res['id'];
      return id is num ? id.toInt() : int.tryParse(id.toString());
    }
    return null;
  }

  Future<void> marcarLeido(String idPlan) async {
    try {
      await _c.rpc('planes_marcar_leido', params: {'p_id_plan': idPlan});
    } catch (e) {
      debugPrint('⚠️ planes_marcar_leido: $e');
    }
  }

  RealtimeChannel suscribirMensajes(
    String idPlan,
    void Function(PlanLocalMensaje) onMensaje,
  ) {
    final canal = _c.channel('planes_chat_local_$idPlan');
    canal
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'planes_mensajes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id_plan',
            value: idPlan,
          ),
          callback: (payload) {
            try {
              onMensaje(
                PlanLocalMensaje.fromMap(
                  Map<String, dynamic>.from(payload.newRecord),
                ),
              );
            } catch (e) {
              debugPrint('⚠️ realtime mensaje plan: $e');
            }
          },
        )
        .subscribe();
    return canal;
  }

  RealtimeChannel suscribirCambiosPlan(
    String idPlan,
    void Function() onCambio,
  ) {
    final canal = _c.channel('planes_estado_local_$idPlan');
    canal
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'planes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: idPlan,
          ),
          callback: (_) => onCambio(),
        )
        .subscribe();
    return canal;
  }

  Future<void> cerrarCanal(RealtimeChannel canal) async {
    try {
      await _c.removeChannel(canal);
    } catch (_) {}
  }
}
