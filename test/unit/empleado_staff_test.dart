import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_locales/models/empleado_staff.dart';

Map<String, dynamic> _mapBase({
  bool activo = true,
  Map<String, dynamic>? perfilStaff,
  Map<String, dynamic>? perfilUsuario,
  bool qrPromos = true,
  bool qrPases = true,
  bool aceptarListas = true,
  bool verListaAceptados = true,
  bool qrInvitacion = false,
  bool qrInvitacionPasarCupo = false,
}) =>
    {
      'id_staff': 'staff-001',
      'activo': activo,
      'fecha_creacion': '2026-01-15T10:00:00.000Z',
      'habilitado_qr_promos': qrPromos,
      'habilitado_qr_pases': qrPases,
      'habilitado_aceptar_listas': aceptarListas,
      'habilitado_ver_lista_aceptados': verListaAceptados,
      'habilitado_qr_invitacion': qrInvitacion,
      'qr_invitacion_pasar_cupo': qrInvitacionPasarCupo,
      'perfiles_staff': ?perfilStaff,
      'perfiles_usuarios': ?perfilUsuario,
    };

void main() {
  group('EmpleadoStaff.fromMap — campos básicos', () {
    test('parsea id_staff y fecha', () {
      final e = EmpleadoStaff.fromMap(_mapBase(
        perfilStaff: {'username': 'juanstaff', 'nombre': 'Juan', 'foto_perfil_url': null},
      ));
      expect(e.idStaff, 'staff-001');
      expect(e.fechaCreacion, isNotNull);
      expect(e.fechaCreacion!.month, 1);
    });

    test('activo true cuando campo es true', () {
      expect(EmpleadoStaff.fromMap(_mapBase(
        activo: true,
        perfilStaff: {'username': 'u'},
      )).activo, isTrue);
    });

    test('activo false cuando campo es false', () {
      expect(EmpleadoStaff.fromMap(_mapBase(
        activo: false,
        perfilStaff: {'username': 'u'},
      )).activo, isFalse);
    });

    test('activo acepta string "true" (compat legacy)', () {
      final map = _mapBase(perfilStaff: {'username': 'u'})..['activo'] = 'true';
      expect(EmpleadoStaff.fromMap(map).activo, isTrue);
    });

    test('activo acepta int 1 (compat legacy)', () {
      final map = _mapBase(perfilStaff: {'username': 'u'})..['activo'] = 1;
      expect(EmpleadoStaff.fromMap(map).activo, isTrue);
    });
  });

  group('EmpleadoStaff.fromMap — resolución de perfil', () {
    test('usa perfiles_staff si está disponible', () {
      final e = EmpleadoStaff.fromMap(_mapBase(
        perfilStaff: {'username': 'staff_user', 'nombre': 'Staff Nombre', 'foto_perfil_url': 'foto.jpg'},
      ));
      expect(e.username, 'staff_user');
      expect(e.nombre, 'Staff Nombre');
      expect(e.fotoPerfilUrl, 'foto.jpg');
    });

    test('usa perfiles_usuarios como fallback si no hay perfiles_staff', () {
      final e = EmpleadoStaff.fromMap(_mapBase(
        perfilUsuario: {'username': 'user_fallback', 'nombre': 'User FB', 'foto_perfil_url': null},
      ));
      expect(e.username, 'user_fallback');
      expect(e.nombre, 'User FB');
    });

    test('username vacío si no hay ningún perfil', () {
      final e = EmpleadoStaff.fromMap({'id_staff': 'x', 'activo': false});
      expect(e.username, '');
    });
  });

  group('EmpleadoStaff.fromMap — permisos', () {
    test('todos los flags true por defecto', () {
      final e = EmpleadoStaff.fromMap(_mapBase(perfilStaff: {'username': 'u'}));
      expect(e.habilitadoQrPromos, isTrue);
      expect(e.habilitadoQrPases, isTrue);
      expect(e.habilitadoAceptarListas, isTrue);
      expect(e.habilitadoVerListaAceptados, isTrue);
    });

    test('habilitadoQrInvitacion default false (permiso especial)', () {
      final e = EmpleadoStaff.fromMap(_mapBase(perfilStaff: {'username': 'u'}));
      expect(e.habilitadoQrInvitacion, isFalse);
      expect(e.qrInvitacionPasarCupo, isFalse);
    });

    test('flags en false cuando se pasan explícitamente', () {
      final e = EmpleadoStaff.fromMap(_mapBase(
        perfilStaff: {'username': 'u'},
        qrPromos: false,
        qrPases: false,
        aceptarListas: false,
        verListaAceptados: false,
      ));
      expect(e.habilitadoQrPromos, isFalse);
      expect(e.habilitadoQrPases, isFalse);
      expect(e.habilitadoAceptarListas, isFalse);
      expect(e.habilitadoVerListaAceptados, isFalse);
    });

    test('habilitadoQrInvitacion true cuando se pasa true', () {
      final e = EmpleadoStaff.fromMap(_mapBase(
        perfilStaff: {'username': 'u'},
        qrInvitacion: true,
        qrInvitacionPasarCupo: true,
      ));
      expect(e.habilitadoQrInvitacion, isTrue);
      expect(e.qrInvitacionPasarCupo, isTrue);
    });
  });

  group('EmpleadoStaff.displayName', () {
    test('retorna username si está disponible', () {
      const e = EmpleadoStaff(idStaff: 'x', username: 'miusername', activo: true);
      expect(e.displayName, 'miusername');
    });

    test('retorna nombre si username está vacío', () {
      const e = EmpleadoStaff(idStaff: 'x', username: '', nombre: 'Mi Nombre', activo: true);
      expect(e.displayName, 'Mi Nombre');
    });

    test('retorna "staff" si ambos están vacíos', () {
      const e = EmpleadoStaff(idStaff: 'x', username: '', activo: true);
      expect(e.displayName, 'staff');
    });
  });

  group('EmpleadoStaff.copyWith', () {
    const original = EmpleadoStaff(
      idStaff: 'emp-1',
      username: 'original_user',
      activo: true,
      habilitadoQrPromos: true,
      habilitadoAceptarListas: true,
    );

    test('crea nueva instancia con campos modificados', () {
      final copia = original.copyWith(activo: false, habilitadoQrPromos: false);
      expect(copia.activo, isFalse);
      expect(copia.habilitadoQrPromos, isFalse);
    });

    test('mantiene los campos no modificados', () {
      final copia = original.copyWith(activo: false);
      expect(copia.idStaff, 'emp-1');
      expect(copia.username, 'original_user');
      expect(copia.habilitadoAceptarListas, isTrue);
    });

    test('no modifica el original', () {
      original.copyWith(activo: false);
      expect(original.activo, isTrue);
    });
  });

  group('EmpleadoStaff.avatarColorFor', () {
    test('misma seed → mismo color (determinístico)', () {
      const e = EmpleadoStaff(idStaff: 'x', username: 'u', activo: true);
      final c1 = e.avatarColorFor('seed-test');
      final c2 = e.avatarColorFor('seed-test');
      expect(c1, equals(c2));
    });

    test('diferentes seeds pueden dar diferentes colores', () {
      const e = EmpleadoStaff(idStaff: 'x', username: 'u', activo: true);
      // Genera 5 colores con seeds distintas — al menos uno diferente del primero
      final colores = List.generate(5, (i) => e.avatarColorFor('seed-$i')).toSet();
      expect(colores.length, greaterThan(1));
    });

    test('retorna un color no transparente', () {
      const e = EmpleadoStaff(idStaff: 'x', username: 'u', activo: true);
      final color = e.avatarColorFor('staff-001');
      expect(color.alpha, greaterThan(0));
    });
  });
}
