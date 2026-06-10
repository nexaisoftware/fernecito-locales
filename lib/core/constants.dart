/// Constantes visuales Fernecito Locales — misma estética que fernecito_frontend.
library;

import 'package:flutter/material.dart';
import 'tema_app_locales.dart';

class ColoresLocales {
  static bool get _oscuro => TemaAppLocales.instancia.esOscuro;

  /// Verde Fernecito (mismo que fernecito_frontend).
  static Color get verdeFernet =>
      _oscuro ? const Color(0xFF4ADE80) : const Color(0xFF1DB954);

  /// Fondo principal oscuro (login, splash).
  static Color get fondoPrincipal =>
      _oscuro ? const Color(0xFF000000) : const Color(0xFF121212);

  /// Fondo de pantallas (home, listas, métricas…). Negro OLED en oscuro.
  static Color get fondoClaro =>
      _oscuro ? const Color(0xFF000000) : const Color(0xFFE8E8E8);

  /// Tarjetas, sheets, app bars.
  static Color get superficie =>
      _oscuro ? const Color(0xFF1A1A1A) : Colors.white;

  /// Superficie un poco más elevada (inputs, chips).
  static Color get superficieElevada =>
      _oscuro ? const Color(0xFF242424) : const Color(0xFFF5F5F5);

  /// Paneles secundarios (menús en perfil, overlays). Claro en modo claro.
  static Color get fondoSuperficie =>
      _oscuro ? const Color(0xFF1A1A1A) : const Color(0xFFF3F4F6);

  static Color get grisClaro =>
      _oscuro ? const Color(0xFF2E2E2E) : const Color(0xFF2A2A2A);

  static Color get grisClaroFondo =>
      _oscuro ? const Color(0xFF333333) : const Color(0xFFD0D0D0);

  static Color get textoPrincipal => Colors.white;

  static Color get textoSecundario =>
      _oscuro ? const Color(0xFF888888) : const Color(0xFFAAAAAA);

  /// Texto principal sobre fondos claros / cards del dashboard.
  static Color get textoOnFondoClaro =>
      _oscuro ? const Color(0xFFE8E8E8) : const Color(0xFF1A1A1A);

  static Color get textoSecundarioOnFondoClaro =>
      _oscuro ? const Color(0xFF888888) : const Color(0xFF555555);

  /// Violeta acento — más lavado en oscuro (texto sobre fondos grises).
  static Color get acentoVioleta =>
      _oscuro ? const Color(0xFFC4B5FD) : const Color(0xFF7C3AED);

  /// Violeta de marca fijo — badges sobre fondos amarillos/de color (no aclara en oscuro).
  static const acentoVioletaMarca = Color(0xFF7C3AED);

  /// Títulos en cards del dashboard (contraste estable en claro y oscuro).
  static const tituloAcento = acentoVioletaMarca;

  /// Texto sobre fondos mostaza/amarillo (badges «Nuevo», verificado).
  static const textoSobreMostaza = Color(0xFF3B1578);

  /// Violeta muestreado de [localeslogo.png] — login, splash y favicon.
  static const violetaLogoMarca = Color(0xFF742ED1);
  static const assetLogoMarca = 'assets/imagenes/localeslogo.png';

  /// Mostaza original del badge verificado (no aclara en oscuro).
  static const mostazaBadge = Color(0xFFD9B44A);

  /// Jerarquías posicionamiento — colores fijos en ambos modos.
  static const jerarquiaRecomendado = Color(0xFF7C3AED);
  static const jerarquiaTop = Color(0xFFD97706);
  static const jerarquiaUltra = Color(0xFFEC4899);

  /// Texto sobre botones violeta/verdes (siempre claro en claro; en oscuro depende del fondo).
  static const textoEnBoton = Colors.white;

  /// Fondo botón violeta — lavado en oscuro, marca en claro.
  static Color get botonVioletaFondo =>
      _oscuro ? const Color(0xFFC4B5FD) : acentoVioletaMarca;

  /// Texto sobre botón violeta.
  static Color get botonVioletaTexto =>
      _oscuro ? const Color(0xFF1A1A1A) : textoEnBoton;

  /// Texto legible sobre un fondo de botón sólido.
  static Color textoEnBotonSobre(Color fondoBoton) {
    if (_oscuro && fondoBoton == botonVioletaFondo) {
      return botonVioletaTexto;
    }
    return textoEnBoton;
  }

  /// Barra inferior del dashboard (plan + cupos).
  static Color get barraDashboard =>
      _oscuro ? const Color(0xFF1A1A1A) : const Color(0xFFF8F5FF);

