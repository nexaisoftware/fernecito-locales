library;

import 'package:flutter/cupertino.dart';

enum TipoActividadStaff { pase, promo, lista, invitacion }

class ActividadStaffItem {
  const ActividadStaffItem({
    required this.tipo,
    required this.titulo,
    required this.subtitulo,
    required this.fecha,
    required this.estadoLabel,
    required this.colorEstado,
    required this.icono,
    this.usuarioNombre,
    this.usuarioUsername,
    this.codigoToken,
    this.infoGrupo,
  });

  final TipoActividadStaff tipo;
  final String titulo;
  final String subtitulo;
  final DateTime fecha;
  final String estadoLabel;
  final Color colorEstado;
  final IconData icono;
  final String? usuarioNombre;
  final String? usuarioUsername;
  final String? codigoToken;
  final String? infoGrupo;

  String get usuarioDisplay {
    final nombre = usuarioNombre?.trim();
    final username = usuarioUsername?.trim();
    if (nombre != null && nombre.isNotEmpty && username != null && username.isNotEmpty) {
      return '$nombre · @$username';
    }
    if (nombre != null && nombre.isNotEmpty) return nombre;
    if (username != null && username.isNotEmpty) return '@$username';
    return 'Usuario';
  }

  bool get tieneUsuario =>
      (usuarioNombre?.trim().isNotEmpty ?? false) ||
      (usuarioUsername?.trim().isNotEmpty ?? false);
}
