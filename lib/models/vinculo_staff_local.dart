library;

class VinculoStaffLocal {
  const VinculoStaffLocal({
    required this.idLocal,
    required this.nombreLocal,
    this.localUsername,
    this.fotoLocalUrl,
    this.activo = true,
    this.localBloqueado = false,
    this.habilitadoQrPromos = true,
    this.habilitadoQrPases = true,
    this.habilitadoAceptarListas = true,
    this.habilitadoVerListaAceptados = true,
    this.habilitadoQrInvitacion = false,
  });

  final String idLocal;
  final String nombreLocal;
  final String? localUsername;
  final String? fotoLocalUrl;
  final bool activo;

  /// La CUENTA del local fue suspendida/pausada por el owner de Fernecito
  /// (distinto de [activo], que es el vínculo staff↔local). Si está bloqueado,
  /// el staff no puede operar para ese local: el backend devuelve 403
  /// `local_suspendido` igual, esto es solo para reflejarlo en la UI.
  final bool localBloqueado;
  final bool habilitadoQrPromos;
  final bool habilitadoQrPases;
  final bool habilitadoAceptarListas;
  final bool habilitadoVerListaAceptados;
  final bool habilitadoQrInvitacion;

  factory VinculoStaffLocal.fromMap(Map<String, dynamic> map) {
    final perfilLocal = map['perfiles_locales'];
    Map<String, dynamic>? pl;
    if (perfilLocal is Map<String, dynamic>) {
      pl = perfilLocal;
    } else if (perfilLocal is List && perfilLocal.isNotEmpty) {
      pl = perfilLocal.first as Map<String, dynamic>?;
    }

    return VinculoStaffLocal(
      idLocal: map['id_local'].toString(),
      nombreLocal: (pl?['nombre_local'] as String?)?.trim().isNotEmpty == true
          ? (pl!['nombre_local'] as String).trim()
          : (pl?['local_username'] as String?)?.trim() ?? 'Local',
      localUsername: (pl?['local_username'] as String?)?.trim(),
      fotoLocalUrl: (pl?['foto_perfil_url'] as String?)?.trim(),
      activo: map['activo'] != false,
      localBloqueado:
          (pl?['estado_cuenta'] as String?)?.trim().isNotEmpty == true &&
              (pl!['estado_cuenta'] as String).trim() != 'activa',
      habilitadoQrPromos: map['habilitado_qr_promos'] != false,
      habilitadoQrPases: map['habilitado_qr_pases'] != false,
      habilitadoAceptarListas: map['habilitado_aceptar_listas'] != false,
      habilitadoVerListaAceptados: map['habilitado_ver_lista_aceptados'] != false,
      habilitadoQrInvitacion: map['habilitado_qr_invitacion'] == true,
    );
  }
}
