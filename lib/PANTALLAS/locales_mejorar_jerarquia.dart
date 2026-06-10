library;

import 'package:flutter/material.dart';
import '../widgets/tema_locales_scope.dart';
import 'locales_posicionamiento.dart';

/// Redirige automáticamente a [LocalesPosicionamiento] en el tab "Sin posición".
/// Se mantiene por compatibilidad con la ruta /mejorar_jerarquia en main.dart.
class LocalesMejorarJerarquia extends StatelessWidget {
  const LocalesMejorarJerarquia({super.key});

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return const LocalesPosicionamiento(tabInicial: 1);
  }
}
