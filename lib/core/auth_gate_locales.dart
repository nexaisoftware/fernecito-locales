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
final GlobalKey<NavigatorState> navigatorKeyLocales = GlobalKey<NavigatorState>();

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
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) {
        final event = data.event;
        final session = data.session;
        if (!mounted) return;

        switch (event) {
          case AuthChangeEvent.initialSession:
            if (session != null) {
              unawaited(ServicioPush.instancia.sincronizarSiAutorizado());
            }
            break;
          case AuthChangeEvent.signedIn:
            _handleSignedIn(session);
            break;
          case AuthChangeEvent.signedOut:
            _handleSignedOut();
            break;
          case AuthChangeEvent.passwordRecovery:
            _handlePasswordRecovery();
            break;
          default:
            break;
        }
      },
      onError: (error) => print('❌ AuthGateLocales: $error'),
    );
  }

  Future<void> _handleSignedIn(Session? session) async {
    if (session == null) return;
    if (enFlujoRecuperacionContrasena) return;
    if (_lastUserId == session.user.id && _currentRoute != null) return;

    _lastUserId = session.user.id;

    // Si ya tenía permiso, registrar token sin pedir de nuevo.
    unawaited(ServicioPush.instancia.sincronizarSiAutorizado());

    await ModoAppLocales.instancia.cargar();

    if (!mounted) return;

    if (ModoAppLocales.instancia.esStaff) {
      await _rutearStaff();
      return;
    }

    try {
      final suspendida = await ServicioEstadoCuentaLocales.instancia.refrescar();
      if (!mounted) return;

      if (suspendida) {
        _navigateTo('/cuenta_bloqueada');
        return;
      }

      final respuesta = await Supabase.instance.client
          .from(_tablaPerfilesLocales)
          .select('id, nombre_local, perfil_local_completo')
          .eq('id', session.user.id)
          .maybeSingle();

      if (!mounted) return;

      final perfilCompleto = respuesta?['perfil_local_completo'] == true ||
          ((respuesta?['nombre_local'] as String?)?.trim() ?? '').isNotEmpty;

      if (perfilCompleto) {
        _navigateTo('/home');
      } else {
        _navigateTo('/crear_perfil');
      }
    } catch (e) {
      print('❌ AuthGateLocales error perfil: $e');
      if (mounted) _navigateTo('/crear_perfil');
    }
  }

  Future<void> _rutearStaff() async {
    try {
      final completo = await ServicioStaffLocales().perfilStaffCompleto();
      if (!mounted) return;
      if (completo) {
        _navigateTo('/staff_home');
      } else {
        _navigateTo('/staff_crear_perfil');
      }
    } catch (e) {
      print('❌ AuthGateLocales error staff: $e');
      if (mounted) _navigateTo('/staff_crear_perfil');
    }
  }

  void _handleSignedOut() {
    ServicioEstadoCuentaLocales.instancia.limpiar();
    ServicioPush.instancia.olvidarLocal();
    _lastUserId = null;
    _currentRoute = null;
    _navigateTo(
      ModoAppLocales.instancia.esStaff ? '/staff_login' : '/login',
    );
  }

  void _handlePasswordRecovery() {
    if (enFlujoRecuperacionContrasena) return;
    _navigateTo('/contrasena');
  }

  void _navigateTo(String routeName) {
    if (_currentRoute == routeName) return;
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
