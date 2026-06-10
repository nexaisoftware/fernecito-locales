import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:frontend_locales/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Fernecito Locales - Smoke Tests', () {
    testWidgets('La app de Locales arranca y muestra la pantalla de login', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Buscamos textos que sabemos que aparecen en la pantalla de login
      final welcomeText = find.textContaining('Bienvenido');
      final loginButton = find.text('Entrar');

      expect(
        welcomeText.evaluate().isNotEmpty || loginButton.evaluate().isNotEmpty,
        isTrue,
        reason: 'Debería mostrar la pantalla de login o bienvenida',
      );
    });
  });
}