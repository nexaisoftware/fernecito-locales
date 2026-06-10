// EdgeException es la pieza que conecta los errores del backend (Edge Functions)
// con la UI. Si el código está mal mapeado, la app puede crashear o mostrar
// mensajes incorrectos al canjear/gestionar listas.
import 'package:flutter_test/flutter_test.dart';

import '../../lib/core/servicio_edges_eventos.dart';

void main() {
  group('EdgeException — constructor', () {
    test('guarda todos los campos correctamente', () {
      final e = EdgeException(
        funcion: 'canjear_asistencia',
        status: 400,
        code: 'already_canjeado',
        mensaje: 'El token ya fue canjeado',
        detail: 'token_id: abc-123',
      );
      expect(e.funcion, 'canjear_asistencia');
      expect(e.status, 400);
      expect(e.code, 'already_canjeado');
      expect(e.mensaje, 'El token ya fue canjeado');
      expect(e.detail, 'token_id: abc-123');
    });

    test('detail es opcional (null por defecto)', () {
      final e = EdgeException(
        funcion: 'gestionar_asistencia',
        status: 500,
        code: 'network_error',
        mensaje: 'Timeout',
      );
      expect(e.detail, isNull);
    });
  });

  group('EdgeException.yaAplicada — códigos idempotentes', () {
    // Crítico: estos 4 códigos significan "ya estaba hecho", no es un error real.
    // El UI debe tratarlos como éxito silencioso, no mostrar error.

    test('already_canjeado → yaAplicada true', () {
      final e = EdgeException(funcion: 'f', status: 409, code: 'already_canjeado', mensaje: '');
      expect(e.yaAplicada, isTrue);
    });

    test('already_rechazado → yaAplicada true', () {
      final e = EdgeException(funcion: 'f', status: 409, code: 'already_rechazado', mensaje: '');
      expect(e.yaAplicada, isTrue);
    });

    test('already_cancelado → yaAplicada true', () {
      final e = EdgeException(funcion: 'f', status: 409, code: 'already_cancelado', mensaje: '');
      expect(e.yaAplicada, isTrue);
    });

    test('stale_pending_state → yaAplicada true', () {
      final e = EdgeException(funcion: 'f', status: 409, code: 'stale_pending_state', mensaje: '');
      expect(e.yaAplicada, isTrue);
    });

    test('código desconocido → yaAplicada false', () {
      final e = EdgeException(funcion: 'f', status: 500, code: 'network_error', mensaje: '');
      expect(e.yaAplicada, isFalse);
    });

    test('código vacío → yaAplicada false', () {
      final e = EdgeException(funcion: 'f', status: 400, code: '', mensaje: '');
      expect(e.yaAplicada, isFalse);
    });

    test('códigos de error reales (cupo_lleno, no_autorizado) → yaAplicada false', () {
      for (final code in ['cupo_lleno', 'no_autorizado', 'rpc_not_found', 'local_suspendido']) {
        final e = EdgeException(funcion: 'f', status: 403, code: code, mensaje: '');
        expect(e.yaAplicada, isFalse, reason: 'code "$code" no debería ser yaAplicada');
      }
    });
  });

  group('EdgeException.toString', () {
    test('incluye función, status, code y mensaje', () {
      final e = EdgeException(
        funcion: 'canjear_promocion',
        status: 404,
        code: 'promo_not_found',
        mensaje: 'Promo no encontrada',
      );
      final s = e.toString();
      expect(s, contains('canjear_promocion'));
      expect(s, contains('404'));
      expect(s, contains('promo_not_found'));
      expect(s, contains('Promo no encontrada'));
    });

    test('sin detail: no incluye " — "', () {
      final e = EdgeException(funcion: 'f', status: 400, code: 'c', mensaje: 'm');
      expect(e.toString(), isNot(contains(' — ')));
    });

    test('con detail: incluye " — " y el detalle', () {
      final e = EdgeException(
        funcion: 'f', status: 400, code: 'c', mensaje: 'm',
        detail: 'contexto extra',
      );
      expect(e.toString(), contains(' — contexto extra'));
    });
  });

  group('EdgeException — es Exception', () {
    test('puede ser capturada como Exception', () {
      expect(
        () => throw EdgeException(funcion: 'f', status: 500, code: 'err', mensaje: 'msg'),
        throwsA(isA<EdgeException>()),
      );
    });

    test('puede distinguirse de una Exception genérica', () {
      expect(
        () => throw EdgeException(funcion: 'f', status: 500, code: 'err', mensaje: 'msg'),
        throwsA(isA<EdgeException>().having((e) => e.code, 'code', 'err')),
      );
    });
  });
}
