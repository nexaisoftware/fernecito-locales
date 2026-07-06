import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_locales/models/vinculo_staff_local.dart';

Map<String, dynamic> _mapBase({
  String estadoCuenta = 'activa',
  bool activo = true,
  Map<String, dynamic>? overridePerfilLocal,
}) =>
    {
      'id_local': 'local-123',
      'activo': activo,
      'habilitado_qr_promos': true,
      'habilitado_qr_pases': true,
      'habilitado_aceptar_listas': true,
      'habilitado_ver_lista_aceptados': true,
      'habilitado_qr_invitacion': false,
      'perfiles_locales': overridePerfilLocal ??
          {
            'nombre_local': 'Boliche Test',
            'local_username': 'boliche_test',
            'foto_perfil_url': null,
            'estado_cuenta': estadoCuenta,
          },
    };

void main() {
  group('VinculoStaffLocal.fromMap — campos básicos', () {
    test('parsea id, nombre y username', () {
      final v = VinculoStaffLocal.fromMap(_mapBase());
      expect(v.idLocal, 'local-123');
      expect(v.nombreLocal, 'Boliche Test');
      expect(v.localUsername, 'boliche_test');
    });

    test('activo true por defecto', () {
      expect(VinculoStaffLocal.fromMap(_mapBase()).activo, isTrue);
    });

    test('activo false cuando campo es false', () {
      expect(VinculoStaffLocal.fromMap(_mapBase(activo: false)).activo, isFalse);
    });
  });

  group('VinculoStaffLocal.fromMap — localBloqueado', () {
    test('false cuando estado_cuenta == activa', () {
      final v = VinculoStaffLocal.fromMap(_mapBase(estadoCuenta: 'activa'));
      expect(v.localBloqueado, isFalse);
    });

    test('true cuando estado_cuenta == pausada', () {
      final v = VinculoStaffLocal.fromMap(_mapBase(estadoCuenta: 'pausada'));
      expect(v.localBloqueado, isTrue);
    });

    test('true cuando estado_cuenta == suspendida', () {
      final v = VinculoStaffLocal.fromMap(_mapBase(estadoCuenta: 'suspendida'));
      expect(v.localBloqueado, isTrue);
    });
  });

  group('VinculoStaffLocal.fromMap — flags de permisos', () {
    test('todos los flags true por defecto desde mapBase', () {
      final v = VinculoStaffLocal.fromMap(_mapBase());
      expect(v.habilitadoQrPromos, isTrue);
      expect(v.habilitadoQrPases, isTrue);
      expect(v.habilitadoAceptarListas, isTrue);
      expect(v.habilitadoVerListaAceptados, isTrue);
    });

    test('habilitadoQrInvitacion false por defecto (permiso especial)', () {
      expect(VinculoStaffLocal.fromMap(_mapBase()).habilitadoQrInvitacion, isFalse);
    });

    test('habilitadoQrInvitacion true cuando campo es true', () {
      final map = _mapBase()..[('habilitado_qr_invitacion')] = true;
      expect(VinculoStaffLocal.fromMap(map).habilitadoQrInvitacion, isTrue);
    });

    test('flags se pueden poner en false individualmente', () {
      final map = _mapBase()
        ..['habilitado_qr_promos'] = false
        ..['habilitado_qr_pases'] = false
        ..['habilitado_aceptar_listas'] = false
        ..['habilitado_ver_lista_aceptados'] = false;
      final v = VinculoStaffLocal.fromMap(map);
      expect(v.habilitadoQrPromos, isFalse);
      expect(v.habilitadoQrPases, isFalse);
      expect(v.habilitadoAceptarListas, isFalse);
      expect(v.habilitadoVerListaAceptados, isFalse);
    });
  });

  group('VinculoStaffLocal.fromMap — fallback de nombreLocal', () {
    test('usa local_username si nombre_local está vacío', () {
      final v = VinculoStaffLocal.fromMap(_mapBase(
        overridePerfilLocal: {
          'nombre_local': '',
          'local_username': 'username_fallback',
          'foto_perfil_url': null,
          'estado_cuenta': 'activa',
        },
      ));
      expect(v.nombreLocal, 'username_fallback');
    });

    test('usa "Local" como fallback final si local_username es null', () {
      // ?? solo aplica cuando el campo es null, no cuando es string vacío
      final v = VinculoStaffLocal.fromMap(_mapBase(
        overridePerfilLocal: {
          'nombre_local': '',
          'local_username': null,
          'foto_perfil_url': null,
          'estado_cuenta': 'activa',
        },
      ));
      expect(v.nombreLocal, 'Local');
    });
  });

  group('VinculoStaffLocal.fromMap — compatibilidad con join de Supabase', () {
    // Supabase a veces devuelve el join como lista en vez de objeto
    test('acepta perfiles_locales como List (join devuelto como array)', () {
      final map = _mapBase()
        ..['perfiles_locales'] = [
          {
            'nombre_local': 'Local en Lista',
            'local_username': 'local_lista',
            'foto_perfil_url': null,
            'estado_cuenta': 'activa',
          }
        ];
      final v = VinculoStaffLocal.fromMap(map);
      expect(v.nombreLocal, 'Local en Lista');
      expect(v.localBloqueado, isFalse);
    });
  });
}
