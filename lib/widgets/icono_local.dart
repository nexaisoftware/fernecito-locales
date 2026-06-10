import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Ícono de local/tienda (frente de comercio) — reemplaza edificios genéricos.
class IconoLocal extends StatelessWidget {
  const IconoLocal({
    super.key,
    this.size = 22,
    this.color,
  });

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return FaIcon(
      FontAwesomeIcons.store,
      size: size,
      color: color,
    );
  }
}