  /// Nav bar inferior.
  static Color get barraNav => superficie;

  /// Borde sutil de avatar / chips.
  static Color get bordeSuave =>
      _oscuro ? const Color(0xFF333333) : Colors.grey.shade300;

  /// Degradado de fondo del home — plano negro en oscuro (estética staff).
  static List<Color> get degradadoHome => _oscuro
      ? const [
          Color(0xFF000000),
          Color(0xFF000000),
          Color(0xFF000000),
          Color(0xFF000000),
        ]
      : const [
          Color(0xFFA78BDA),
          Color(0xFFEDE8F7),
          Color(0xFFF5F2FA),
          Color(0xFFFFFFFF),
        ];

  /// Card exclusiva Flyer IA en dashboard.
  static List<Color> get degradadoCardExclusivo => _oscuro
      ? const [Color(0xFF1A1A1A), Color(0xFF1A1A1A)]
      : const [Color(0xFFF3EDFF), Color(0xFFFFF8E8)];

  static Color get mostazaDestacado =>
      _oscuro ? const Color(0xFFE8C96A) : const Color(0xFFD9B44A);

  /// Fondo lavanda suave de cards / placeholders de flyer.
  static Color get cardLavanda =>
      _oscuro ? const Color(0xFF1E1E1E) : const Color(0xFFF3F0FF);

  /// Inputs, chips y paneles secundarios.
  static Color get cardInput =>
      _oscuro ? const Color(0xFF1A1A1A) : const Color(0xFFF8F7FF);

  /// Divisores y bordes muy suaves.
  static Color get separador =>
      _oscuro ? const Color(0xFF2A2A2A) : const Color(0xFFEEEEEE);

  /// Sombra de cards — apagada en oscuro (minimal).
  static Color get sombraCard =>
      _oscuro ? Colors.transparent : Colors.black.withOpacity(0.04);

  /// Cards alternativas (flyer IA, bloques del formulario).
  static Color get cardAlt =>
      _oscuro ? const Color(0xFF1E1E1E) : const Color(0xFFF7F4FF);

  /// Fondo general de formularios largos.
  static Color get fondoFormulario =>
      _oscuro ? const Color(0xFF000000) : const Color(0xFFFBFAFF);

  /// Chips / tabs inactivos sobre fondo claro.
  static Color get chipInactivo => superficie;

  /// Relleno de TextField / dropdown.
  static Color get rellenoInput => superficieElevada;

  /// Glow violeta (login, CTAs) — desactivado en oscuro.
  static List<BoxShadow> get glowAcento => _oscuro
      ? const <BoxShadow>[]
      : [
          BoxShadow(
            color: acentoVioleta.withOpacity(0.28),
            blurRadius: 14,
            offset: const Offset(0, 2),
          ),
        ];

  /// Sombras de cards del dashboard — ninguna en oscuro.
  static List<BoxShadow> sombrasCard({
    bool exclusivo = false,
    Color? acento,
  }) {
    if (_oscuro) return const <BoxShadow>[];
    final c = acento ?? acentoVioleta;
    return [
      BoxShadow(
        color: c.withOpacity(exclusivo ? 0.1 : 0.06),
        blurRadius: exclusivo ? 12 : 8,
        offset: const Offset(0, 2),
      ),
    ];
  }

  /// Borde de card — gris sutil en oscuro, violeta tenue en claro.
  static Color bordeCard({bool exclusivo = false}) => _oscuro
      ? bordeSuave
      : (exclusivo
          ? mostazaDestacado.withOpacity(0.38)
          : acentoVioleta.withOpacity(0.16));

  /// Decoración estándar de cards (dashboard y pantallas similares).
  static BoxDecoration decoracionCard({
    Color? color,
    double radius = 20,
    bool exclusivo = false,
  }) {
    final bg = color ?? superficie;
    if (exclusivo && !_oscuro) {
      return BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: degradadoCardExclusivo,
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: bordeCard(exclusivo: true), width: 1.2),
        boxShadow: sombrasCard(exclusivo: true),
      );
    }
    return BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: bordeCard(exclusivo: exclusivo)),
      boxShadow: sombrasCard(exclusivo: exclusivo),
    );
  }
}

/// Paleta semántica para suscripción/posicionamiento.
class ColoresFeaturesLocales {
  static Color get verificado => ColoresLocales.acentoVioletaMarca;
  static const flyersIa = Color(0xFF16A34A);
  static const recomendadoFernecito = Color(0xFF0891B2);
  static const topCartelera = Color(0xFFD97706);
  static const topUltra = Color(0xFFEC4899);
}
