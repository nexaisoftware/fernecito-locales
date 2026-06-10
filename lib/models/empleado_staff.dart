library;

import 'package:flutter/material.dart';

class EmpleadoStaff {
  const EmpleadoStaff({
    required this.idStaff,
    required this.username,
    this.nombre,
    this.fotoPerfilUrl,
    required this.activo,
    this.fechaCreacion,
    this.habilitadoQrPromos = true,
    this.habilitadoQrPases = true,
    this.habilitadoAceptarListas = true,
    this.habilitadoVerListaAceptados = true,
    this.habilitadoQrInvitacion = false,
    this.qrInvitacionPasarCupo = false,
  });

  final String idStaff;
  final String username;
  final String? nombre;
  final String? fotoPerfilUrl;
  final bool activo;
  final DateTime? fechaCreacion;
  // Permisos granulares (default TRUE en DB).
  final bool habilitadoQrPromos;
  final bool habilitadoQrPases;
  final bool habilitadoAceptarListas;
  final bool habilitadoVerListaAceptados;
  // QR de RRPP / invitación (default FALSE: permiso especial).
  final bool habilitadoQrInvitacion;
  final bool qrInvitacionPasarCupo;

  EmpleadoStaff copyWith({
    bool? activo,
    bool? habilitadoQrPromos,
    bool? habilitadoQrPases,
    bool? habilitadoAceptarListas,
    bool? habilitadoVerListaAceptados,
    bool? habilitadoQrInvitacion,
    bool? qrInvitacionPasarCupo,
  }) {
    return EmpleadoStaff(
      idStaff: idStaff,
      username: username,
      nombre: nombre,
      fotoPerfilUrl: fotoPerfilUrl,
      activo: activo ?? this.activo,
      fechaCreacion: fechaCreacion,
      habilitadoQrPromos: habilitadoQrPromos ?? this.habilitadoQrPromos,
      habilitadoQrPases: habilitadoQrPases ?? this.habilitadoQrPases,
      habilitadoAceptarListas: habilitadoAceptarListas ?? this.habilitadoAceptarListas,
      habilitadoVerListaAceptados: habilitadoVerListaAceptados ?? this.habilitadoVerListaAceptados,
      habilitadoQrInvitacion: habilitadoQrInvitacion ?? this.habilitadoQrInvitacion,
      qrInvitacionPasarCupo: qrInvitacionPasarCupo ?? this.qrInvitacionPasarCupo,
    );
  }

  String get displayName {
    final u = username.trim();
    if (u.isNotEmpty) return u;
    final n = nombre?.trim();
    if (n != null && n.isNotEmpty) return n;
    return 'staff';
  }

  Color avatarColorFor(String seed) {
    final hash = seed.codeUnits.fold<int>(0, (a, b) => a + b);
    const palette = [
      Color(0xFFEDE8F7),
      Color(0xFFF3EDFF),
      Color(0xFFE8F4FD),
      Color(0xFFFDF2F8),
      Color(0xFFECFDF5),
    ];
    return palette[hash % palette.length];
  }

  factory EmpleadoStaff.fromMap(Map<String, dynamic> map) {
    final perfilStaffRaw = map['perfiles_staff'];
    final perfilUsuarioRaw = map['perfiles_usuarios'];
    Map<String, dynamic>? perfil;
    if (perfilStaffRaw is Map) {
      perfil = Map<String, dynamic>.from(perfilStaffRaw);
    } else if (perfilUsuarioRaw is Map) {
      perfil = Map<String, dynamic>.from(perfilUsuarioRaw);
    }

    DateTime? fecha;
    final fc = map['fecha_creacion'];
    if (fc != null) {
      fecha = DateTime.tryParse(fc.toString())?.toLocal();
    }

    return EmpleadoStaff(
      idStaff: map['id_staff']?.toString() ?? '',
      username: perfil?['username']?.toString().trim() ?? '',
      nombre: perfil?['nombre']?.toString().trim(),
      fotoPerfilUrl: perfil?['foto_perfil_url']?.toString().trim(),
      activo: map['activo'] == true || map['activo'] == 'true' || map['activo'] == 1,
      fechaCreacion: fecha,
      // Permisos: default true si no viene el campo en la respuesta.
      habilitadoQrPromos: map['habilitado_qr_promos'] != false,
      habilitadoQrPases: map['habilitado_qr_pases'] != false,
      habilitadoAceptarListas: map['habilitado_aceptar_listas'] != false,
      habilitadoVerListaAceptados: map['habilitado_ver_lista_aceptados'] != false,
      // Default FALSE: solo true si la DB lo trae explícitamente.
      habilitadoQrInvitacion: map['habilitado_qr_invitacion'] == true,
      qrInvitacionPasarCupo: map['qr_invitacion_pasar_cupo'] == true,
    );
  }
}
