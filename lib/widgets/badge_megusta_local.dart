library;

import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants.dart';

const _rojoMegusta = Color(0xFFE91E63);
const _navBlurSigma = 18.0;

String _formatearCantidadMegusta(int cantidad) {
  if (cantidad >= 1000000) {
    final m = cantidad / 1000000;
    return m >= 10
        ? '${m.round()}M'
        : '${m.toStringAsFixed(1).replaceAll('.0', '')}M';
  }
  if (cantidad >= 1000) {
    final k = cantidad / 1000;
    return k >= 10
        ? '${k.round()}K'
        : '${k.toStringAsFixed(1).replaceAll('.0', '')}K';
  }
  return '$cantidad';
}

class _PillGlassMegusta extends StatelessWidget {
  const _PillGlassMegusta({
    required this.activo,
    required this.child,
    this.compacto = false,
  });

  final bool activo;
  final Widget child;
  final bool compacto;

  BoxDecoration _decoracionPill(bool activo) {
    final nav = ColoresLocales.barraNav;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: activo
            ? [
                _rojoMegusta.withValues(alpha: 0.34),
                _rojoMegusta.withValues(alpha: 0.48),
              ]
            : [
                nav.withValues(alpha: 0.72),
                nav.withValues(alpha: 0.92),
              ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: _navBlurSigma,
          sigmaY: _navBlurSigma,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: compacto ? 10 : 12,
            vertical: compacto ? 6 : 7,
          ),
          decoration: _decoracionPill(activo),
          child: child,
        ),
      ),
    );
  }
}

Color _colorContenidoMegusta({required bool activo, required bool esIcono}) {
  if (activo && esIcono) return _rojoMegusta;
  if (activo) return Colors.white;
  return ColoresLocales.textoSecundario;
}

TextStyle _estiloTextoMegusta({
  required bool activo,
  required double fontSize,
  FontWeight fontWeight = FontWeight.w800,
}) {
  return GoogleFonts.baloo2(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: _colorContenidoMegusta(activo: activo, esIcono: false),
    height: 1,
  );
}

/// Contador de me gusta sobre el degradado (solo lectura — Mi local).
class BadgeMegustaLocalLectura extends StatelessWidget {
  const BadgeMegustaLocalLectura({
    super.key,
    required this.cantidad,
    this.compacto = false,
  });

  final int cantidad;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    const activo = false;
    final iconSize = compacto ? 15.0 : 19.0;
    final textoCantidad = _formatearCantidadMegusta(cantidad);

    return _PillGlassMegusta(
      activo: activo,
      compacto: compacto,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.heart_fill,
            size: iconSize,
            color: _rojoMegusta,
          ),
          if (cantidad > 0) ...[
            const SizedBox(width: 3),
            Text(
              textoCantidad,
              style: _estiloTextoMegusta(
                activo: activo,
                fontSize: compacto ? 13.5 : 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
          const SizedBox(width: 6),
          Text(
            'Tus me gusta',
            style: _estiloTextoMegusta(
              activo: activo,
              fontSize: compacto ? 11.5 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
