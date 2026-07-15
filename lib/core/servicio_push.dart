/// ServicioPush (Locales) — registro y manejo de notificaciones push (FCM).
///
/// Registra tokens FCM nativos (Android/iOS) y Web/PWA cuando existe config
/// Firebase Web. El token se ata al local logueado via edge
/// `registrar_push_token` con app='locales' (para segmentar los envíos).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config_push_web.dart';
import 'push_web_helper.dart';

class ServicioPush {
  ServicioPush._();
  static final ServicioPush instancia = ServicioPush._();

  static const String _app = 'locales';

  bool _inicializado = false;
  String? _ultimoTokenRegistrado;

  bool get soportado =>
      (kIsWeb && ConfigPushWeb.habilitada) ||
      (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS));

  Future<void> inicializar() async {
    if (_inicializado || !soportado) return;
    _inicializado = true;

    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _registrarToken(token);
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
      debugPrint('📩 Push locales en primer plano: ${msg.notification?.title}');
      if (kIsWeb) {
        unawaited(
          mostrarNotificacionForegroundWeb(
            titulo: msg.notification?.title ?? 'Fernecito',
            cuerpo: msg.notification?.body ?? '',
          ),
        );
      }
    });
  }

  /// Pide permiso (Android 13+/iOS/PWA) y registra el token del local actual.
  /// Llamar solo tras acción explícita del usuario (botón / diálogo).
  Future<bool> registrarParaUsuario() async {
    if (!soportado) return false;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('🔔 Permiso push locales: ${settings.authorizationStatus.name}');
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return false;
      }
      return _obtenerYRegistrarToken();
    } catch (e) {
      debugPrint('⚠️ registrarParaUsuario push locales: $e');
    }
    return false;
  }

  /// Si el usuario ya autorizó antes, registra el token sin mostrar el modal del OS.
  Future<void> sincronizarSiAutorizado() async {
    if (!soportado) return;
    if (!await tienePermiso()) return;
    await _obtenerYRegistrarToken();
  }

  Future<bool> tienePermiso() async {
    if (!soportado) return false;
    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _obtenerYRegistrarToken() async {
    try {
      if (kIsWeb) {
        await asegurarServiceWorkerPush();
      }
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb ? ConfigPushWeb.vapidKey : null,
      );
      if (token != null && token.isNotEmpty) {
        await _registrarToken(token);
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ obtener token push locales: $e');
    }
    return false;
  }

  Future<void> _registrarToken(String token) async {
    if (token == _ultimoTokenRegistrado) return;
    final sesion = Supabase.instance.client.auth.currentSession;
    if (sesion == null) return;
    try {
      await Supabase.instance.client.functions.invoke(
        'registrar_push_token',
        body: {
          'token': token,
          'app': _app,
          'plataforma': kIsWeb
              ? 'web'
              : (defaultTargetPlatform == TargetPlatform.iOS
                    ? 'ios'
                    : 'android'),
        },
      );
      _ultimoTokenRegistrado = token;
      debugPrint('✅ Token push locales registrado');
    } catch (e) {
      debugPrint('⚠️ registrar token push locales: $e');
    }
  }

  void olvidarLocal() {
    _ultimoTokenRegistrado = null;
  }
}
