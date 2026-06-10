/// Recuperar contraseña con código OTP de 6 dígitos (PWA, sin deep links).
///
/// Flujo en 3 pasos:
/// 1. Pedir email → Enviar código
/// 2. Ingresar código 6 dígitos → Verificar
/// 3. Nueva contraseña + confirmar → Actualizar
library;

import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pinput/pinput.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/auth_errors.dart';
import '../core/constants.dart';
import '../widgets/tema_locales_scope.dart';
import '../core/flujo_recuperacion.dart';
import '../core/supabase_client.dart';

class LocalesContrasena extends StatefulWidget {
  const LocalesContrasena({super.key});

  @override
  State<LocalesContrasena> createState() => _LocalesContrasenaState();
}

class _LocalesContrasenaState extends State<LocalesContrasena> {
  int _paso = 1;
  final TextEditingController _email = TextEditingController();
  final TextEditingController _codigo = TextEditingController();
  final TextEditingController _nuevaContrasena = TextEditingController();
  final TextEditingController _confirmarContrasena = TextEditingController();

  bool _ocultarNueva = true;
  bool _ocultarConfirmar = true;
  bool _procesando = false;
  int _segundosReenviar = 0;
  Timer? _timerReenviar;

  @override
  void dispose() {
    enFlujoRecuperacionContrasena = false;
    _email.dispose();
    _codigo.dispose();
    _nuevaContrasena.dispose();
    _confirmarContrasena.dispose();
    _timerReenviar?.cancel();
    super.dispose();
  }

