library;

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/tema_app_locales.dart';
import 'tema_locales_scope.dart';

/// Fondo del home — negro plano en oscuro, degradado lavanda en claro.
class FondoDegradadoLocales extends StatelessWidget {
  const FondoDegradadoLocales({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final oscuro = TemaAppLocales.instancia.esOscuro;
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: oscuro
                ? BoxDecoration(color: ColoresLocales.fondoClaro)
                : BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: ColoresLocales.degradadoHome,
                      stops: const [0.0, 0.22, 0.55, 1.0],
                    ),
                  ),
          ),
        ),
        child,
      ],
    );
  }
}
