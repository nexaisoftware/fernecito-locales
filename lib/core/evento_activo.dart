/// Evento mínimo para pantalla de validación QR en puerta.
class EventoActivo {
  final String idEvento;
  final String idLocal;
  final String nombre;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;

  const EventoActivo({
    required this.idEvento,
    required this.idLocal,
    required this.nombre,
    required this.fechaInicio,
    required this.fechaFin,
  });

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String && v.trim().isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  factory EventoActivo.fromMap(Map<String, dynamic> m) => EventoActivo(
        idEvento: m['id_evento'].toString(),
        idLocal: m['id_local'].toString(),
        nombre: ((m['titulo_evento'] as String?) ?? '').trim().isEmpty
            ? 'Evento sin título'
            : (m['titulo_evento'] as String).trim(),
        fechaInicio: _parseDate(m['fecha_inicio']),
        fechaFin: _parseDate(m['fecha_fin']),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EventoActivo && other.idEvento == idEvento);

  @override
  int get hashCode => idEvento.hashCode;
}
