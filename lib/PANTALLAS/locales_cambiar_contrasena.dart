/// Cambiar contraseña (logueado) — estilo Fernecito Locales con tema oscuro/claro.
/// Pide la actual → revalida con signInWithPassword → setea la nueva.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import '../widgets/tema_locales_scope.dart';

class LocalesCambiarContrasena extends StatefulWidget {
  const LocalesCambiarContrasena({super.key});

  @override
  State<LocalesCambiarContrasena> createState() => _LocalesCambiarContrasenaState();
}

class _LocalesCambiarContrasenaState extends State<LocalesCambiarContrasena> {
  final _actual = TextEditingController();
  final _nueva = TextEditingController();
  final _repetir = TextEditingController();
  bool _ocultarActual = true;
  bool _ocultarNueva = true;
  bool _ocultarRepetir = true;
  bool _procesando = false;

  @override
  void dispose() {
    _actual.dispose();
    _nueva.dispose();
    _repetir.dispose();
    super.dispose();
  }

  bool _esValida(String s) =>
      s.length >= 8 &&
      RegExp(r'[a-zA-Z]').hasMatch(s) &&
      RegExp(r'[0-9]').hasMatch(s);

  Future<void> _cambiar() async {
    if (_procesando) return;
    HapticFeedback.selectionClick();

    final actual = _actual.text;
    final nueva = _nueva.text;
    final repetir = _repetir.text;

    if (actual.isEmpty || nueva.isEmpty || repetir.isEmpty) {
      _alert('Completá los tres campos.');
      return;
    }
    if (!_esValida(nueva)) {
      _alert('La nueva contraseña debe tener mínimo 8 caracteres,\n'
          'al menos una letra y un número.');
      return;
    }
    if (nueva != repetir) {
      _alert('Las contraseñas nuevas no coinciden.');
      return;
    }
    if (nueva == actual) {
      _alert('La nueva contraseña tiene que ser distinta a la actual.');
      return;
    }

    final sb = Supabase.instance.client;
    final email = sb.auth.currentUser?.email;
    if (email == null) {
      _alert('No pudimos identificar tu sesión. Volvé a entrar.');
      return;
    }

    setState(() => _procesando = true);
    try {
      await sb.auth.signInWithPassword(email: email, password: actual);
      await sb.auth.updateUser(UserAttributes(password: nueva));

      if (!mounted) return;
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Listo, tu contraseña fue actualizada.',
              style: GoogleFonts.baloo2()),
          backgroundColor: const Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.of(context).pop();
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase().contains('credentials')
          ? 'La contraseña actual es incorrecta.'
          : 'No pudimos cambiar la contraseña: ${e.message}';
      _alert(msg);
    } catch (e) {
      _alert('Error inesperado: $e');
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  void _alert(String msg) {
    HapticFeedback.mediumImpact();
    final oscuro = TemaLocalesScope.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: oscuro ? const Color(0xFF1A1A1A) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'No se pudo cambiar',
          style: GoogleFonts.baloo2(
            fontWeight: FontWeight.w900,
            color: ColoresLocales.textoOnFondoClaro,
          ),
        ),
        content: Text(
          msg,
          style: GoogleFonts.baloo2(
              color: ColoresLocales.textoSecundarioOnFondoClaro),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK',
                style: GoogleFonts.baloo2(
                    color: ColoresLocales.violetaLogoMarca,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Suscribirse al notifier de tema (rebuild en toggle oscuro/claro).
    TemaLocalesScope.of(context);

    return Scaffold(
      backgroundColor: ColoresLocales.fondoClaro,
      appBar: AppBar(
        backgroundColor: ColoresLocales.superficie,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: ColoresLocales.textoOnFondoClaro),
        title: Text(
          'Cambiar contraseña',
          style: GoogleFonts.baloo2(
            fontWeight: FontWeight.w900,
            color: ColoresLocales.textoOnFondoClaro,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Hero ────────────────────────────────────────────────
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: ColoresLocales.violetaLogoMarca
                            .withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.lock_reset,
                        size: 48,
                        color: ColoresLocales.violetaLogoMarca,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Actualizá tu contraseña',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.baloo2(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: ColoresLocales.textoOnFondoClaro,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tu sesión queda activa.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.baloo2(
                      fontSize: 13.5,
                      color: ColoresLocales.textoSecundarioOnFondoClaro,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Campos ──────────────────────────────────────────────
                  _CampoPass(
                    label: 'Contraseña actual',
                    controller: _actual,
                    ocultar: _ocultarActual,
                    onToggle: () =>
                        setState(() => _ocultarActual = !_ocultarActual),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  _CampoPass(
                    label: 'Nueva contraseña',
                    controller: _nueva,
                    ocultar: _ocultarNueva,
                    onToggle: () =>
                        setState(() => _ocultarNueva = !_ocultarNueva),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  _CampoPass(
                    label: 'Repetir nueva contraseña',
                    controller: _repetir,
                    ocultar: _ocultarRepetir,
                    onToggle: () =>
                        setState(() => _ocultarRepetir = !_ocultarRepetir),
                  ),

                  const SizedBox(height: 14),
                  _ReglasContrasena(valor: _nueva.text),

                  const SizedBox(height: 24),

                  // ── CTA ────────────────────────────────────────────────
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _procesando ? null : _cambiar,
                      style: FilledButton.styleFrom(
                        backgroundColor: ColoresLocales.violetaLogoMarca,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            ColoresLocales.violetaLogoMarca.withValues(alpha: 0.6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: _procesando
                          ? const SizedBox(
                              height: 22, width: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(
                              'Cambiar contraseña',
                              style: GoogleFonts.baloo2(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ── Helper ─────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: ColoresLocales.superficie,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: ColoresLocales.violetaLogoMarca
                            .withValues(alpha: 0.18),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            size: 18,
                            color: ColoresLocales.violetaLogoMarca),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '¿Olvidaste la actual? Cerrá sesión y desde el login tocá "Olvidé mi contraseña" o escribinos por soporte.',
                            style: GoogleFonts.baloo2(
                              fontSize: 12.5,
                              color: ColoresLocales.textoSecundarioOnFondoClaro,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Campo de password — mismo estilo que el _CampoLogin de locales_login.dart
// ═══════════════════════════════════════════════════════════════════════════
class _CampoPass extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool ocultar;
  final VoidCallback onToggle;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  const _CampoPass({
    required this.label,
    required this.controller,
    required this.ocultar,
    required this.onToggle,
    this.onChanged,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final oscuro = TemaLocalesScope.of(context);
    final fillColor = oscuro
        ? ColoresLocales.superficieElevada
        : const Color(0xFFF3F4F6);
    final borderColor = oscuro
        ? ColoresLocales.superficieElevada
        : const Color(0xFFE5E7EB);
    final hintColor = ColoresLocales.textoSecundarioOnFondoClaro;
    final textoColor = ColoresLocales.textoOnFondoClaro;

    return TextField(
      controller: controller,
      obscureText: ocultar,
      autofocus: autofocus,
      onChanged: onChanged,
      style: GoogleFonts.baloo2(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: textoColor,
      ),
      decoration: InputDecoration(
        hintText: label,
        hintStyle: GoogleFonts.baloo2(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: hintColor,
        ),
        prefixIcon: Icon(Icons.lock_outline, color: hintColor, size: 22),
        suffixIcon: IconButton(
          icon: Icon(
            ocultar
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: hintColor,
            size: 22,
          ),
          onPressed: onToggle,
        ),
        filled: true,
        fillColor: fillColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: ColoresLocales.violetaLogoMarca,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Reglas de validación en vivo
// ═══════════════════════════════════════════════════════════════════════════
class _ReglasContrasena extends StatelessWidget {
  final String valor;
  const _ReglasContrasena({required this.valor});

  @override
  Widget build(BuildContext context) {
    final largo = valor.length >= 8;
    final letra = RegExp(r'[a-zA-Z]').hasMatch(valor);
    final num = RegExp(r'[0-9]').hasMatch(valor);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _regla(context, 'Mínimo 8 caracteres', largo),
          _regla(context, 'Al menos 1 letra', letra),
          _regla(context, 'Al menos 1 número', num),
        ],
      ),
    );
  }

  Widget _regla(BuildContext context, String txt, bool ok) {
    final okColor = const Color(0xFF22C55E);
    final neutroColor = ColoresLocales.textoSecundarioOnFondoClaro;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: ok ? okColor : neutroColor,
          ),
          const SizedBox(width: 8),
          Text(
            txt,
            style: GoogleFonts.baloo2(
              fontSize: 12.5,
              color: ok ? okColor : neutroColor,
              fontWeight: ok ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
