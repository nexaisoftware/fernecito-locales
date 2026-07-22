/// Recorte circular web-safe (InteractiveViewer + overlay Path.combine + captura
/// por RepaintBoundary). Reemplaza al paquete profile_image_cropper que no
/// renderiza el recorte ni los gestos en Flutter web/PWA.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';

/// Bottom sheet de recorte circular de logo (mismo flujo que crear perfil).
/// Devuelve los bytes PNG recortados o `null` si cancela.
Future<Uint8List?> mostrarRecorteLogoSheet(
  BuildContext context,
  Uint8List bytes,
) {
  final boundaryKey = GlobalKey();
  var recortando = false;
  return showModalBottomSheet<Uint8List>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setModal) {
        final bottom = MediaQuery.paddingOf(context).bottom;
        return DraggableScrollableSheet(
          initialChildSize: 0.78,
          minChildSize: 0.55,
          maxChildSize: 0.95,
          builder: (_, __) => Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1B1430),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Encuadrá tu logo',
                              style: GoogleFonts.baloo2(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Mové y hacé zoom. Así se verá en tu perfil.',
                              style: GoogleFonts.baloo2(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        onPressed:
                            recortando ? null : () => Navigator.pop(ctx),
                        child: Text(
                          'Cancelar',
                          style: GoogleFonts.baloo2(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      CupertinoButton(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        onPressed: recortando
                            ? null
                            : () async {
                                setModal(() => recortando = true);
                                final result =
                                    await capturarRecorteBoundary(boundaryKey);
                                if (!ctx.mounted) return;
                                Navigator.pop(ctx, result);
                              },
                        child: recortando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF4A1A8A),
                                ),
                              )
                            : Text(
                                'Listo',
                                style: GoogleFonts.baloo2(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF4A1A8A),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
                    child: RecorteAreaCircular(
                      boundaryKey: boundaryKey,
                      bytes: bytes,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Área cuadrada con la imagen (pan/zoom) y guía circular. `boundaryKey` debe
/// pasarse a [capturarRecorteBoundary] al confirmar. Solo la imagen se captura.
class RecorteAreaCircular extends StatelessWidget {
  const RecorteAreaCircular({
    super.key,
    required this.boundaryKey,
    required this.bytes,
  });

  final GlobalKey boundaryKey;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final lado = constraints.biggest.shortestSide;
        return Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: lado,
              height: lado,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Color(0xFF141414)),
                  RepaintBoundary(
                    key: boundaryKey,
                    child: InteractiveViewer(
                      clipBehavior: Clip.hardEdge,
                      minScale: 1.0,
                      maxScale: 5.0,
                      child: Image.memory(
                        bytes,
                        width: lado,
                        height: lado,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: CustomPaint(
                      size: Size(lado, lado),
                      painter: _GuiaCircular(),
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
}

/// Captura el contenido del RepaintBoundary (imagen encuadrada) como PNG.
Future<Uint8List?> capturarRecorteBoundary(GlobalKey boundaryKey) async {
  await WidgetsBinding.instance.endOfFrame;
  final obj = boundaryKey.currentContext?.findRenderObject();
  if (obj is! RenderRepaintBoundary) return null;
  final ui.Image img = await obj.toImage(pixelRatio: 3.0);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return bytes?.buffer.asUint8List();
}

class _GuiaCircular extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final centro = Offset(size.width / 2, size.height / 2);
    final radio = size.shortestSide / 2;
    final circulo = Path()
      ..addOval(Rect.fromCircle(center: centro, radius: radio));
    final full = Path()..addRect(Offset.zero & size);
    final fuera = Path.combine(PathOperation.difference, full, circulo);
    canvas.drawPath(fuera, Paint()..color = Colors.black.withValues(alpha: 0.55));
    canvas.drawCircle(
      centro,
      radio,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(covariant _GuiaCircular oldDelegate) => false;
}
