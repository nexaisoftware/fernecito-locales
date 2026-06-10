library;

import 'dart:typed_data';

/// Datos para prellenar [LocalesCrearEvento] desde un flyer generado con IA.
class CrearEventoDesdeFlyerArgs {
  const CrearEventoDesdeFlyerArgs({
    required this.tituloEvento,
    this.rutaFlyerLocal,
    this.urlFlyerRemota,
    this.flyerBytes,
    this.nombrePromo,
    this.fechaInicio,
    this.fechaFin,
    this.activarPromos = false,
  });

  final String tituloEvento;
  final String? rutaFlyerLocal;
  final String? urlFlyerRemota;
  final Uint8List? flyerBytes;
  final String? nombrePromo;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;
  final bool activarPromos;

  /// Día/mes sin año del formulario IA → [DateTime] con año coherente (actual o siguiente).
  static DateTime? fechaDesdePartes({
    required int mesIdx,
    required int diaMes,
    required int hora,
    required int minuto,
  }) {
    final now = DateTime.now();
    var year = now.year;
    var dt = DateTime(year, mesIdx + 1, diaMes, hora, minuto);
    if (dt.isBefore(now.subtract(const Duration(hours: 6)))) {
      dt = DateTime(year + 1, mesIdx + 1, diaMes, hora, minuto);
    }
    return dt;
  }

  static DateTime? fechaFinDesdeInicio(DateTime? inicio) {
    if (inicio == null) return null;
    return inicio.add(const Duration(hours: 5));
  }
}
