library;

import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';

/// Contador de me gusta sobre el degradado (solo lectura — Mi local).
class BadgeMegustaLocalLectura extends StatelessWidget {
  const BadgeMegustaLocalLectura({
    super.key,
    required this.cantidad,
    this.compacto = false,
  });

  final int cantidad;
  final bool compacto;

  String get _textoCantidad {
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

  TextStyle _textoStyle({required double fontSize}) {
    return GoogleFonts.baloo2(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      color: CupertinoColors.white,
      height: 1,
      shadows: [
        Shadow(
          color: CupertinoColors.black.withValues(alpha: 0.72),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const colorActivo = Color(0xFFE91E63);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.heart_fill,
                size: compacto ? 27 : 31,
                color: colorActivo,
                shadows: [
                  Shadow(
                    color: CupertinoColors.black.withValues(alpha: 0.55),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              if (cantidad > 0) ...[
                const SizedBox(width: 6),
                Text(_textoCantidad, style: _textoStyle(fontSize: 18)),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text('Tus me gusta', style: _textoStyle(fontSize: 11.5)),
        ],
      ),
    );
  }
}
