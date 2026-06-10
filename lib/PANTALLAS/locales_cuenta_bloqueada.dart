/// Pantalla bloqueante cuando el local está suspendido.
/// Solo permite soporte y cerrar sesión.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/servicio_estado_cuenta_locales.dart';
import '../core/tema_app_locales.dart';
import '../core/constants.dart';

class LocalesCuentaBloqueada extends StatefulWidget {
  const LocalesCuentaBloqueada({super.key});

  @override
  State<LocalesCuentaBloqueada> createState() => _LocalesCuentaBloqueadaState();
}

class _LocalesCuentaBloqueadaState extends State<LocalesCuentaBloqueada> {
  bool _verificando = true;

  @override
  void initState() {
    super.initState();
    _verificarEstado();
  }

  Future<void> _verificarEstado() async {
    final sigueSuspendida = await ServicioEstadoCuentaLocales.instancia.refrescar();
    if (!mounted) return;
    if (!sigueSuspendida) {
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
      return;
    }
    setState(() => _verificando = false);
  }

  Future<void> _irSoporte() async {
    await Navigator.of(context).pushNamed('/soporte');
    if (!mounted) return;
    await ServicioEstadoCuentaLocales.instancia.refrescar();
    if (!mounted) return;
    if (!ServicioEstadoCuentaLocales.instancia.suspendida) {
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
    }
  }

  Future<void> _cerrarSesion() async {
    ServicioEstadoCuentaLocales.instancia.limpiar();
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final oscuro = TemaAppLocales.instancia.esOscuro;
    final fondo = oscuro ? const Color(0xFF0F0E14) : const Color(0xFFFAF9FC);
    final texto = oscuro ? Colors.white : const Color(0xFF222033);
    final subt = oscuro ? Colors.white70 : Colors.black54;
    final motivo = ServicioEstadoCuentaLocales.instancia.motivoLabel ??
        'Tu cuenta fue suspendida por el equipo de Fernecito';

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: fondo,
        body: SafeArea(
          child: _verificando
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFB91C1C).withValues(alpha: 0.15),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.gpp_bad_rounded,
                              size: 72,
                              color: Color(0xFFB91C1C),
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            'Cuenta suspendida',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.baloo2(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: texto,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'El acceso a tu panel de local fue suspendido temporalmente.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.baloo2(fontSize: 14.5, color: subt, height: 1.45),
                          ),
                          const SizedBox(height: 22),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: oscuro ? const Color(0xFF1C1B24) : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Motivo',
                                  style: GoogleFonts.baloo2(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFFB91C1C),
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  motivo,
                                  style: GoogleFonts.baloo2(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: texto,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Podés contactar a soporte oficial para revisar tu caso. '
                            'El resto de funciones permanecen deshabilitadas.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.baloo2(fontSize: 13, color: subt, height: 1.4),
                          ),
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                _irSoporte();
                              },
                              icon: const Icon(Icons.support_agent_rounded),
                              label: Text(
                                'Contactar soporte',
                                style: GoogleFonts.baloo2(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: ColoresLocales.acentoVioleta,
                                foregroundColor: ColoresLocales.textoEnBoton,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _cerrarSesion,
                              icon: Icon(Icons.logout_rounded, color: subt),
                              label: Text(
                                'Cerrar sesión',
                                style: GoogleFonts.baloo2(
                                  fontWeight: FontWeight.w700,
                                  color: subt,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                side: BorderSide(color: subt.withValues(alpha: 0.35)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