  Future<void> _enviarCodigo() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      _mostrarError('Ingresá tu email');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      _mostrarError('Ingresá un email válido');
      return;
    }
    setState(() => _procesando = true);
    try {
      await ServicioSupabase().cliente.auth.resetPasswordForEmail(email);
      if (mounted) {
        _mostrarExito(TraductorErroresAuth.mensajeCodigoEnviado());
        _iniciarContadorReenviar();
        setState(() {
          _paso = 2;
          _procesando = false;
          _codigo.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        _mostrarError(TraductorErroresAuth.traducir(e));
        setState(() => _procesando = false);
      }
    }
  }

  void _iniciarContadorReenviar() {
    _timerReenviar?.cancel();
    setState(() => _segundosReenviar = 60);
    _timerReenviar = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_segundosReenviar <= 1) {
          _segundosReenviar = 0;
          _timerReenviar?.cancel();
        } else {
          _segundosReenviar--;
        }
      });
    });
  }

  Future<void> _reenviarCodigo() async {
    if (_segundosReenviar > 0) return;
    await _enviarCodigo();
  }

  Future<void> _verificarCodigo() async {
    final codigo = _codigo.text.trim();
    if (codigo.length != 8) {
      _mostrarError('Ingresá el código de 8 dígitos');
      return;
    }
    final email = _email.text.trim();
    setState(() => _procesando = true);
    enFlujoRecuperacionContrasena = true; // Evita que AuthGate navegue al recibir signedIn
    try {
      await ServicioSupabase().cliente.auth.verifyOTP(
        email: email,
        token: codigo,
        type: OtpType.recovery,
      );
      if (mounted) {
        setState(() {
          _paso = 3;
          _procesando = false;
          _nuevaContrasena.clear();
          _confirmarContrasena.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        _mostrarError(TraductorErroresAuth.traducir(e));
        setState(() => _procesando = false);
      }
    }
  }

  bool _esContrasenaValida(String s) {
    if (s.length < 8) return false;
    final tieneLetra = RegExp(r'[a-zA-Z]').hasMatch(s);
    final tieneNumero = RegExp(r'[0-9]').hasMatch(s);
    return tieneLetra && tieneNumero;
  }

  Future<void> _cambiarContrasena() async {
    final pass = _nuevaContrasena.text;
    final confirm = _confirmarContrasena.text;
    if (pass.isEmpty || confirm.isEmpty) {
      _mostrarError('Completá ambos campos de contraseña');
      return;
    }
    if (!_esContrasenaValida(pass)) {
      _mostrarError(
        'La contraseña debe tener al menos 8 caracteres,\n'
        'una letra y un número.',
      );
      return;
    }
    if (pass != confirm) {
      _mostrarError('Las contraseñas no coinciden');
      return;
    }
    setState(() => _procesando = true);
    try {
      await ServicioSupabase().cliente.auth.updateUser(
        UserAttributes(password: pass),
      );
      if (mounted) {
        enFlujoRecuperacionContrasena = false;
        _mostrarExito(TraductorErroresAuth.mensajePasswordActualizada());
        await Future.delayed(Duration(seconds: 2));
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        }
      }
    } catch (e) {
      if (mounted) _mostrarError(TraductorErroresAuth.traducir(e));
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  void _mostrarError(String mensaje) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ColoresLocales.fondoSuperficie,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Error', style: GoogleFonts.baloo2(color: ColoresLocales.textoPrincipal)),
        content: Text(mensaje, style: GoogleFonts.baloo2(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK', style: GoogleFonts.baloo2(color: ColoresLocales.acentoVioleta)),
          ),
        ],
      ),
    );
  }

  void _mostrarExito(String mensaje) {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ColoresLocales.fondoSuperficie,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Listo', style: GoogleFonts.baloo2(color: ColoresLocales.textoPrincipal)),
        content: Text(mensaje, style: GoogleFonts.baloo2(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK', style: GoogleFonts.baloo2(color: ColoresLocales.acentoVioleta)),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String hint, {IconData? prefixIcon, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.baloo2(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: ColoresLocales.textoSecundarioOnFondoClaro,
      ),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, color: ColoresLocales.textoSecundarioOnFondoClaro, size: 22)
          : null,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: ColoresLocales.grisClaroFondo,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(50),
        borderSide: BorderSide(color: ColoresLocales.acentoVioleta, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(50),
        borderSide: BorderSide(color: ColoresLocales.acentoVioleta.withOpacity(0.5), width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(50),
        borderSide: BorderSide(color: ColoresLocales.acentoVioleta, width: 2),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    );
  }

  PinTheme _pinTheme({bool focused = false}) {
    return PinTheme(
      width: 48,
      height: 56,
      textStyle: GoogleFonts.baloo2(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: ColoresLocales.textoOnFondoClaro,
      ),
      decoration: BoxDecoration(
        color: ColoresLocales.grisClaroFondo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: focused ? ColoresLocales.acentoVioleta : ColoresLocales.acentoVioleta.withOpacity(0.4),
          width: focused ? 2 : 1.5,
        ),
      ),
    );
  }

  Widget _botonPrincipal({
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: ColoresLocales.acentoVioleta,
          foregroundColor: ColoresLocales.textoEnBoton,
          disabledBackgroundColor: ColoresLocales.acentoVioleta.withOpacity(0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
          elevation: 0,
        ),
        child: _procesando
            ? SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(color: ColoresLocales.textoEnBoton, strokeWidth: 2),
              )
            : Text(
                label,
                style: GoogleFonts.baloo2(fontSize: 17, fontWeight: FontWeight.w800),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return Scaffold(
      backgroundColor: ColoresLocales.fondoClaro,
      appBar: AppBar(
        backgroundColor: ColoresLocales.superficie,
        elevation: 0,
        centerTitle: true,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {
            if (_paso > 1) {
              setState(() => _paso--);
            } else {
              Navigator.of(context).pop();
            }
          },
          child: Icon(CupertinoIcons.chevron_back, color: ColoresLocales.acentoVioleta),
        ),
        title: Text(
          _tituloPaso(),
          style: GoogleFonts.baloo2(
            fontWeight: FontWeight.w900,
            color: ColoresLocales.acentoVioleta,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              _contenidoPaso(),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  String _tituloPaso() {
    switch (_paso) {
      case 1:
        return 'Recuperar contraseña';
      case 2:
        return 'Código de verificación';
      case 3:
        return 'Nueva contraseña';
      default:
        return 'Recuperar contraseña';
    }
  }

  Widget _contenidoPaso() {
    switch (_paso) {
      case 1:
        return _pasoEmail();
      case 2:
        return _pasoCodigo();
      case 3:
        return _pasoNuevaContrasena();
      default:
        return _pasoEmail();
    }
  }

  Widget _pasoEmail() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.lock_outline, size: 72, color: ColoresLocales.acentoVioleta),
        SizedBox(height: 24),
        Text(
          '¿Olvidaste tu contraseña?',
          textAlign: TextAlign.center,
          style: GoogleFonts.baloo2(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: ColoresLocales.textoOnFondoClaro,
          ),
        ),
        SizedBox(height: 12),
        Text(
          'Ingresá tu email y te enviaremos un código de 8 dígitos para recuperar tu cuenta de local.',
          textAlign: TextAlign.center,
          style: GoogleFonts.baloo2(
            fontSize: 14,
            color: ColoresLocales.textoSecundarioOnFondoClaro,
          ),
        ),
        SizedBox(height: 40),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enabled: !_procesando,
          style: GoogleFonts.baloo2(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: ColoresLocales.textoOnFondoClaro,
          ),
          decoration: _decoration(
            'Email de tu cuenta de local',
            prefixIcon: Icons.email_outlined,
          ),
        ),
        SizedBox(height: 32),
        _botonPrincipal(label: 'Enviar código', onPressed: _procesando ? null : _enviarCodigo),
      ],
    );
  }

  Widget _pasoCodigo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.sms_outlined, size: 72, color: ColoresLocales.acentoVioleta),
        SizedBox(height: 24),
        Text(
          'Ingresá el código',
          textAlign: TextAlign.center,
          style: GoogleFonts.baloo2(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: ColoresLocales.textoOnFondoClaro,
          ),
        ),
        SizedBox(height: 12),
        Text(
          'Te enviamos un código de 8 dígitos a ${_email.text.trim()}',
          textAlign: TextAlign.center,
          style: GoogleFonts.baloo2(
            fontSize: 14,
            color: ColoresLocales.textoSecundarioOnFondoClaro,
          ),
        ),
        SizedBox(height: 32),
        Pinput(
          controller: _codigo,
          length: 8,
          defaultPinTheme: _pinTheme(),
          focusedPinTheme: _pinTheme(focused: true),
          submittedPinTheme: _pinTheme(focused: true),
          enabled: !_procesando,
          hapticFeedbackType: HapticFeedbackType.mediumImpact,
          onCompleted: (_) => _verificarCodigo(),
        ),
        SizedBox(height: 24),
        _botonPrincipal(
          label: 'Verificar código',
          onPressed: _procesando ? null : _verificarCodigo,
        ),
        SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _segundosReenviar > 0 ? 'Reenviar en ${_segundosReenviar}s' : '¿No te llegó?',
              style: GoogleFonts.baloo2(
                fontSize: 14,
                color: ColoresLocales.textoSecundarioOnFondoClaro,
              ),
            ),
            SizedBox(width: 8),
            TextButton(
              onPressed: _segundosReenviar > 0 ? null : _reenviarCodigo,
              child: Text(
                'Reenviar código',
                style: GoogleFonts.baloo2(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _segundosReenviar > 0
                      ? ColoresLocales.textoSecundarioOnFondoClaro
                      : ColoresLocales.acentoVioleta,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _pasoNuevaContrasena() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.lock_reset, size: 72, color: ColoresLocales.acentoVioleta),
        SizedBox(height: 24),
        Text(
          'Creá tu nueva contraseña',
          textAlign: TextAlign.center,
          style: GoogleFonts.baloo2(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: ColoresLocales.textoOnFondoClaro,
          ),
        ),
        SizedBox(height: 12),
        Text(
          'Mínimo 8 caracteres, una letra y un número.',
          textAlign: TextAlign.center,
          style: GoogleFonts.baloo2(
            fontSize: 14,
            color: ColoresLocales.textoSecundarioOnFondoClaro,
          ),
        ),
        SizedBox(height: 32),
        TextField(
          controller: _nuevaContrasena,
          obscureText: _ocultarNueva,
          enabled: !_procesando,
          style: GoogleFonts.baloo2(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: ColoresLocales.textoOnFondoClaro,
          ),
          decoration: _decoration(
            'Nueva contraseña',
            prefixIcon: Icons.lock_outline_rounded,
            suffixIcon: IconButton(
              icon: Icon(
                _ocultarNueva ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: ColoresLocales.textoSecundarioOnFondoClaro,
                size: 22,
              ),
              onPressed: () => setState(() => _ocultarNueva = !_ocultarNueva),
            ),
          ),
        ),
        SizedBox(height: 16),
        TextField(
          controller: _confirmarContrasena,
          obscureText: _ocultarConfirmar,
          enabled: !_procesando,
          style: GoogleFonts.baloo2(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: ColoresLocales.textoOnFondoClaro,
          ),
          decoration: _decoration(
            'Repetí la contraseña',
            prefixIcon: Icons.lock_outline_rounded,
            suffixIcon: IconButton(
              icon: Icon(
                _ocultarConfirmar ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: ColoresLocales.textoSecundarioOnFondoClaro,
                size: 22,
              ),
              onPressed: () => setState(() => _ocultarConfirmar = !_ocultarConfirmar),
            ),
          ),
        ),
        const SizedBox(height: 32),
        _botonPrincipal(
          label: 'Cambiar contraseña',
          onPressed: _procesando ? null : _cambiarContrasena,
        ),
      ],
    );
  }
}
