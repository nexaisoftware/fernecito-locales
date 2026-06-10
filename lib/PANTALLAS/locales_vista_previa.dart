library;

import 'package:flutter/material.dart';
import '../widgets/tema_locales_scope.dart';
import 'locales_vista_previa_v2.dart';

class LocalesVistaPrevia extends StatelessWidget {
  final Map<String, dynamic> evento;
  const LocalesVistaPrevia({super.key, required this.evento});

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return LocalesVistaPreviaV2(evento: evento);
  }
}


