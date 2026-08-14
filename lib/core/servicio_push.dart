/// ServicioPush (Locales) — registro y manejo de notificaciones push (FCM).
///
/// Registra tokens FCM nativos (Android/iOS) y Web/PWA cuando existe config
/// Firebase Web. El token se ata al local logueado via edge
/// `registrar_push_token` con app='locales' (para segmentar los envíos).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config_push_web.dart';
import 'navigator_key_locales.dart';
import 'push_web_helper.dart';
import 'servicio_planes_locales.dart';

class ServicioPush {
  ServicioPush._();
  static final ServicioPush instancia = ServicioPush._();

  static const String _app = 'locales';

  bool _inicializado = false;
  bool _reintentandoNavegacion = false;
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

    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      unawaited(_navegarDesdePush(msg));
    });
    unawaited(_procesarMensajeInicial());
  }

  Future<void> _procesarMensajeInicial() async {
    try {
      final msg = await FirebaseMessaging.instance.getInitialMessage();
      if (msg != null) await _navegarDesdePush(msg);
    } catch (e) {
      debugPrint('⚠️ mensaje push inicial locales: $e');
    }
  }

  /// Abre el detalle del plan y, cuando el payload indica `chat`, continúa
  /// automáticamente al chat. Si el navigator todavía no está montado (caso
  /// habitual de `getInitialMessage` durante el arranque), se reintenta en el
  /// primer frame; sin navigator global no hay una ruta segura que empujar.
  Future<void> _navegarDesdePush(RemoteMessage message) async {
    final data = message.data;
    final tipo = (data['tipo'] ?? '').toString().trim();
    final ruta = (data['ruta'] ?? data['cta_ruta'] ?? '').toString().trim();
    final esPlan = tipo.startsWith('plan_') || ruta.contains('planes');
    String dato(List<String> keys) {
      for (final k in keys) {
        final v = data[k]?.toString().trim() ?? '';
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    final idPlan = esPlan ? dato(['id_plan', 'ref', 'cta_id_ref']) : '';
    if (!esPlan &&
        tipo != 'ranking_local_primero' &&
        ruta != '/home' &&
        idPlan.isEmpty) {
      return;
    }
    final accion = (data['accion'] ?? data['cta'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final navigator = navigatorKeyLocales.currentState;
    if (navigator == null) {
      if (_reintentandoNavegacion) {
        debugPrint(
          'ℹ️ Push recibido antes de montar navigatorKeyLocales; '
          'se omite la navegación.',
        );
        return;
      }
      _reintentandoNavegacion = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _reintentandoNavegacion = false;
        unawaited(_navegarDesdePush(message));
      });
      return;
    }
    if (tipo == 'ranking_local_primero' || (ruta == '/home' && !esPlan)) {
      await navigator.pushNamed('/home');
      return;
    }
    if (idPlan.isEmpty) return;
    final detalle = await ServicioPlanesLocales.instancia.detalle(idPlan);
    if (detalle != null && !detalle.plan.estaAbierto) {
      await navigator.pushNamed('/planes');
      return;
    }

    await navigator.pushNamed(
      '/planes/detalle',
      arguments: <String, dynamic>{
        'id_plan': idPlan,
        if (accion == 'chat') 'accion': 'chat',
      },
    );
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
      debugPrint(
        '🔔 Permiso push locales: ${settings.authorizationStatus.name}',
      );
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
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
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
