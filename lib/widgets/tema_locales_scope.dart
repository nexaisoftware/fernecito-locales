library;

import 'package:flutter/material.dart';

import '../core/tema_app_locales.dart';

/// Propaga cambios de tema a todo el subtree (como [ValueListenableBuilder] global).
class TemaLocalesScope extends InheritedNotifier<ValueNotifier<bool>> {
  const TemaLocalesScope({
    super.key,
    required ValueNotifier<bool> notifier,
    required super.child,
  }) : super(notifier: notifier);

  /// Registra dependencia y devuelve si el modo oscuro está activo.
  static bool of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TemaLocalesScope>();
    return scope?.notifier?.value ?? TemaAppLocales.instancia.esOscuro;
  }
}
