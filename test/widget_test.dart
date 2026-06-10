// Test básico de la app Fernecito Locales.

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_locales/main.dart';

void main() {
  testWidgets('App Locales arranca y muestra login', (WidgetTester tester) async {
    await tester.pumpWidget(const AppLocales());

    expect(find.text('¡Bienvenido a Fernecito Locales!'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
  });
}
