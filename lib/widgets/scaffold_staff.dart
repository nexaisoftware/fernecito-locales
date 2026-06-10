library;

import 'package:flutter/material.dart';

import '../core/colores_staff.dart';
import 'fondo_degradado_locales.dart';
import 'tema_locales_scope.dart';

/// AppBar transparente — el fondo del [ScaffoldStaff] se ve de punta a punta.
PreferredSizeWidget appBarStaff({
  Widget? title,
  Widget? leading,
  List<Widget>? actions,
  bool centerTitle = false,
  double toolbarHeight = kToolbarHeight,
}) {
  return AppBar(
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    toolbarHeight: toolbarHeight,
    centerTitle: centerTitle,
    leading: leading,
    title: title,
    actions: actions,
  );
}

double insetSuperiorStaff(
  BuildContext context, {
  double toolbarHeight = kToolbarHeight,
}) =>
    MediaQuery.of(context).padding.top + toolbarHeight;

/// Scaffold unificado del flujo staff — AppBar siempre transparente.
class ScaffoldStaff extends StatelessWidget {
  const ScaffoldStaff({
    super.key,
    this.appBar,
    required this.body,
    this.conDegradado = false,
    this.fondo,
    this.toolbarHeight = kToolbarHeight,
    this.safeAreaBottom = false,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final bool conDegradado;
  final Color? fondo;
  final double toolbarHeight;
  final bool safeAreaBottom;

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final bg = fondo ?? ColoresStaff.fondo;
    final inset = appBar != null
        ? insetSuperiorStaff(context, toolbarHeight: toolbarHeight)
        : 0.0;

    Widget contenido = Padding(
      padding: EdgeInsets.only(top: inset),
      child: body,
    );

    if (conDegradado) {
      contenido = FondoDegradadoLocales(child: contenido);
    }

    if (safeAreaBottom) {
      contenido = SafeArea(top: false, child: contenido);
    }

    return Scaffold(
      backgroundColor: conDegradado ? Colors.transparent : bg,
      extendBodyBehindAppBar: appBar != null,
      appBar: appBar,
      body: contenido,
    );
  }
}
