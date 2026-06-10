library;

import 'package:flutter/foundation.dart';

/// Callback registrado por [LocalesHome] para cambiar al tab Posición
/// y resaltar la card del evento indicado.
class NavegacionPosicionamiento {
  static void Function(String idEvento)? _ir;
  static final Set<VoidCallback> _listenersActualizacion = <VoidCallback>{};

  static void registrar(void Function(String idEvento)? fn) {
    _ir = fn;
  }

  static void irAEvento(String idEvento) {
    _ir?.call(idEvento);
  }

  static bool get estaRegistrado => _ir != null;

  static void registrarActualizacion(VoidCallback fn) {
    _listenersActualizacion.add(fn);
  }

  static void desregistrarActualizacion(VoidCallback fn) {
    _listenersActualizacion.remove(fn);
  }

  static void notificarActualizacion() {
    final listeners = List<VoidCallback>.from(_listenersActualizacion);
    for (final listener in listeners) {
      listener();
    }
  }
}
