/// Plantilla para pantallas en desarrollo — "Próximamente..."
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants.dart';
import '../widgets/tema_locales_scope.dart';

Widget buildProximamente(String titulo) {
  return Builder(
    builder: (context) {
      TemaLocalesScope.of(context);
      return Scaffold(
        backgroundColor: ColoresLocales.fondoClaro,
        appBar: AppBar(
          backgroundColor: ColoresLocales.fondoClaro,
          elevation: 0,
          surfaceTintColor: ColoresLocales.fondoClaro,
          centerTitle: true,
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
            child: Icon(CupertinoIcons.chevron_back, color: ColoresLocales.acentoVioleta),
          ),
          title: Text(
            titulo,
            style: GoogleFonts.baloo2(
              fontWeight: FontWeight.w900,
              color: ColoresLocales.acentoVioleta,
            ),
          ),
        ),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: ColoresLocales.acentoVioleta.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.construction_rounded,
                    size: 52,
                    color: ColoresLocales.acentoVioleta,
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  titulo,
                  style: GoogleFonts.baloo2(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: ColoresLocales.textoOnFondoClaro,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Próximamente...',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.baloo2(
                    fontSize: 14,
                    color: ColoresLocales.textoSecundarioOnFondoClaro,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
