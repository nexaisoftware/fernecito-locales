/// Pantalla de login Fernecito Locales — Supabase Auth.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/auth_redirect_locales.dart';
import '../core/constants.dart';
import '../core/modo_app_locales.dart';
import '../core/supabase_client.dart';
import '../core/auth_errors.dart';
import 'locales_confirmar_email.dart';

class LocalesLogin extends StatefulWidget {
  const LocalesLogin({super.key});

  @override
  State<LocalesLogin> createState() => _LocalesLoginState();
}

class _LocalesLoginState extends State<LocalesLogin>
    with SingleTickerProviderStateMixin {
  final TextEditingController _usuario = TextEditingController();
  final TextEditingController _contrasena = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final GlobalKey _keyAcordeon = GlobalKey();

  late final AnimationController _animController;
  late final Animation<double> _animAcordeon;

  bool _mostrarFormularioEmail = false;
  bool _ocultarContrasena = true;
  bool _cargando = false;
  bool _cargandoGoogle = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _animAcordeon = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _usuario.dispose();
    _contrasena.dispose();
    _animController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _alternarFormularioEmail() {
    setState(() {
      _mostrarFormularioEmail = !_mostrarFormularioEmail;
      if (_mostrarFormularioEmail) {
        _animController.forward();
        Future.delayed(const Duration(milliseconds: 120), () {
          final ctx = _keyAcordeon.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeInOut,
              alignment: 0.1,
            );
          }
        });
      } else {
        _animController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColoresLocales.violetaLogoMarca,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              children: [
                Expanded(
                  flex: constraints.maxHeight > 700 ? 2 : 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          ColoresLocales.assetLogoMarca,
                          width: 96,
                          height: 96,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Fernecito Locales',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.baloo2(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Administrá tu local desde un solo lugar',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.baloo2(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.82),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: ColoresLocales.superficie,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Iniciá sesión',
                            style: GoogleFonts.baloo2(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: ColoresLocales.textoOnFondoClaro,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Elegí cómo querés entrar',
                            style: GoogleFonts.baloo2(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: ColoresLocales.textoSecundarioOnFondoClaro,
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 50,
                            child: OutlinedButton(
                              onPressed: (_cargando || _cargandoGoogle)
                                  ? null
                                  : _iniciarSesionGoogle,
                              style: OutlinedButton.styleFrom(
                                foregroundColor:
                                    ColoresLocales.textoOnFondoClaro,
                                backgroundColor: ColoresLocales.superficie,
                                side: BorderSide(
                                  color: ColoresLocales.bordeSuave,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _cargandoGoogle
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        FaIcon(
                                          FontAwesomeIcons.google,
                                          size: 18,
                                          color:
                                              ColoresLocales.textoOnFondoClaro,
                                        ),
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
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 50,
                            child: FilledButton(
                              onPressed: (_cargando || _cargandoGoogle)
                                  ? null
                                  : _alternarFormularioEmail,
                              style: FilledButton.styleFrom(
                                backgroundColor:
                                    ColoresLocales.violetaLogoMarca,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _mostrarFormularioEmail
                                        ? CupertinoIcons.chevron_up
                                        : CupertinoIcons.mail_solid,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Iniciar con email',
                                    style: GoogleFonts.baloo2(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          _buildAcordeonEmail(),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () =>
                                Navigator.pushNamed(context, '/crear_cuenta'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: ColoresLocales.violetaLogoMarca,
                              side: BorderSide(
                                color: ColoresLocales.violetaLogoMarca
                                    .withValues(alpha: 0.35),
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
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              ModoAppLocales.instancia.establecerStaff();
                              Navigator.pushNamed(context, '/staff_login');
                            },
                            child: Text(
                              'Soy del staff',
                              style: GoogleFonts.baloo2(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color:
                                    ColoresLocales.textoSecundarioOnFondoClaro,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAcordeonEmail() {
    return SizeTransition(
      sizeFactor: _animAcordeon,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: _animAcordeon,
        child: Padding(
          key: _keyAcordeon,
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CampoLogin(
                controller: _usuario,
                hint: 'Email',
                prefixIcon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              _CampoLogin(
                controller: _contrasena,
                hint: 'Contraseña',
                prefixIcon: Icons.lock_outline_rounded,
                obscureText: _ocultarContrasena,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _cargando ? null : _iniciarSesion(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _ocultarContrasena
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: ColoresLocales.textoSecundarioOnFondoClaro,
                    size: 22,
                  ),
                  onPressed: () =>
                      setState(() => _ocultarContrasena = !_ocultarContrasena),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _cargando ? null : _iniciarSesion,
                  style: FilledButton.styleFrom(
                    backgroundColor: ColoresLocales.violetaLogoMarca,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _cargando
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Entrar',
                          style: GoogleFonts.baloo2(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/contrasena'),
                  child: Text(
                    'Olvidé mi contraseña',
                    style: GoogleFonts.baloo2(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ColoresLocales.violetaLogoMarca,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _iniciarSesionGoogle() async {
    setState(() => _cargandoGoogle = true);
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

  Future<void> _iniciarSesion() async {
    final email = _usuario.text.trim();
    final contrasena = _contrasena.text;
    if (email.isEmpty || contrasena.isEmpty) {
      _mostrarError('Ingresá email y contraseña');
      return;
    }
    setState(() => _cargando = true);
    try {
      final supabase = ServicioSupabase();
      await supabase.cliente.auth.signInWithPassword(
        email: email,
        password: contrasena,
      );
    } catch (e) {
      if (mounted) {
        final msg = TraductorErroresAuth.esCredencialesInvalidas(e)
            ? TraductorErroresAuth.mensajeLoginIncorrectoLocales()
            : TraductorErroresAuth.traducir(e);
        _mostrarError(msg, email: email);
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _mostrarError(String mensaje, {String? email}) {
    final esEmailSinConfirmar =
        mensaje.contains('confirmar tu email') ||
        mensaje.contains('falta confirmar') ||
        mensaje.contains('confirmación');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ColoresLocales.superficie,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          esEmailSinConfirmar ? 'Email sin confirmar' : 'Error',
          style: GoogleFonts.baloo2(
            color: ColoresLocales.textoOnFondoClaro,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          mensaje,
          style: GoogleFonts.baloo2(
            color: ColoresLocales.textoSecundarioOnFondoClaro,
          ),
        ),
        actions: [
          if (esEmailSinConfirmar && email != null && email.isNotEmpty) ...[
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushNamed(
                  context,
                  '/confirmar_email',
                  arguments: ConfirmarEmailArgs(email: email),
                );
              },
              child: Text(
                'Ver instrucciones',
                style: GoogleFonts.baloo2(
                  color: ColoresLocales.violetaLogoMarca,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _reenviarConfirmacion(email);
              },
              child: Text(
                'Reenviar email',
                style: GoogleFonts.baloo2(
                  color: ColoresLocales.violetaLogoMarca,
                ),
              ),
            ),
          ],
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'OK',
              style: GoogleFonts.baloo2(color: ColoresLocales.violetaLogoMarca),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reenviarConfirmacion(String email) async {
    try {
      await ServicioSupabase().cliente.auth.resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo: authRedirectUrlLocales,
      );
      if (mounted) {
        _mostrarExito(TraductorErroresAuth.mensajeConfirmacionReenviada());
      }
    } catch (e) {
      if (mounted) {
        _mostrarError(TraductorErroresAuth.traducir(e));
      }
    }
  }

  void _mostrarExito(String mensaje) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ColoresLocales.superficie,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Listo',
          style: GoogleFonts.baloo2(
            color: ColoresLocales.textoOnFondoClaro,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          mensaje,
          style: GoogleFonts.baloo2(
            color: ColoresLocales.textoSecundarioOnFondoClaro,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'OK',
              style: GoogleFonts.baloo2(color: ColoresLocales.violetaLogoMarca),
            ),
          ),
        ],
      ),
    );
  }
}

class _CampoLogin extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData prefixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Widget? suffixIcon;
  final ValueChanged<String>? onSubmitted;

  const _CampoLogin({
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
      style: GoogleFonts.baloo2(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: ColoresLocales.textoOnFondoClaro,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.baloo2(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: ColoresLocales.textoSecundarioOnFondoClaro,
        ),
        prefixIcon: Icon(
          prefixIcon,
          color: ColoresLocales.textoSecundarioOnFondoClaro,
          size: 22,
        ),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: ColoresLocales.rellenoInput,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: ColoresLocales.bordeSuave),
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
