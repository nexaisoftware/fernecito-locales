library;

import '../models/vinculo_staff_local.dart';

/// Permisos del staff al operar en un local.
/// `null` (no pasarlo a la pantalla) = dueño del local con acceso total.
class PermisosStaffValidar {
  const PermisosStaffValidar({
    required this.aceptarListas,
    required this.canjearPases,
    required this.canjearPromos,
    required this.verListaAceptados,
    this.qrInvitacion = false,
  });

  final bool aceptarListas;
  final bool canjearPases;
  final bool canjearPromos;
  final bool verListaAceptados;
  // QR de RRPP / invitación (default FALSE: permiso especial otorgado por el local).
  final bool qrInvitacion;

  /// Todos los permisos activos (dueño del local).
  static const todos = PermisosStaffValidar(
    aceptarListas: true,
    canjearPases: true,
    canjearPromos: true,
    verListaAceptados: true,
    qrInvitacion: true,
  );

  factory PermisosStaffValidar.desdeVinculo(VinculoStaffLocal v) =>
      PermisosStaffValidar(
        aceptarListas: v.habilitadoAceptarListas,
        canjearPases: v.habilitadoQrPases,
        canjearPromos: v.habilitadoQrPromos,
        verListaAceptados: v.habilitadoVerListaAceptados,
        qrInvitacion: v.habilitadoQrInvitacion,
      );

  bool get puedeValidarQr => canjearPases || canjearPromos;

  bool get tieneAlgunPermiso =>
      aceptarListas ||
      canjearPases ||
      canjearPromos ||
      verListaAceptados ||
      qrInvitacion;
}
