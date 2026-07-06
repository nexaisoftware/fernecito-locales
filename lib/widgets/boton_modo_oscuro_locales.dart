library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/tema_app_locales.dart';
import 'tema_locales_scope.dart';

/// Toggle claro/oscuro — mismo control que en el dashboard de locales.
class BotonModoOscuroLocales extends StatelessWidget {
  const BotonModoOscuroLocales({super.key});

  @override
  Widget build(BuildContext context) {
    final oscuro = TemaLocalesScope.of(context);
    return Semantics(
      button: true,
      label: oscuro
          ? 'Modo oscuro activo. Tocá para modo claro'
          : 'Modo claro activo. Tocá para modo oscuro',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: TemaAppLocales.instancia.toggle,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Center(
              child: Icon(
                oscuro ? CupertinoIcons.sun_max_fill : CupertinoIcons.moon_fill,
                size: 20,
                color: ColoresLocales.acentoVioleta,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
