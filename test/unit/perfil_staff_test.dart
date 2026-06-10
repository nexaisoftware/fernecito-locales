import 'package:flutter_test/flutter_test.dart';

import '../../lib/models/perfil_staff.dart';

void main() {
  group('PerfilStaff.fromMap — campos básicos', () {
    test('parsea todos los campos', () {
      final p = PerfilStaff.fromMap({
        'id': 'staff-abc',
        'username': 'juanstaff',
        'nombre': 'Juan López',
        'dni': '12345678',
        'edad': 28,
        'fecha_nacimiento': '1997-03-15',
        'foto_perfil_url': 'avatars/foto.jpg',
        'perfil_completo': true,
      });
      expect(p.id, 'staff-abc');
      expect(p.username, 'juanstaff');
      expect(p.nombre, 'Juan López');
      expect(p.dni, '12345678');
      expect(p.edad, 28);
      expect(p.fechaNacimiento, isNotNull);
      expect(p.fechaNacimiento!.year, 1997);
      expect(p.fotoPerfilUrl, 'avatars/foto.jpg');
      expect(p.perfilCompleto, isTrue);
    });

    test('campos opcionales null si no vienen', () {
      final p = PerfilStaff.fromMap({'id': 'x'});
      expect(p.username, isNull);
      expect(p.nombre, isNull);
      expect(p.dni, isNull);
      expect(p.edad, isNull);
      expect(p.fechaNacimiento, isNull);
      expect(p.fotoPerfilUrl, isNull);
      expect(p.perfilCompleto, isFalse);
    });

    test('trimea espacios en strings', () {
      final p = PerfilStaff.fromMap({
        'id': 'x',
        'username': '  usuario  ',
        'nombre': '  Nombre  ',
      });
      expect(p.username, 'usuario');
      expect(p.nombre, 'Nombre');
    });
  });

  group('PerfilStaff.edadCalculada', () {
    // Hoy: 2026-06-02. Tests diseñados para ser estables en cualquier fecha de 2026.

    test('calcula edad desde fechaNacimiento (cumple en enero → ya cumplió en junio)', () {
      final p = PerfilStaff.fromMap({
        'id': 'x',
        'fecha_nacimiento': '1990-01-01', // cumple en enero, ya pasó en junio
      });
      // 2026 - 1990 = 36, enero ya pasó en junio
      expect(p.edadCalculada, 36);
    });

    test('resta 1 si el cumpleaños no pasó aún (cumple en diciembre)', () {
      final p = PerfilStaff.fromMap({
        'id': 'x',
        'fecha_nacimiento': '1990-12-31', // cumple en diciembre, no pasó en junio
      });
      // 2026 - 1990 = 36, pero diciembre aún no llegó → 35
      expect(p.edadCalculada, 35);
    });

    test('usa campo edad como fallback si fechaNacimiento es null', () {
      final p = PerfilStaff.fromMap({'id': 'x', 'edad': 25});
      expect(p.edadCalculada, 25);
    });

    test('usa campo edad como fallback si fechaNacimiento da edad ≤ 0 (fecha futura)', () {
      final p = PerfilStaff.fromMap({
        'id': 'x',
        'fecha_nacimiento': '2099-01-01', // fecha futura → edad negativa
        'edad': 20,
      });
      expect(p.edadCalculada, 20);
    });

    test('retorna null si ni fechaNacimiento ni edad están disponibles', () {
      final p = PerfilStaff.fromMap({'id': 'x'});
      expect(p.edadCalculada, isNull);
    });
  });

  group('PerfilStaff.estaCompleto', () {
    test('true si perfilCompleto == true (aunque falten otros campos)', () {
      final p = PerfilStaff.fromMap({'id': 'x', 'perfil_completo': true});
      expect(p.estaCompleto, isTrue);
    });

    test('true si tiene nombre + username + edad válida', () {
      final p = PerfilStaff.fromMap({
        'id': 'x',
        'nombre': 'María',
        'username': 'mariastaff',
        'edad': 22,
      });
      expect(p.estaCompleto, isTrue);
    });

    test('true si tiene nombre + username + fechaNacimiento (sin campo edad)', () {
      final p = PerfilStaff.fromMap({
        'id': 'x',
        'nombre': 'Pedro',
        'username': 'pedrostaff',
        'fecha_nacimiento': '2000-05-10',
      });
      expect(p.estaCompleto, isTrue);
    });

    test('false si falta nombre', () {
      final p = PerfilStaff.fromMap({'id': 'x', 'username': 'u', 'edad': 22});
      expect(p.estaCompleto, isFalse);
    });

    test('false si falta username', () {
      final p = PerfilStaff.fromMap({'id': 'x', 'nombre': 'N', 'edad': 22});
      expect(p.estaCompleto, isFalse);
    });

    test('false si tiene nombre + username pero edad es 0 y sin fechaNacimiento', () {
      final p = PerfilStaff.fromMap({'id': 'x', 'nombre': 'N', 'username': 'u', 'edad': 0});
      expect(p.estaCompleto, isFalse);
    });
  });
}
