/// AuthGate — redirige según modo local/staff y estado del perfil.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'flujo_recuperacion.dart';
import 'modo_app_locales.dart';
import 'servicio_push.dart';
import 'servicio_staff_locales.dart';
import 'servicio_estado_cuenta_locales.dart';
import 'vault_sesiones_locales.dart';
import 'recarga_cuenta_locales.dart';
import 'navigator_key_locales.dart';

const String _tablaPerfilesLocales = 'perfiles_locales';

class AuthGateLocales extends StatefulWidget {
  final Widget child;

  const AuthGateLocales({super.key, required this.child});

  @override
  State<AuthGateLocales> createState() => _AuthGateLocalesState();
}

class _AuthGateLocalesState extends State<AuthGateLocales> {
  late final StreamSubscription<AuthState> _authSubscription;
  String? _lastUserId;
  String? _currentRoute;

  @override
  void initState() {
    super.initState();
    _setupAuthListener();
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  void _setupAuthListener() {
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) {
      final event = data.event;
      final session = data.session;
      if (!mounted) return;

      switch (event) {
        case AuthChangeEvent.initialSession:
          if (session != null) {
            unawaited(ServicioPush.instancia.sincronizarSiAutorizado());
            // Snapshotear la cuenta ya logueada (sesión restaurada) en el
            // vault: sin esto el switcher sale vacío en la cuenta principal.
            if (!ModoAppLocales.instancia.esStaff) {
              unawaited(VaultSesionesLocales().guardarActual());
            }
          }
          break;
        case AuthChangeEvent.signedIn:
          _handleSignedIn(session);
          break;
        case AuthChangeEvent.signedOut:
          _handleSignedOut();
          break;
        case AuthChangeEvent.tokenRefreshed:
          // Re-guardar el refresh token rotado de la cuenta activa en el vault
          // para que no se venza al cambiar de cuenta más tarde.
          unawaited(VaultSesionesLocales().actualizarTokenActivo());
          // Algunos flujos de setSession emiten tokenRefreshed en vez de
          // signedIn: si cambió el uid, ruteamos igual.
          final uid = session?.user.id;
          if (uid != null && _lastUserId != null && uid != _lastUserId) {
            unawaited(_handleSignedIn(session));
          }
          break;
        case AuthChangeEvent.passwordRecovery:
          _handlePasswordRecovery();
          break;
        default:
          break;
      }
    }, onError: (error) => print('❌ AuthGateLocales: $error'));
  }

  Future<void> _handleSignedIn(Session? session) async {
    if (session == null) return;
    if (enFlujoRecuperacionContrasena) return;

    // Misma cuenta y ya ruteada → no repetir.
    // Cambio de cuenta (multi-cuenta / agregar) → SÍ hay que re-navegar aunque
    // la ruta sea la misma (/home→/home); si no, la UI queda con el Home viejo
    // y el switcher se queda en "Cambiando…".
    final uidAnterior = _lastUserId;
    final cambioDeCuenta =
        uidAnterior != null && uidAnterior != session.user.id;
    if (!cambioDeCuenta &&
        uidAnterior == session.user.id &&
        _currentRoute != null) {
      return;
    }

    _lastUserId = session.user.id;

    // Si ya tenía permiso, registrar token sin pedir de nuevo.
    unawaited(ServicioPush.instancia.sincronizarSiAutorizado());

    await ModoAppLocales.instancia.cargar();

    if (!mounted) return;

    if (ModoAppLocales.instancia.esStaff) {
      await _rutearStaff(forzar: cambioDeCuenta);
      return;
    }

    try {
      final suspendida = await ServicioEstadoCuentaLocales.instancia
          .refrescar();
      if (!mounted) return;

      if (suspendida) {
        _navigateTo('/cuenta_bloqueada', forzar: cambioDeCuenta);
        return;
      }

      final respuesta = await Supabase.instance.client
          .from(_tablaPerfilesLocales)
          .select('id, nombre_local, perfil_local_completo')
          .eq('id', session.user.id)
          .maybeSingle();

      if (!mounted) return;

      final nombreLocal = (respuesta?['nombre_local'] as String?)?.trim();
      final perfilCompleto =
          respuesta?['perfil_local_completo'] == true ||
          (nombreLocal ?? '').isNotEmpty;

      // Multi-cuenta: snapshotear esta cuenta (dueño) en el vault de sesiones.
      unawaited(VaultSesionesLocales().guardarActual(nombreLocal: nombreLocal));

      if (perfilCompleto) {
        if (cambioDeCuenta) {
          // Remount completo con splash (switcher/login también pueden
          // dispararlo; recargarAppTrasCambioCuenta es idempotente y
          // resuelve home vs crear_perfil según el perfil).
          unawaited(recargarAppTrasCambioCuenta());
        } else {
          _navigateTo('/home');
        }
      } else {
        if (cambioDeCuenta) {
          // Misma recarga: el splash manda a /crear_perfil si está incompleto.
          unawaited(recargarAppTrasCambioCuenta());
        } else {
          _navigateTo('/crear_perfil');
        }
      }
    } catch (e) {
      print('❌ AuthGateLocales error perfil: $e');
      if (mounted) _navigateTo('/crear_perfil', forzar: cambioDeCuenta);
    }
  }

  Future<void> _rutearStaff({bool forzar = false}) async {
    try {
      final completo = await ServicioStaffLocales().perfilStaffCompleto();
      if (!mounted) return;
      if (completo) {
        _navigateTo('/staff_home', forzar: forzar);
      } else {
        _navigateTo('/staff_crear_perfil', forzar: forzar);
      }
    } catch (e) {
      print('❌ AuthGateLocales error staff: $e');
      if (mounted) _navigateTo('/staff_crear_perfil', forzar: forzar);
    }
  }

  void _handleSignedOut() {
    ServicioEstadoCuentaLocales.instancia.limpiar();
    ServicioPush.instancia.olvidarLocal();
    _lastUserId = null;
    _currentRoute = null;
    // Seguridad multi-cuenta: signOut = fin de sesión en este dispositivo.
    // El switch (setSession) NO dispara signedOut, así que las otras cuentas
    // siguen en el vault. Pero un logout real NO debe dejar refresh tokens
    // reutilizables (dispositivo compartido / cerrar desde cuenta bloqueada).
    unawaited(VaultSesionesLocales().vaciar());
    _navigateTo(
      ModoAppLocales.instancia.esStaff ? '/staff_login' : '/login',
      forzar: true,
    );
  }

  void _handlePasswordRecovery() {
    if (enFlujoRecuperacionContrasena) return;
    _navigateTo('/contrasena', forzar: true);
  }

  /// [forzar]: remonta aunque la ruta sea la misma (cambio de cuenta multi-sesión).
  void _navigateTo(String routeName, {bool forzar = false}) {
    if (!forzar && _currentRoute == routeName) return;
    final navigator = navigatorKeyLocales.currentState;
    if (navigator == null) return;
    navigator.pushNamedAndRemoveUntil(routeName, (_) => false);
    _currentRoute = routeName;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
