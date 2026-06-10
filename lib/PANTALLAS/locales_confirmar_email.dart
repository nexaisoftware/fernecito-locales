/// Pantalla dedicada tras crear cuenta: confirmar email con enlace (no código OTP).
library;

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/auth_errors.dart';
import '../core/auth_redirect_locales.dart';
import '../core/constants.dart';
import '../core/supabase_client.dart';

class ConfirmarEmailArgs {
  const ConfirmarEmailArgs({required this.email});

  final String email;
}

class LocalesConfirmarEmail extends StatefulWidget {
  const LocalesConfirmarEmail({super.key, required this.email});

  final String email;

  @override
  State<LocalesConfirmarEmail> createState() => _LocalesConfirmarEmailState();
}

class _LocalesConfirmarEmailState extends State<LocalesConfirmarEmail> {
  bool _reenviando = false;
  int _segundosReenviar = 0;
  Timer? _timerReenviar;

  @override
  void initState() {
    super.initState();
    _iniciarContadorReenviar(segundos: 45);
  }

  @override
  void dispose() {
    _timerReenviar?.cancel();
    super.dispose();
  }

  void _iniciarContadorReenviar({int segundos = 60}) {
    _timerReenviar?.cancel();
    setState(() => _segundosReenviar = segundos);
    _timerReenviar = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_segundosReenviar <= 1) {
        t.cancel();
        setState(() => _segundosReenviar = 0);
      } else {
        setState(() => _segundosReenviar -= 1);
      }
    });
  }

  Future<void> _reenviarEmail() async {
    if (_segundosReenviar > 0 || _reenviando) return;
    setState(() => _reenviando = true);
    try {
      await ServicioSupabase().cliente.auth.resend(
            type: OtpType.signup,
            email: widget.email,
            emailRedirectTo: authRedirectUrlLocales,
          );
      if (!mounted) return;
      _mostrarSnack(TraductorErroresAuth.mensajeConfirmacionReenviada());
      _iniciarContadorReenviar();
    } catch (e) {
      if (mounted) _mostrarSnack(TraductorErroresAuth.traducir(e), esError: true);
    } finally {
      if (mounted) setState(() => _reenviando = false);
    }
  }

  void _mostrarSnack(String mensaje, {bool esError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mensaje,
          style: GoogleFonts.baloo2(fontWeight: FontWeight.w600),
        ),
        backgroundColor: esError ? const Color(0xFFE53935) : ColoresLocales.acentoVioleta,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _irALogin() {
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.email.trim();

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
                        Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            CupertinoIcons.mail_solid,
                            size: 56,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Revisá tu correo',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.baloo2(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Te enviamos un enlace de confirmación.\nNo es un código: solo tocá el link.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.baloo2(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.88),
                            height: 1.35,
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
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Confirmá tu cuenta',
                            style: GoogleFonts.baloo2(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.alternate_email_rounded,
                                  color: ColoresLocales.violetaLogoMarca,
                                  size: 22,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    email,
                                    style: GoogleFonts.baloo2(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF1A1A1A),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          _PasoConfirmacion(
                            numero: 1,
                            titulo: 'Abrí tu bandeja de entrada',
                            detalle: 'Si no lo ves, revisá spam o promociones.',
                          ),
                          const SizedBox(height: 12),
                          _PasoConfirmacion(
                            numero: 2,
                            titulo: 'Tocá el enlace de Fernecito',
                            detalle: 'El botón suele decir "Confirmar email" o similar.',
                          ),
                          const SizedBox(height: 12),
                          _PasoConfirmacion(
                            numero: 3,
                            titulo: 'Volvé acá e iniciá sesión',
                            detalle:
                                'Con el email confirmado, entrás y la app te lleva a crear el perfil de tu local.',
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 52,
                            child: FilledButton(
                              onPressed: _irALogin,
                              style: FilledButton.styleFrom(
                                backgroundColor: ColoresLocales.violetaLogoMarca,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: Text(
                                'Ya confirmé — Iniciar sesión',
                                style: GoogleFonts.baloo2(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: (_segundosReenviar > 0 || _reenviando) ? null : _reenviarEmail,
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
                            child: _reenviando
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(
                                    _segundosReenviar > 0
                                        ? 'Reenviar email (${_segundosReenviar}s)'
                                        : 'Reenviar email',
                                    style: GoogleFonts.baloo2(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () =>
                                Navigator.pushReplacementNamed(context, '/crear_cuenta'),
                            child: Text(
                              'Usar otro email',
                              style: GoogleFonts.baloo2(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF6B7280),
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
}

class _PasoConfirmacion extends StatelessWidget {
  const _PasoConfirmacion({
    required this.numero,
    required this.titulo,
    required this.detalle,
  });

  final int numero;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: ColoresLocales.violetaLogoMarca,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$numero',
              style: GoogleFonts.baloo2(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: GoogleFonts.baloo2(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detalle,
                style: GoogleFonts.baloo2(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF6B7280),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
