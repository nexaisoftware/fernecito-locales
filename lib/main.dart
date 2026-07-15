/// Punto de entrada Fernecito Locales — inicializa configuracion y Supabase.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'core/config_push_web.dart';
import 'core/servicio_push.dart';
import 'core/constants.dart';
import 'core/barra_sistema_locales.dart';
import 'core/tema_app_locales.dart';
import 'core/modo_app_locales.dart';
import 'widgets/tema_locales_scope.dart';
import 'core/auth_gate_locales.dart';
import 'core/rutas_locales.dart';
import 'core/servicio_staff_locales.dart';
import 'PANTALLAS/locales_home.dart';
import 'PANTALLAS/locales_login.dart';
import 'PANTALLAS/locales_crear_perfil.dart';
import 'PANTALLAS/locales_staff_login.dart';
import 'PANTALLAS/locales_staff_crear_perfil.dart';
import 'PANTALLAS/locales_staff_home.dart';
import 'core/servicio_estado_cuenta_locales.dart';
import 'PANTALLAS/locales_cuenta_bloqueada.dart';
import 'widgets/skeleton_pantalla_dashboard.dart';
import 'widgets/control_actualizacion_web.dart';
import 'widgets/control_instalar_pwa.dart';

/// Handler de mensajes push con la app en background/cerrada (top-level).
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {}

bool get _pushSoportado =>
    (kIsWeb && ConfigPushWeb.habilitada) ||
    (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS));

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Fuerza apagar guías de baseline/debug paint que generan "doble subrayado" en textos.
  debugPaintBaselinesEnabled = false;

  // Fallback local: --dart-define (prod) > assets/.env > .env en raíz.
  await _cargarEnvLocal();

  bool supabaseOk = false;
  String? errorSupabase;
  try {
    final url = _config('URL_SUPABASE');
    final clave = _config('CLAVE_PUBLICA_SUPABASE');
    if (url.isEmpty || clave.isEmpty) {
      throw Exception('Faltan URL_SUPABASE o CLAVE_PUBLICA_SUPABASE');
    }
    await Supabase.initialize(
      url: url,
      anonKey: clave,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    supabaseOk = true;
  } catch (e) {
    final msg = e.toString();
    errorSupabase =
        msg.contains('NotInitializedError') || msg.contains('Instance of')
        ? 'Supabase no pudo inicializarse. Revisá las credenciales.'
        : msg;
  }

  // Firebase + push: nativo (Android/iOS) y PWA web. Nunca bloquea el arranque.
  if (supabaseOk && _pushSoportado) {
    try {
      await Firebase.initializeApp(
        options: kIsWeb ? ConfigPushWeb.options : null,
      );
      FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);
      await ServicioPush.instancia.inicializar();
    } catch (e) {
      debugPrint('⚠️ Firebase/push locales no inicializado: $e');
    }
  }

  if (supabaseOk) {
    await TemaAppLocales.instancia.cargar();
    await ModoAppLocales.instancia.cargar();
    runApp(const AppLocales());
  } else {
    runApp(_PantallaErrorConfig(errorSupabase ?? 'Supabase no inicializado'));
  }
}

