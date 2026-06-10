library;

import 'package:flutter/material.dart';

import 'auth_gate_locales.dart';

/// Navegación segura usando siempre el [Navigator] raíz de la app.
class NavegacionLocales {
  NavegacionLocales._();

  static NavigatorState? get _nav => navigatorKeyLocales.currentState;

  static Future<T?>? pushNamed<T extends Object?>(
    String route, {
    Object? arguments,
  }) {
    return _nav?.pushNamed<T>(route, arguments: arguments);
  }

  static Future<T?>? pushReplacementNamed<T extends Object?, TO extends Object?>(
    String route, {
    Object? arguments,
    TO? result,
  }) {
    return _nav?.pushReplacementNamed<T, TO>(route, arguments: arguments, result: result);
  }

  static void pop<T extends Object?>([T? result]) {
    final nav = _nav;
    if (nav != null && nav.canPop()) {
      nav.pop(result);
    }
  }

  static void popUntilHome() {
    _nav?.popUntil((route) => route.isFirst);
  }

  static Future<void> irASuscripciones({int? pestana}) async {
    await _nav?.pushNamed(
      '/administrar_subscripciones',
      arguments: pestana,
    );
  }

  static Future<void> irAComprasPagos(String plan) async {
    await _nav?.pushNamed('/compras_pagos', arguments: plan);
  }

  /// Botón atrás seguro: pop si hay historial; si no, vuelve al home.
  static void volver(BuildContext context) {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    _nav?.pushReplacementNamed('/home');
  }

  /// Tras enviar comprobante: cierra éxito y deja suscripciones en el stack.
  static void exitoComprobanteVerSuscripcion(BuildContext context) {
    Navigator.of(context).pop(); // pantalla éxito
    final nav = _nav;
    if (nav == null) return;
    nav.pushReplacementNamed('/administrar_subscripciones');
  }

  /// Tras enviar comprobante: cierra éxito y vuelve al dashboard.
  static void exitoComprobanteIrHome(BuildContext context) {
    Navigator.of(context).pop(); // pantalla éxito
    popUntilHome();
  }
}
