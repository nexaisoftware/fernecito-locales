/// Diálogo de pre-permiso push: explica el beneficio y dispara el modal del OS
/// solo cuando el usuario toca «Activar» (requerido en PWA y buena práctica en Android).
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import '../core/servicio_push.dart';

class DialogPermisoPushLocales {
  DialogPermisoPushLocales._();

  static bool _mostrando = false;
  static bool _mostradoEstaSesion = false;

  /// Muestra el diálogo una vez por sesión si push está soportado y aún no hay permiso.
  static Future<void> mostrarSiCorresponde(BuildContext context) async {
    if (_mostrando || _mostradoEstaSesion) return;
    if (!ServicioPush.instancia.soportado) return;
    if (Supabase.instance.client.auth.currentSession == null) return;
    if (await ServicioPush.instancia.tienePermiso()) return;

    _mostradoEstaSesion = true;
    if (!context.mounted) return;

    _mostrando = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DialogPermisoPush(
        onActivar: () async {
          Navigator.of(ctx).pop();
          await ServicioPush.instancia.registrarParaUsuario();
        },
      ),
    );
    _mostrando = false;
  }
}

class _DialogPermisoPush extends StatelessWidget {
  const _DialogPermisoPush({required this.onActivar});

  final Future<void> Function() onActivar;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ColoresLocales.superficie,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(
            CupertinoIcons.bell_fill,
            color: ColoresLocales.violetaLogoMarca,
            size: 26,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Activá las notificaciones',
              style: GoogleFonts.baloo2(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: ColoresLocales.textoOnFondoClaro,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        'Te avisamos al instante sobre reservas, pagos, eventos importantes '
        'y novedades de tu local. Sin permiso, solo ves alertas dentro de la app.',
        style: GoogleFonts.baloo2(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: ColoresLocales.textoSecundarioOnFondoClaro,
          height: 1.4,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Ahora no',
            style: GoogleFonts.baloo2(
              fontWeight: FontWeight.w700,
              color: ColoresLocales.textoSecundarioOnFondoClaro,
            ),
          ),
        ),
        FilledButton(
          onPressed: () => onActivar(),
          style: FilledButton.styleFrom(
            backgroundColor: ColoresLocales.violetaLogoMarca,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            'Activar notificaciones',
            style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}