class _PantallaErrorConfig extends StatelessWidget {
  const _PantallaErrorConfig(this.mensaje);
  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: ColoresLocales.fondoPrincipal,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 24),
                Text(
                  'Error de configuración',
                  style: GoogleFonts.baloo2(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  mensaje,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Text(
                  'En produccion: --dart-define. En local: copiá assets/.env.ejemplo → assets/.env '
                  '(o .env en la raíz del proyecto).',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _cargarEnvLocal() async {
  if (_configFromDefine('URL_SUPABASE').isNotEmpty &&
      _configFromDefine('CLAVE_PUBLICA_SUPABASE').isNotEmpty) {
    return;
  }

  for (final path in ['assets/.env', '.env']) {
    try {
      await dotenv.load(fileName: path);
      final url = (dotenv.env['URL_SUPABASE'] ?? '').trim();
      final clave = (dotenv.env['CLAVE_PUBLICA_SUPABASE'] ?? '').trim();
      if (url.isNotEmpty && clave.isNotEmpty) return;
    } catch (_) {}
  }
}

String _configFromDefine(String key) {
  const urlSupabase = String.fromEnvironment('URL_SUPABASE');
  const clavePublicaSupabase = String.fromEnvironment('CLAVE_PUBLICA_SUPABASE');
  return switch (key) {
    'URL_SUPABASE' => urlSupabase,
    'CLAVE_PUBLICA_SUPABASE' => clavePublicaSupabase,
    _ => '',
  };
}

String _config(String key) {
  final fromDefine = _configFromDefine(key);
  return fromDefine.isNotEmpty ? fromDefine : (dotenv.env[key] ?? '').trim();
}

class AppLocales extends StatefulWidget {
  const AppLocales({super.key});

  @override
  State<AppLocales> createState() => _AppLocalesState();
}

class _AppLocalesState extends State<AppLocales> {
  bool _verificando = true;
  bool _sesionActiva = false;
  bool _perfilCompleto = false;
  bool _staffPerfilCompleto = false;

  @override
  void initState() {
    super.initState();
    _verificarSesion();
  }

  Future<void> _verificarSesion() async {
    await ModoAppLocales.instancia.cargar();
    try {
      final usuario = Supabase.instance.client.auth.currentUser;
      if (usuario != null) {
        unawaited(ServicioPush.instancia.sincronizarSiAutorizado());
        if (ModoAppLocales.instancia.esStaff) {
          final completo = await ServicioStaffLocales().perfilStaffCompleto();
          setState(() {
            _sesionActiva = true;
            _staffPerfilCompleto = completo;
          });
        } else {
          final suspendida = await ServicioEstadoCuentaLocales.instancia
              .refrescar();
          if (suspendida) {
            setState(() {
              _sesionActiva = true;
              _perfilCompleto = true;
            });
          } else {
            final r = await Supabase.instance.client
                .from('perfiles_locales')
                .select('id, nombre_local')
                .eq('id', usuario.id)
                .maybeSingle();
            final nombreLocal = (r?['nombre_local'] as String?)?.trim() ?? '';
            setState(() {
              _sesionActiva = true;
              _perfilCompleto = nombreLocal.isNotEmpty;
            });
          }
        }
      }
    } catch (_) {}
    setState(() => _verificando = false);
  }

  ThemeData _temaApp({required bool oscuro}) {
    return ThemeData(
      useMaterial3: true,
      brightness: oscuro ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: oscuro
          ? ColoresLocales.fondoClaro
          : ColoresLocales.fondoPrincipal,
      cardColor: ColoresLocales.superficie,
      dividerColor: ColoresLocales.separador,
      colorScheme: oscuro
          ? ColorScheme.dark(
              primary: ColoresLocales.acentoVioleta,
              surface: ColoresLocales.superficie,
              onPrimary: ColoresLocales.textoEnBoton,
              onSurface: ColoresLocales.textoOnFondoClaro,
            )
          : ColorScheme.light(
              primary: ColoresLocales.acentoVioleta,
              surface: ColoresLocales.superficie,
              onPrimary: ColoresLocales.textoEnBoton,
              onSurface: ColoresLocales.textoOnFondoClaro,
            ),
      fontFamily: GoogleFonts.baloo2().fontFamily,
    );
  }

  @override
  Widget build(BuildContext context) {
    return TemaLocalesScope(
      notifier: TemaAppLocales.instancia.modoOscuro,
      child: ValueListenableBuilder<bool>(
        valueListenable: TemaAppLocales.instancia.modoOscuro,
        builder: (context, oscuro, _) {
          return AuthGateLocales(
            child: MaterialApp(
              navigatorKey: navigatorKeyLocales,
              builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
                value: BarraSistemaLocales.estilo(oscuro),
                child: ControlInstalarPwa(
                  child: ControlActualizacionWeb(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
              title: 'Fernecito Locales',
              debugShowCheckedModeBanner: false,
              themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
              theme: _temaApp(oscuro: false),
              darkTheme: _temaApp(oscuro: true),
              onGenerateRoute: (settings) =>
                  generarRutaLocales(settings) ??
                  rutaDesconocidaLocales(settings),
              home: _verificando
                  ? const SkeletonPantallaDashboard()
                  : _sesionActiva
                  ? (ModoAppLocales.instancia.esStaff
                        ? (_staffPerfilCompleto
                              ? const LocalesStaffHome()
                              : const LocalesStaffCrearPerfil())
                        : (ServicioEstadoCuentaLocales.instancia.suspendida
                              ? const LocalesCuentaBloqueada()
                              : (_perfilCompleto
                                    ? const LocalesHome()
                                    : const LocalesCrearPerfil())))
                  : (ModoAppLocales.instancia.esStaff
                        ? const LocalesStaffLogin()
                        : const LocalesLogin()),
            ),
          );
        },
      ),
    );
  }
}
