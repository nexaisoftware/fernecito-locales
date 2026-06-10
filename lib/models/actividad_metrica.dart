library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

enum TipoActividadMetrica { evento, asistencia, promo }

/// Subtipo granular para filtros combinables en la pestaña Actividad.
enum CategoriaActividadMetrica {
  listaAceptada,
  listaRechazada,
  invitacionQr,
  qrPase,
  qrPromo,
  eventoPublicado,
  eventoFinalizado,
  eventoCancelado,
}

extension CategoriaActividadMetricaLabels on CategoriaActividadMetrica {
  String get etiquetaChip {
    switch (this) {
      case CategoriaActividadMetrica.listaAceptada:
        return 'Listas aceptadas';
      case CategoriaActividadMetrica.listaRechazada:
        return 'Listas rechazadas';
      case CategoriaActividadMetrica.invitacionQr:
        return 'QR RRPP';
      case CategoriaActividadMetrica.qrPase:
        return 'QR pases';
      case CategoriaActividadMetrica.qrPromo:
        return 'QR promos';
      case CategoriaActividadMetrica.eventoPublicado:
        return 'Publicaciones';
      case CategoriaActividadMetrica.eventoFinalizado:
        return 'Fin eventos';
      case CategoriaActividadMetrica.eventoCancelado:
        return 'Cancelados';
    }
  }
}

/// Opción del dropdown de actor (local o staff).
class ActorMetricaOpcion {
  const ActorMetricaOpcion({
    required this.id,
    required this.etiqueta,
    this.esLocal = false,
    this.activo = true,
  });

  /// `null` = todos los actores.
  final String? id;
  final String etiqueta;
  final bool esLocal;
  final bool activo;

  static const todos = ActorMetricaOpcion(id: null, etiqueta: 'Todos');
}

/// Infiere categoría para ítems legacy o tras hot reload sin `categoria`.
CategoriaActividadMetrica inferirCategoriaActividadMetrica({
  required TipoActividadMetrica tipo,
  required String estadoLabel,
}) {
  switch (tipo) {
    case TipoActividadMetrica.evento:
      switch (estadoLabel) {
        case 'Finalizado':
          return CategoriaActividadMetrica.eventoFinalizado;
        case 'Cancelado':
          return CategoriaActividadMetrica.eventoCancelado;
        default:
          return CategoriaActividadMetrica.eventoPublicado;
      }
    case TipoActividadMetrica.promo:
      return CategoriaActividadMetrica.qrPromo;
    case TipoActividadMetrica.asistencia:
      switch (estadoLabel) {
        case 'Invitación QR':
          return CategoriaActividadMetrica.invitacionQr;
        case 'Canjeada':
          return CategoriaActividadMetrica.qrPase;
        case 'Rechazada':
        case 'Expirada':
          return CategoriaActividadMetrica.listaRechazada;
        default:
          return CategoriaActividadMetrica.listaAceptada;
      }
  }
}

/// Ítem unificado del feed de actividad del local.
class ActividadMetricaItem {
  const ActividadMetricaItem({
    required this.id,
    required this.tipo,
    CategoriaActividadMetrica? categoria,
    required this.fecha,
    required this.titulo,
    required this.subtitulo,
    required this.estadoLabel,
    required this.icono,
    required this.colorEstado,
    this.idActor,
    this.nombreActor,
    this.etiquetaActor,
  }) : _categoria = categoria;

  final String id;
  final TipoActividadMetrica tipo;
  final CategoriaActividadMetrica? _categoria;
  final DateTime fecha;
  final String titulo;
  final String subtitulo;
  final String estadoLabel;
  final IconData icono;
  final Color colorEstado;
  /// Quién realizó la acción (staff, local). Null solo en casos legacy.
  final String? idActor;
  final String? nombreActor;
  /// Texto completo de autoría (ej. autoaceptada por el local).
  final String? etiquetaActor;

  CategoriaActividadMetrica get categoria =>
      _categoria ??
      inferirCategoriaActividadMetrica(tipo: tipo, estadoLabel: estadoLabel);

  /// Línea secundaria de autor: "Por @staff" o "Autoaceptada por mi local".
  String? get lineaActor {
    final etiqueta = etiquetaActor?.trim();
    if (etiqueta != null && etiqueta.isNotEmpty) return etiqueta;
    final nombre = nombreActor?.trim();
    if (nombre != null && nombre.isNotEmpty) return 'Por $nombre';
    return null;
  }
}

class PuntoRendimiento {
  const PuntoRendimiento({required this.etiqueta, required this.valor});

  final String etiqueta;
  final double valor;
}

/// Datos agregados para la pestaña Rendimientos.
class DatosRendimientoMetricas {
  const DatosRendimientoMetricas({
    required this.traficoPorDia,
    required this.canjesEntradasPorDia,
    required this.reservasPorDia,
    required this.promosCanjeadasPorDia,
    required this.topEventosCanjes,
    required this.totalTrafico,
    required this.totalCanjesEntradas,
    required this.totalReservas,
    required this.totalPromosCanjeadas,
    required this.totalVisitas,
    required this.eventosActivos,
  });

  final List<PuntoRendimiento> traficoPorDia;
  final List<PuntoRendimiento> canjesEntradasPorDia;
  final List<PuntoRendimiento> reservasPorDia;
  final List<PuntoRendimiento> promosCanjeadasPorDia;
  final List<PuntoRendimiento> topEventosCanjes;
  final int totalTrafico;
  final int totalCanjesEntradas;
  final int totalReservas;
  final int totalPromosCanjeadas;
  final int totalVisitas;
  final int eventosActivos;

  static const vacio = DatosRendimientoMetricas(
    traficoPorDia: [],
    canjesEntradasPorDia: [],
    reservasPorDia: [],
    promosCanjeadasPorDia: [],
    topEventosCanjes: [],
    totalTrafico: 0,
    totalCanjesEntradas: 0,
    totalReservas: 0,
    totalPromosCanjeadas: 0,
    totalVisitas: 0,
    eventosActivos: 0,
  );
}
