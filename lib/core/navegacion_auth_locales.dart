library;

import 'package:flutter/material.dart';

import 'navigator_key_locales.dart';
import 'modo_app_locales.dart';

/// Sale del flujo staff y muestra el login principal de locales (dueño).
/// No usa [Navigator.pop]: si staff login es la única ruta (logout / modo staff),
/// un pop dejaría pantalla negra.
void volverAlLoginLocal(BuildContext context) {
  ModoAppLocales.instancia.establecerLocal();
  final navigator = navigatorKeyLocales.currentState ?? Navigator.of(context);
  navigator.pushNamedAndRemoveUntil('/login', (_) => false);
}
