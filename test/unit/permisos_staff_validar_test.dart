import 'package:flutter_test/flutter_test.dart';

import '../../lib/core/permisos_staff_validar.dart';
import '../../lib/models/vinculo_staff_local.dart';

VinculoStaffLocal _vinculo({
  bool qrPromos = false,
  bool qrPases = false,
  bool aceptarListas = false,
  bool verListaAceptados = false,
  bool qrInvitacion = false,
}) =>
    VinculoStaffLocal(
      idLocal: 'local-test-001',
      nombreLocal: 'Local Test',
      habilitadoQrPromos: qrPromos,
      habilitadoQrPases: qrPases,
      habilitadoAceptarListas: aceptarListas,
      habilitadoVerListaAceptados: verListaAceptados,
      habilitadoQrInvitacion: qrInvitacion,
    );

void main() {
  group('PermisosStaffValidar.todos', () {
    test('tiene todos los flags activos', () {
      const p = PermisosStaffValidar.todos;
      expect(p.aceptarListas, isTrue);
      expect(p.canjearPases, isTrue);
      expect(p.canjearPromos, isTrue);
      expect(p.verListaAceptados, isTrue);
      expect(p.qrInvitacion, isTrue);
    });

    test('puedeValidarQr es true', () {
      expect(PermisosStaffValidar.todos.puedeValidarQr, isTrue);
    });

    test('tieneAlgunPermiso es true', () {
      expect(PermisosStaffValidar.todos.tieneAlgunPermiso, isTrue);
    });
  });

  group('PermisosStaffValidar.puedeValidarQr', () {
    test('true si solo canjearPases activo', () {
      const p = PermisosStaffValidar(
        aceptarListas: false,
        canjearPases: true,
        canjearPromos: false,
        verListaAceptados: false,
      );
      expect(p.puedeValidarQr, isTrue);
    });

    test('true si solo canjearPromos activo', () {
      const p = PermisosStaffValidar(
        aceptarListas: false,
        canjearPases: false,
        canjearPromos: true,
        verListaAceptados: false,
      );
      expect(p.puedeValidarQr, isTrue);
    });

    test('false si ni canjearPases ni canjearPromos', () {
      const p = PermisosStaffValidar(
        aceptarListas: true,
        canjearPases: false,
        canjearPromos: false,
        verListaAceptados: true,
        qrInvitacion: true,
      );
      expect(p.puedeValidarQr, isFalse);
    });
  });

  group('PermisosStaffValidar.tieneAlgunPermiso', () {
    test('false cuando todos los flags son false', () {
      const p = PermisosStaffValidar(
        aceptarListas: false,
        canjearPases: false,
        canjearPromos: false,
        verListaAceptados: false,
        qrInvitacion: false,
      );
      expect(p.tieneAlgunPermiso, isFalse);
    });

    test('true con solo aceptarListas activo', () {
      const p = PermisosStaffValidar(
        aceptarListas: true,
        canjearPases: false,
        canjearPromos: false,
        verListaAceptados: false,
      );
      expect(p.tieneAlgunPermiso, isTrue);
    });

    test('true con solo qrInvitacion activo', () {
      const p = PermisosStaffValidar(
        aceptarListas: false,
        canjearPases: false,
        canjearPromos: false,
        verListaAceptados: false,
        qrInvitacion: true,
      );
      expect(p.tieneAlgunPermiso, isTrue);
    });
  });

  group('PermisosStaffValidar.desdeVinculo', () {
    test('copia todos los flags del VinculoStaffLocal', () {
      final v = _vinculo(
        qrPromos: true,
        qrPases: false,
        aceptarListas: true,
        verListaAceptados: true,
        qrInvitacion: false,
      );
      final p = PermisosStaffValidar.desdeVinculo(v);
      expect(p.canjearPromos, isTrue);
      expect(p.canjearPases, isFalse);
      expect(p.aceptarListas, isTrue);
      expect(p.verListaAceptados, isTrue);
      expect(p.qrInvitacion, isFalse);
    });

    test('staff solo con canjes de promos: puede validarQr pero no aceptar listas', () {
      final p = PermisosStaffValidar.desdeVinculo(_vinculo(qrPromos: true));
      expect(p.puedeValidarQr, isTrue);
      expect(p.aceptarListas, isFalse);
    });

    test('staff sin ningún permiso: tieneAlgunPermiso false, puedeValidarQr false', () {
      final p = PermisosStaffValidar.desdeVinculo(_vinculo());
      expect(p.tieneAlgunPermiso, isFalse);
      expect(p.puedeValidarQr, isFalse);
    });

    test('staff solo con pases: puedeValidarQr true, canjearPromos false', () {
      final p = PermisosStaffValidar.desdeVinculo(_vinculo(qrPases: true));
      expect(p.puedeValidarQr, isTrue);
      expect(p.canjearPromos, isFalse);
    });

    test('qrInvitacion default false cuando no se pasa', () {
      final p = PermisosStaffValidar.desdeVinculo(_vinculo());
      expect(p.qrInvitacion, isFalse);
    });
  });
}
