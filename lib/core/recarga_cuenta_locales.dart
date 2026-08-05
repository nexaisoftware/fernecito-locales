/// Recarga completa de la UI tras un cambio de cuenta multi-sesión.
///
/// `setSession` / `signInWithPassword` cambian el JWT, pero el [LocalesHome]
/// (IndexedStack + caches) puede quedar montado con datos de la cuenta anterior.
/// Este puente limpia estado en memoria, muestra splash y remonta el destino
/// correcto según el perfil activo:
/// - suspendida → `/cuenta_bloqueada`
/// - perfil completo → `/home` (ValueKey por uid)
/// - perfil incompleto / sin fila → `/crear_perfil` (onboarding)
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/splash_carga_locales.dart';
import 'auth_gate_locales.dart';
import 'servicio_estado_cuenta_locales.dart';
import 'servicio_push.dart';

const String rutaRecargarCuenta = '/recargar_cuenta';
const String _tablaPerfilesLocales = 'perfiles_locales';

bool _recargaEnCurso = false;

/// Limpia caches y navega al splash de recarga → destino según perfil.
/// Idempotente: si ya hay una recarga en curso, no apila otra.
Future<void> recargarAppTrasCambioCuenta() async {
  if (_recargaEnCurso) return;
  _recargaEnCurso = true;

  ServicioEstadoCuentaLocales.instancia.limpiar();
  unawaited(ServicioPush.instancia.sincronizarSiAutorizado());

  final nav = navigatorKeyLocales.currentState;
  if (nav == null) {
    _recargaEnCurso = false;
    return;
  }
  nav.pushNamedAndRemoveUntil(rutaRecargarCuenta, (_) => false);
}

/// Misma regla que AuthGate: completo si flag o hay nombre.
Future<String> _destinoTrasCambioCuenta(String uid) async {
  try {
    final suspendida = await ServicioEstadoCuentaLocales.instancia.refrescar();
    if (suspendida) return '/cuenta_bloqueada';

    final respuesta = await Supabase.instance.client
        .from(_tablaPerfilesLocales)
        .select('id, nombre_local, perfil_local_completo')
        .eq('id', uid)
        .maybeSingle();

    final nombreLocal = (respuesta?['nombre_local'] as String?)?.trim() ?? '';
    final perfilCompleto =
        respuesta?['perfil_local_completo'] == true || nombreLocal.isNotEmpty;
    return perfilCompleto ? '/home' : '/crear_perfil';
  } catch (_) {
    // Ante duda, onboarding (no un Home vacío).
    return '/crear_perfil';
  }
}

/// Splash breve y remount del destino correcto (home o crear perfil).
class LocalesRecargarCuenta extends StatefulWidget {
  const LocalesRecargarCuenta({super.key});

  @override
  State<LocalesRecargarCuenta> createState() => _LocalesRecargarCuentaState();
}

class _LocalesRecargarCuentaState extends State<LocalesRecargarCuenta> {
  @override
  void initState() {
    super.initState();
    unawaited(_continuar());
  }

  Future<void> _continuar() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      _recargaEnCurso = false;
      navigatorKeyLocales.currentState?.pushNamedAndRemoveUntil(
        '/login',
        (_) => false,
      );
      return;
    }

    final destino = await _destinoTrasCambioCuenta(uid);

    // Mínimo visual para que se note el cambio de contexto.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) {
      _recargaEnCurso = false;
      return;
    }

    final nav = navigatorKeyLocales.currentState;
    if (nav == null) {
      _recargaEnCurso = false;
      return;
    }

    if (destino == '/home') {
      nav.pushNamedAndRemoveUntil(
        '/home',
        (_) => false,
        arguments: uid,
      );
    } else {
      nav.pushNamedAndRemoveUntil(
        destino,
        (_) => false,
        arguments: uid,
      );
    }
    _recargaEnCurso = false;
  }

  @override
  Widget build(BuildContext context) {
    return const SplashCargaLocales();
  }
}
