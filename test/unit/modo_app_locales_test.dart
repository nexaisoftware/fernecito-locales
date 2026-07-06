import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_locales/core/modo_app_locales.dart';

void main() {
  // ModoAppLocales es un singleton. Reseteamos el estado antes de cada test
  // modificando directamente el ValueNotifier (accesible por ser público).
  setUp(() {
    ModoAppLocales.instancia.modo.value = ModoAppLocalesTipo.local;
  });

  group('ModoAppLocales — estado inicial', () {
    test('arranca en modo local por defecto', () {
      expect(ModoAppLocales.instancia.esLocal, isTrue);
      expect(ModoAppLocales.instancia.esStaff, isFalse);
    });
  });

  group('ModoAppLocales.establecerStaff', () {
    test('cambia a modo staff', () {
      ModoAppLocales.instancia.establecerStaff();
      expect(ModoAppLocales.instancia.esStaff, isTrue);
      expect(ModoAppLocales.instancia.esLocal, isFalse);
    });

    test('es idempotente (llamar dos veces no rompe nada)', () {
      ModoAppLocales.instancia.establecerStaff();
      ModoAppLocales.instancia.establecerStaff();
      expect(ModoAppLocales.instancia.esStaff, isTrue);
    });
  });

  group('ModoAppLocales.establecerLocal', () {
    test('vuelve a modo local desde staff', () {
      ModoAppLocales.instancia.establecerStaff();
      ModoAppLocales.instancia.establecerLocal();
      expect(ModoAppLocales.instancia.esLocal, isTrue);
      expect(ModoAppLocales.instancia.esStaff, isFalse);
    });

    test('es idempotente en modo local', () {
      ModoAppLocales.instancia.establecerLocal();
      ModoAppLocales.instancia.establecerLocal();
      expect(ModoAppLocales.instancia.esLocal, isTrue);
    });
  });

  group('ModoAppLocales — ciclo completo', () {
    test('local → staff → local funciona correctamente', () {
      expect(ModoAppLocales.instancia.esLocal, isTrue);

      ModoAppLocales.instancia.establecerStaff();
      expect(ModoAppLocales.instancia.esStaff, isTrue);

      ModoAppLocales.instancia.establecerLocal();
      expect(ModoAppLocales.instancia.esLocal, isTrue);
    });
  });

  group('ModoAppLocales — ValueNotifier notifica cambios', () {
    test('notifica al cambiar a staff', () {
      int notificaciones = 0;
      ModoAppLocales.instancia.modo.addListener(() => notificaciones++);

      ModoAppLocales.instancia.establecerStaff();
      expect(notificaciones, 1);

      // Limpiar listener
      ModoAppLocales.instancia.modo.removeListener(() {});
    });

    test('no notifica si el modo ya es el mismo', () {
      // Ya está en local (setUp lo garantiza)
      int notificaciones = 0;
      ModoAppLocales.instancia.modo.addListener(() => notificaciones++);

      ModoAppLocales.instancia.establecerLocal(); // ya es local → no notifica
      expect(notificaciones, 0);

      ModoAppLocales.instancia.modo.removeListener(() {});
    });
  });

  group('ModoAppLocalesTipo enum', () {
    test('contiene local y staff', () {
      expect(ModoAppLocalesTipo.values, containsAll([
        ModoAppLocalesTipo.local,
        ModoAppLocalesTipo.staff,
      ]));
    });
  });
}
