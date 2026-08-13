/// Pantalla crear cuenta Fernecito Locales — Supabase Auth signUp.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/auth_errors.dart';
import '../core/auth_redirect_locales.dart';
import '../core/colores_onboarding_locales.dart';
import '../core/constants.dart';
import '../core/recarga_cuenta_locales.dart';
import '../core/supabase_client.dart';
import '../core/vault_sesiones_locales.dart';
import 'locales_confirmar_email.dart';

const String _assetLogo = 'assets/imagenes/logo.png';

/// Regex simple para validar email.
bool _esEmailValido(String? value) {
  if (value == null || value.trim().isEmpty) return false;
  final emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );
  return emailRegex.hasMatch(value.trim());
}

class LocalesCrearCuenta extends StatefulWidget {
  const LocalesCrearCuenta({
    super.key,
    this.desdeMultiCuenta = false,
  });

  final bool desdeMultiCuenta;

  @override
  State<LocalesCrearCuenta> createState() => _LocalesCrearCuentaState();
}

class _LocalesCrearCuentaState extends State<LocalesCrearCuenta> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _contrasena = TextEditingController();
  final TextEditingController _repetirContrasena = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _ocultarContrasena = true;
  bool _ocultarRepetir = true;
  bool _cargando = false;
  bool _cargandoGoogle = false;

  @override
  void dispose() {
    _email.dispose();
    _contrasena.dispose();
    _repetirContrasena.dispose();
    super.dispose();
  }

  Future<void> _preservarSiMultiCuenta() async {
    if (!widget.desdeMultiCuenta) return;
    try {
      final vault = VaultSesionesLocales();
      final uid = vault.uidActivo;
      if (uid == null) return;
      if (await vault.buscar(uid) == null) return;
      await vault.guardarActual();
    } catch (_) {}
  }

  Future<void> _crearCuentaGoogle() async {
    setState(() => _cargandoGoogle = true);
    await _preservarSiMultiCuenta();
    try {
      await ServicioSupabase().cliente.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: authRedirectUrlLocales,
      );
    } catch (e) {
      if (mounted) {
        _mostrarError(
          'No se pudo conectar con Google.\n\nProbá de nuevo en unos segundos.',
        );
      }
    } finally {
      if (mounted) setState(() => _cargandoGoogle = false);
    }
  }

  Future<void> _crearCuenta() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _cargando = true);
    await _preservarSiMultiCuenta();
    try {
      final supabase = ServicioSupabase();
      final email = _email.text.trim();

      // Comprobar si el email ya está registrado (evita falso positivo de Supabase)
      final yaRegistrado = await _emailYaRegistrado(supabase.cliente, email);
      if (yaRegistrado && mounted) {
        _mostrarError(TraductorErroresAuth.mensajeCuentaExistenteEnFernecito());
        return;
      }

      final respuesta = await supabase.cliente.auth.signUp(
        email: email,
        password: _contrasena.text,
        emailRedirectTo: authRedirectUrlLocales,
      );
      final identidades = respuesta.user?.identities;
      if (respuesta.user != null &&
          respuesta.session == null &&
          identidades != null &&
          identidades.isEmpty) {
        if (mounted) {
          _mostrarError(
            TraductorErroresAuth.mensajeCuentaExistenteEnFernecito(),
          );
        }
        return;
      }
      if (respuesta.user != null) {
        if (respuesta.session == null) {
          if (widget.desdeMultiCuenta) {
            if (!mounted) return;
            await _mostrarExitoAsync(
              'Te enviamos un email de confirmación a $email.\n\n'
              'Cuando lo confirmes, volvé a "Agregar cuenta" e iniciá sesión.',
            );
            await _restaurarCuentaPreviaSiHaceFalta();
            return;
          }
          if (mounted) {
            Navigator.pushReplacementNamed(
              context,
              '/confirmar_email',
              arguments: ConfirmarEmailArgs(email: email),
            );
          }
        } else {
          await VaultSesionesLocales().guardarActual();
          if (widget.desdeMultiCuenta) {
            await recargarAppTrasCambioCuenta();
            return;
          }
          if (mounted) {
            _mostrarExito(
              '¡Cuenta creada! Ahora configurá el perfil de tu local.',
            );
          }
        }
      } else if (mounted) {
        _mostrarError('No se pudo crear la cuenta. Intentá de nuevo.');
      }
    } catch (e) {
      if (mounted) {
        final mensaje = TraductorErroresAuth.esCuentaYaRegistrada(e)
            ? TraductorErroresAuth.mensajeCuentaExistenteEnFernecito()
            : TraductorErroresAuth.traducir(e);
        _mostrarError(mensaje);
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Llama a la función RPC en Supabase que indica si el email ya existe en auth.
  /// Si la función no existe o falla, devuelve false para no bloquear el signUp.
  Future<bool> _emailYaRegistrado(dynamic cliente, String email) async {
    try {
      final res = await cliente.rpc(
        'email_ya_registrado',
        params: {'p_email': email},
      );
      if (res == true) return true;
      if (res is List && res.isNotEmpty && res.first == true) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _restaurarCuentaPreviaSiHaceFalta() async {
    final vault = VaultSesionesLocales();
    if (vault.uidActivo != null) return;
    for (final c in await vault.listar()) {
      final res = await vault.cambiarA(c.uid, preservarActiva: false);
      if (res == ResultadoCambioCuenta.ok) {
        await recargarAppTrasCambioCuenta();
        return;
      }
    }
  }

  void _mostrarExito(String mensaje) =>
      _mostrarDialogoAuth(titulo: '¡Listo!', mensaje: mensaje, esError: false);

  Future<void> _mostrarExitoAsync(String mensaje) =>
      _mostrarDialogoAuth(titulo: '¡Listo!', mensaje: mensaje, esError: false);

  void _mostrarError(String mensaje) => _mostrarDialogoAuth(
    titulo: 'No se pudo crear la cuenta',
    mensaje: mensaje,
  );

  Future<void> _mostrarDialogoAuth({
    required String titulo,
    required String mensaje,
    bool esError = true,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ColoresOnboardingLocales.violetaOscuro,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          titulo,
          style: GoogleFonts.baloo2(
            color: esError
                ? const Color(0xFFFF8A80)
                : ColoresOnboardingLocales.texto,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          mensaje,
          style: GoogleFonts.baloo2(
            color: ColoresOnboardingLocales.textoSecundario,
            height: 1.35,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Entendido',
              style: GoogleFonts.baloo2(
                color: ColoresOnboardingLocales.mostaza,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColoresOnboardingLocales.violeta,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 32),
                Center(
                  child: Image.asset(
                    _assetLogo,
                    height: 80,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.person_add_rounded,
                      size: 64,
                      color: ColoresLocales.textoOnFondoClaro,
                    ),
                  ),
                ),
                SizedBox(height: 24),
                Text(
                  'Crear cuenta',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.baloo2(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: ColoresOnboardingLocales.texto,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '¿Ya usás Fernecito con Google? Entrá con el mismo email.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.baloo2(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: ColoresOnboardingLocales.textoSecundario,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: (_cargando || _cargandoGoogle)
                        ? null
                        : _crearCuentaGoogle,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ColoresOnboardingLocales.violetaOscuro,
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _cargandoGoogle
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const FaIcon(FontAwesomeIcons.google, size: 18),
                              const SizedBox(width: 10),
                              Text(
                                'Continuar con Google',
                                style: GoogleFonts.baloo2(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Divider(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'o con email',
                        style: GoogleFonts.baloo2(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: ColoresOnboardingLocales.textoSuave,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Divider(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingresá un email';
                    }
                    if (!_esEmailValido(value)) {
                      return 'Ingresá un email válido';
                    }
                    return null;
                  },
                  style: GoogleFonts.baloo2(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: ColoresOnboardingLocales.texto,
                  ),
                  decoration: _decoration(
                    hint: 'Email',
                    prefixIcon: Icons.email_outlined,
                  ),
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _contrasena,
                  obscureText: _ocultarContrasena,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Ingresá una contraseña';
                    }
                    if (value.length < 6) {
                      return 'Mínimo 6 caracteres';
                    }
                    return null;
                  },
                  style: GoogleFonts.baloo2(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: ColoresOnboardingLocales.texto,
                  ),
                  decoration: _decoration(
                    hint: 'Contraseña',
                    prefixIcon: Icons.lock_outline_rounded,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _ocultarContrasena
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: ColoresOnboardingLocales.textoSecundario,
                        size: 22,
                      ),
                      onPressed: () => setState(
                        () => _ocultarContrasena = !_ocultarContrasena,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _repetirContrasena,
                  obscureText: _ocultarRepetir,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Repetí la contraseña';
                    }
                    if (value != _contrasena.text) {
                      return 'Las contraseñas no coinciden';
                    }
                    return null;
                  },
                  style: GoogleFonts.baloo2(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: ColoresOnboardingLocales.texto,
                  ),
                  decoration: _decoration(
                    hint: 'Repetir contraseña',
                    prefixIcon: Icons.lock_outline_rounded,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _ocultarRepetir
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: ColoresOnboardingLocales.textoSecundario,
                        size: 22,
                      ),
                      onPressed: () =>
                          setState(() => _ocultarRepetir = !_ocultarRepetir),
                    ),
                  ),
                ),
                SizedBox(height: 28),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _cargando ? null : _crearCuenta,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: ColoresOnboardingLocales.violetaOscuro,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                      elevation: 0,
                    ),
                    child: _cargando
                        ? SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              color: ColoresLocales.chipInactivo,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'Crear cuenta',
                            style: GoogleFonts.baloo2(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
                SizedBox(height: 20),
                Center(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: GoogleFonts.baloo2(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: ColoresOnboardingLocales.textoSecundario,
                        ),
                        children: [
                          TextSpan(text: '¿Ya tenés cuenta? '),
                          TextSpan(
                            text: 'Iniciar sesión',
                            style: GoogleFonts.baloo2(
                              fontSize: 14,
                              color: ColoresOnboardingLocales.mostaza,
                              fontWeight: FontWeight.w800,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration({
    required String hint,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.baloo2(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: ColoresOnboardingLocales.textoSuave,
      ),
      errorStyle: GoogleFonts.baloo2(
        fontSize: 12,
        color: const Color(0xFFFFD89B),
      ),
      prefixIcon: Icon(
        prefixIcon,
        color: ColoresOnboardingLocales.textoSecundario,
        size: 22,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: ColoresOnboardingLocales.inputFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: ColoresOnboardingLocales.inputBorde,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: ColoresOnboardingLocales.inputBorde,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFFFB4B4), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}
