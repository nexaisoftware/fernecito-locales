library;

class PerfilStaff {
  const PerfilStaff({
    required this.id,
    this.username,
    this.nombre,
    this.dni,
    this.edad,
    this.fechaNacimiento,
    this.fotoPerfilUrl,
    this.perfilCompleto = false,
  });

  final String id;
  final String? username;
  final String? nombre;
  final String? dni;
  final int? edad;
  final DateTime? fechaNacimiento;
  final String? fotoPerfilUrl;
  final bool perfilCompleto;

  factory PerfilStaff.fromMap(Map<String, dynamic> map) {
    return PerfilStaff(
      id: map['id'].toString(),
      username: (map['username'] as String?)?.trim(),
      nombre: (map['nombre'] as String?)?.trim(),
      dni: (map['dni'] as String?)?.trim(),
      edad: (map['edad'] as num?)?.toInt(),
      fechaNacimiento: map['fecha_nacimiento'] != null
          ? DateTime.tryParse(map['fecha_nacimiento'].toString())
          : null,
      fotoPerfilUrl: (map['foto_perfil_url'] as String?)?.trim(),
      perfilCompleto: map['perfil_completo'] == true,
    );
  }

  /// Edad calculada desde fecha_nacimiento (si está) — fallback al campo `edad`.
  int? get edadCalculada {
    if (fechaNacimiento != null) {
      final ahora = DateTime.now();
      var anios = ahora.year - fechaNacimiento!.year;
      if (ahora.month < fechaNacimiento!.month ||
          (ahora.month == fechaNacimiento!.month && ahora.day < fechaNacimiento!.day)) {
        anios--;
      }
      if (anios > 0) return anios;
    }
    return edad;
  }

  bool get estaCompleto =>
      perfilCompleto ||
      ((nombre?.isNotEmpty ?? false) &&
          (username?.isNotEmpty ?? false) &&
          (edad != null && edad! > 0 || fechaNacimiento != null));
}
