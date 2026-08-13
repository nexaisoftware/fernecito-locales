/// Login interno liviano para el flujo multi-cuenta.
///
/// Se abre desde el switcher ("+ Agregar cuenta") o como fallback de re-login
/// cuando una cuenta guardada venció. Antes de iniciar sesión snapshotea la
/// cuenta activa en el vault para no perderla; al entrar bien, el AuthGate
/// rutea al nuevo local (mismo camino de siempre).
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/auth_errors.dart';
import '../core/auth_redirect_locales.dart';
import '../core/constants.dart';
import '../core/recarga_cuenta_locales.dart';
import '../core/supabase_client.dart';
import '../core/vault_sesiones_locales.dart';
import 'locales_crear_cuenta.dart';

class LocalesLoginInterno extends StatefulWidget {
  const LocalesLoginInterno({
    super.key,
    this.emailSugerido,
    this.titulo = 'Agregar cuenta',
    this.subtitulo = 'Entrá con la cuenta de tu otro local',
  });

  /// Pre-llena el email (ej. re-login de una cuenta vencida).
  final String? emailSugerido;
  final String titulo;
  final String subtitulo;

  @override
  State<LocalesLoginInterno> createState() => _LocalesLoginInternoState();
}

class _LocalesLoginInternoState extends State<LocalesLoginInterno> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _contrasena = TextEditingController();

  bool _ocultar = true;
  bool _cargando = false;
  bool _cargandoGoogle = false;

  @override
  void initState() {
    super.initState();
    if (widget.emailSugerido != null && widget.emailSugerido!.trim().isNotEmpty) {
      _email.text = widget.emailSugerido!.trim();
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _contrasena.dispose();
    super.dispose();
  }

  /// Antes de cualquier login nuevo: guardar la sesión actual para no perderla
  /// (clave en web, donde el redirect de OAuth pisa la sesión).
  /// Si la activa ya no está en el vault (la acabamos de cerrar), NO re-agregar.
  Future<void> _preservarActual() async {
    try {
      final vault = VaultSesionesLocales();
      final uid = vault.uidActivo;
      if (uid == null) return;
      if (await vault.buscar(uid) == null) return;
      await vault.guardarActual();
    } catch (_) {/* no bloquear el login por esto */}
  }

  Future<void> _irCrearCuenta() async {
    await _preservarActual();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LocalesCrearCuenta(desdeMultiCuenta: true),
      ),
    );
  }

  Future<void> _entrarGoogle() async {
    if (_cargando || _cargandoGoogle) return;
    setState(() => _cargandoGoogle = true);
    await _preservarActual();
    try {
      await ServicioSupabase().cliente.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: authRedirectUrlLocales,
      );
      // En web redirige (esta pantalla se descarta); en nativo abre el browser
      // y el AuthGate rutea al volver.
    } catch (_) {
      if (mounted) {
        _mostrarError('No se pudo conectar con Google.\n\nProbá de nuevo en unos segundos.');
      }
    } finally {
      if (mounted) setState(() => _cargandoGoogle = false);
    }
  }

  Future<void> _entrarEmail() async {
    if (_cargando || _cargandoGoogle) return;
    final email = _email.text.trim();
    final pass = _contrasena.text;
    if (email.isEmpty || pass.isEmpty) {
      _mostrarError('Ingresá email y contraseña');
      return;
    }
    setState(() => _cargando = true);
    await _preservarActual();
    try {
      await ServicioSupabase().cliente.auth.signInWithPassword(
        email: email,
        password: pass,
      );
      // Snapshotear YA la nueva cuenta (el AuthGate también lo hace; esto
      // asegura que quede en el vault aunque el gate tarde).
      await VaultSesionesLocales().guardarActual();

      // Splash + remount completo (evita Home stale de la cuenta anterior).
      await recargarAppTrasCambioCuenta();
      // Éxito: no bajamos el loading (la ruta se destruye al navegar).
      return;
    } catch (e) {
      if (mounted) {
        final msg = TraductorErroresAuth.esCredencialesInvalidas(e)
            ? TraductorErroresAuth.mensajeLoginIncorrectoLocales()
            : TraductorErroresAuth.traducir(e);
        _mostrarError(msg);
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _mostrarError(String mensaje) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ColoresLocales.superficie,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Error',
            style: GoogleFonts.baloo2(color: ColoresLocales.textoOnFondoClaro, fontWeight: FontWeight.w800)),
        content: Text(mensaje,
            style: GoogleFonts.baloo2(color: ColoresLocales.textoSecundarioOnFondoClaro)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK', style: GoogleFonts.baloo2(color: ColoresLocales.violetaLogoMarca)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ocupado = _cargando || _cargandoGoogle;
    return Scaffold(
      backgroundColor: ColoresLocales.violetaLogoMarca,
      body: SafeArea(
        child: Column(
          children: [
            // Cabecera violeta con cerrar.
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: ocupado ? null : () => Navigator.of(context).maybePop(),
                    icon: const Icon(CupertinoIcons.xmark, color: Colors.white),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Image.asset(
              ColoresLocales.assetLogoMarca,
              width: 64,
              height: 64,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) =>
                  const Icon(CupertinoIcons.building_2_fill, size: 56, color: Colors.white),
            ),
            const SizedBox(height: 14),
            Text(
              widget.titulo,
              textAlign: TextAlign.center,
              style: GoogleFonts.baloo2(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                widget.subtitulo,
                textAlign: TextAlign.center,
                style: GoogleFonts.baloo2(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.82),
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: ColoresLocales.superficie,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 50,
                        child: OutlinedButton(
                          onPressed: ocupado ? null : _entrarGoogle,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ColoresLocales.textoOnFondoClaro,
                            backgroundColor: ColoresLocales.superficie,
                            side: BorderSide(color: ColoresLocales.bordeSuave),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _cargandoGoogle
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    FaIcon(FontAwesomeIcons.google, size: 18, color: ColoresLocales.textoOnFondoClaro),
                                    const SizedBox(width: 10),
                                    Text('Continuar con Google',
                                        style: GoogleFonts.baloo2(fontSize: 15, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(child: Divider(color: ColoresLocales.bordeSuave)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text('o con email',
                                style: GoogleFonts.baloo2(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: ColoresLocales.textoSecundarioOnFondoClaro,
                                )),
                          ),
                          Expanded(child: Divider(color: ColoresLocales.bordeSuave)),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _CampoLoginInterno(
                        controller: _email,
                        hint: 'Email',
                        prefixIcon: Icons.mail_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),
                      _CampoLoginInterno(
                        controller: _contrasena,
                        hint: 'Contraseña',
                        prefixIcon: Icons.lock_outline_rounded,
                        obscureText: _ocultar,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _cargando ? null : _entrarEmail(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _ocultar ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            color: ColoresLocales.textoSecundarioOnFondoClaro,
                            size: 22,
                          ),
                          onPressed: () => setState(() => _ocultar = !_ocultar),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: ocupado ? null : _entrarEmail,
                          style: FilledButton.styleFrom(
                            backgroundColor: ColoresLocales.violetaLogoMarca,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                          child: _cargando
                              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text('Entrar', style: GoogleFonts.baloo2(fontSize: 17, fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.center,
                        child: TextButton(
                          onPressed: ocupado ? null : () => Navigator.pushNamed(context, '/contrasena'),
                          child: Text('Olvidé mi contraseña',
                              style: GoogleFonts.baloo2(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: ColoresLocales.violetaLogoMarca,
                              )),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: ocupado ? null : _irCrearCuenta,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ColoresLocales.violetaLogoMarca,
                          side: BorderSide(
                            color: ColoresLocales.violetaLogoMarca.withValues(alpha: 0.35),
                          ),
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          'Crear cuenta de local',
                          style: GoogleFonts.baloo2(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CampoLoginInterno extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData prefixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Widget? suffixIcon;
  final ValueChanged<String>? onSubmitted;

  const _CampoLoginInterno({
    required this.controller,
    required this.hint,
    required this.prefixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.suffixIcon,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: GoogleFonts.baloo2(fontSize: 16, fontWeight: FontWeight.w600, color: ColoresLocales.textoOnFondoClaro),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.baloo2(fontSize: 16, fontWeight: FontWeight.w600, color: ColoresLocales.textoSecundarioOnFondoClaro),
        prefixIcon: Icon(prefixIcon, color: ColoresLocales.textoSecundarioOnFondoClaro, size: 22),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: ColoresLocales.rellenoInput,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: ColoresLocales.bordeSuave)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: ColoresLocales.violetaLogoMarca, width: 1.5)),
      ),
    );
  }
}
