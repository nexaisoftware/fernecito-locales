/// Planes comunidad — API para la app de locales (solo planes del venue).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final String contactoModo;
  final bool ingresoAbierto;

  bool get estaAbierto => estado == 'abierto';
  bool get estaFinalizado =>
      estado == 'cancelado' || estado == 'finalizado' || estado == 'eliminado';
  bool get hayPedidoPendiente =>
      beneficioEstado == 'pedido' || beneficioEstado == 'contraoferta';
  bool get beneficioAceptado => beneficioEstado == 'aceptado';
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
    return ServicioSupabase()
        .cliente
        .storage
        .from('planes-portadas')
        .getPublicUrl(p);
  }

  String? get fotoOrganizadorUrl {
    final p = fotoOrganizador;
    if (p == null || p.isEmpty) return null;
    if (p.startsWith('http')) return p;
    if (tipoOrganizador == 'squad') {
      return ServicioSupabase()
          .cliente
          .storage
          .from('squad-banners')
          .getPublicUrl(p);
    }
    if (tipoOrganizador == 'local') {
      return ServicioSupabase()
          .cliente
          .storage
          .from('avatars_locales')
          .getPublicUrl(p);
    }
    return ServicioSupabase()
        .cliente
        .storage
        .from('avatars')
        .getPublicUrl(p);
  }

  factory PlanLocalItem.fromMap(Map<String, dynamic> m) {
    DateTime? dt(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString())?.toLocal();
    }

    int? n(dynamic v) =>
        v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');

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
      portadaPath: m['portada_path']?.toString(),
      colorHex: m['color_hex']?.toString() ?? '#C084FC',
      estado: m['estado']?.toString() ?? 'abierto',
      beneficioLocal: m['beneficio_local']?.toString(),
      beneficioEstado: m['beneficio_estado']?.toString() ?? 'ninguno',
      beneficioContraoferta: m['beneficio_contraoferta']?.toString(),
      pedidoBeneficio: m['pedido_beneficio']?.toString(),
      pedidoVotos: n(m['pedido_votos']) ?? 0,
      personasAceptadas: n(m['personas_aceptadas']) ?? n(m['cupo_usados']) ?? 0,
      contactoAnfitrion: m['contacto_anfitrion']?.toString(),
      contactoModo: m['contacto_modo']?.toString() == 'colaborar'
          ? 'colaborar'
          : 'contactar',
      ingresoAbierto: m['ingreso_abierto'] != false,
    );
  }
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
  const PlanLocalDetalle({
    required this.plan,
    required this.miembros,
  });
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
      final plan =
          PlanLocalItem.fromMap(Map<String, dynamic>.from(planRaw));
      final miembrosRaw = res['miembros'];
      final miembros = miembrosRaw is List
          ? miembrosRaw
              .whereType<Map>()
              .map(
                (e) =>
                    PlanLocalMiembro.fromMap(Map<String, dynamic>.from(e)),
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
          if (contraoferta != null) 'p_contraoferta': contraoferta,
        },
      );
      return res is Map && res['ok'] == true;
    } catch (e) {
      debugPrint('⚠️ planes_pedido_responder: $e');
      return false;
    }
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

  Future<void> cerrarCanal(RealtimeChannel canal) async {
    try {
      await _c.removeChannel(canal);
    } catch (_) {}
  }
}
