library;

import 'package:flutter/cupertino.dart';

/// Notificación in-app para el local (tabla `notificaciones_locales`).
class Notificacion {
  final String id;
  final String idLocal;
  final String tipo;
  final String prioridad; // 'alta' | 'media' | 'baja'
  final String titulo;
  final String descripcion;
  final String? iconoKey;
  final String? ctaTexto;
  final String? ctaRuta;
  final String? ctaIdRef;
  final Map<String, dynamic>? payload;
  final bool leida;
  final DateTime fechaCreacion;
  final DateTime? fechaLectura;

  const Notificacion({
    required this.id,
    required this.idLocal,
    required this.tipo,
    required this.prioridad,
    required this.titulo,
    required this.descripcion,
    this.iconoKey,
    this.ctaTexto,
    this.ctaRuta,
    this.ctaIdRef,
    this.payload,
    required this.leida,
    required this.fechaCreacion,
    this.fechaLectura,
  });

  factory Notificacion.fromMap(Map<String, dynamic> m) {
    return Notificacion(
      id: m['id'].toString(),
      idLocal: m['id_local'].toString(),
      tipo: (m['tipo'] as String?) ?? '',
      prioridad: (m['prioridad'] as String?) ?? 'media',
      titulo: (m['titulo'] as String?) ?? '',
      descripcion: (m['descripcion'] as String?) ?? '',
      iconoKey: m['icono_key'] as String?,
      ctaTexto: m['cta_texto'] as String?,
      ctaRuta: m['cta_ruta'] as String?,
      ctaIdRef: m['cta_id_ref']?.toString(),
      payload: m['payload'] is Map ? Map<String, dynamic>.from(m['payload'] as Map) : null,
      leida: m['leida'] == true,
      fechaCreacion:
          DateTime.tryParse(m['fecha_creacion']?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc(),
      fechaLectura: m['fecha_lectura'] != null
          ? DateTime.tryParse(m['fecha_lectura'].toString())?.toUtc()
          : null,
    );
  }

  /// Mapea `icono_key` (string del backend) → IconData de Cupertino.
  /// Si no matchea, retorna bell genérico. Centralizado acá para que
  /// la UI no tenga que mapear strings sueltos.
  IconData get icono {
    switch (iconoKey) {
      case 'list_bullet':
        return CupertinoIcons.list_bullet;
      case 'checkmark_seal_fill':
        return CupertinoIcons.checkmark_seal_fill;
      case 'star_fill':
        return CupertinoIcons.star_fill;
      case 'star_lefthalf_fill':
        return CupertinoIcons.star_lefthalf_fill;
      case 'tag_fill':
        return CupertinoIcons.tag_fill;
      case 'creditcard_fill':
        return CupertinoIcons.creditcard;
      case 'exclamationmark_triangle_fill':
        return CupertinoIcons.exclamationmark_triangle_fill;
      case 'clock_fill':
        return CupertinoIcons.clock_fill;
      case 'person_3_fill':
        return CupertinoIcons.person_3_fill;
      case 'xmark_circle_fill':
        return CupertinoIcons.xmark_circle_fill;
      case 'checkmark_circle_fill':
        return CupertinoIcons.checkmark_circle_fill;
      default:
        return CupertinoIcons.bell_fill;
    }
  }

  /// Fecha relativa amigable: "Hace 5 min", "Hace 1 h", "Ayer", "Hace 3 días", "DD/MM"
  String get fechaRelativa {
    final ahora = DateTime.now().toUtc();
    final diff = ahora.difference(fechaCreacion);
    if (diff.inSeconds < 60) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    if (diff.inDays == 1) return 'Ayer';
    if (diff.inDays < 7) return 'Hace ${diff.inDays} días';
    final l = fechaCreacion.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}';
  }

  Notificacion copyWith({bool? leida, DateTime? fechaLectura}) {
    return Notificacion(
      id: id,
      idLocal: idLocal,
      tipo: tipo,
      prioridad: prioridad,
      titulo: titulo,
      descripcion: descripcion,
      iconoKey: iconoKey,
      ctaTexto: ctaTexto,
      ctaRuta: ctaRuta,
      ctaIdRef: ctaIdRef,
      payload: payload,
      leida: leida ?? this.leida,
      fechaCreacion: fechaCreacion,
      fechaLectura: fechaLectura ?? this.fechaLectura,
    );
  }
}
