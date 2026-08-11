library;

import 'package:flutter/material.dart';

import '../PANTALLAS/locales_administrar_subscriociones.dart';
import '../PANTALLAS/locales_calificaciones.dart';
import '../PANTALLAS/locales_compras_pagos.dart';
import '../PANTALLAS/locales_contrasena.dart';
import '../PANTALLAS/locales_confirmar_email.dart';
import '../PANTALLAS/locales_crear_cuenta.dart';
import '../core/crear_evento_desde_flyer_args.dart';
import '../PANTALLAS/locales_crear_evento.dart';
import '../PANTALLAS/locales_crear_perfil.dart';
import '../PANTALLAS/locales_flyer_ia.dart';
import '../PANTALLAS/locales_home.dart';
import '../PANTALLAS/locales_login.dart';
import '../PANTALLAS/locales_mejorar_jerarquia.dart';
import '../PANTALLAS/locales_metricas.dart';
import '../PANTALLAS/locales_mis_eventos.dart';
import '../PANTALLAS/locales_mi_cuenta.dart';
import '../PANTALLAS/locales_notificaciones.dart';
import '../PANTALLAS/locales_perfil.dart';
import '../PANTALLAS/locales_perfil_clientes.dart';
import '../PANTALLAS/locales_cambiar_contrasena.dart';
import '../PANTALLAS/locales_plan_dashboard.dart';
import '../PANTALLAS/locales_planes.dart';
import '../PANTALLAS/locales_soporte.dart';
import '../PANTALLAS/locales_staff.dart';
import '../PANTALLAS/locales_staff_actividad.dart';
import '../PANTALLAS/locales_staff_crear_cuenta.dart';
import '../PANTALLAS/locales_staff_crear_perfil.dart';
import '../PANTALLAS/locales_staff_home.dart';
import '../PANTALLAS/locales_staff_login.dart';
import '../PANTALLAS/locales_staff_mi_cuenta.dart';
import '../PANTALLAS/locales_staff_vincular.dart';
import '../PANTALLAS/locales_validar.dart';
import '../PANTALLAS/locales_cuenta_bloqueada.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'recarga_cuenta_locales.dart';
import 'servicio_estado_cuenta_locales.dart';

/// Mapa único de rutas nombradas — usado por [MaterialApp.routes] y [onGenerateRoute].
Map<String, WidgetBuilder> rutasLocales() => {
      '/login': (context) => const LocalesLogin(),
      '/home': (context) {
        final args = ModalRoute.of(context)?.settings.arguments;
        final uid = (args is String && args.isNotEmpty)
            ? args
            : (Supabase.instance.client.auth.currentUser?.id ?? 'anon');
        // Key por uid: remonta Home completo al cambiar de cuenta.
        return LocalesHome(key: ValueKey('home_$uid'));
      },
      rutaRecargarCuenta: (context) => const LocalesRecargarCuenta(),
      '/contrasena': (context) => const LocalesContrasena(),
      '/perfil': (context) => const LocalesPerfil(),
      '/crear_perfil': (context) {
        final args = ModalRoute.of(context)?.settings.arguments;
        final uid = (args is String && args.isNotEmpty)
            ? args
            : (Supabase.instance.client.auth.currentUser?.id ?? 'anon');
        // Key por uid: remonta onboarding al cambiar a otra cuenta incompleta.
        return LocalesCrearPerfil(key: ValueKey('crear_perfil_$uid'));
      },
      '/mi_cuenta': (context) => const LocalesMiCuenta(),
      '/mis_eventos': (context) => const LocalesMisEventos(),
      '/crear_evento': (context) {
        final args = ModalRoute.of(context)?.settings.arguments;
        return LocalesCrearEvento(
          datosFlyer: args is CrearEventoDesdeFlyerArgs ? args : null,
        );
      },
      '/listas': (context) => const LocalesValidar(),
      '/validar': (context) => const LocalesValidar(),
      '/notificaciones': (context) => const LocalesNotificaciones(),
      '/mejorar_jerarquia': (context) => const LocalesMejorarJerarquia(),
      '/administrar_subscripciones': (context) {
        final args = ModalRoute.of(context)?.settings.arguments;
        final pestana = args is int ? args : null;
        return LocalesAdministrarSubscriociones(pestanaInicial: pestana);
      },
      '/soporte': (context) => const LocalesSoporte(),
      '/cuenta_bloqueada': (context) => const LocalesCuentaBloqueada(),
      '/cambiar_contrasena': (context) => const LocalesCambiarContrasena(),
      '/compras_pagos': (context) => const LocalesComprasPagos(),
      '/flyer_ia': (context) => const LocalesFlyerIa(),
      '/staff_login': (context) => const LocalesStaffLogin(),
      '/staff_crear_cuenta': (context) => const LocalesStaffCrearCuenta(),
      '/staff_crear_perfil': (context) => const LocalesStaffCrearPerfil(),
      '/staff_home': (context) => const LocalesStaffHome(),
      '/staff_vincular': (context) => const LocalesStaffVincular(),
      '/staff_actividad': (context) => const LocalesStaffActividad(),
      '/staff_mi_cuenta': (context) => const LocalesStaffMiCuenta(),
      '/metricas': (context) => const LocalesMetricas(),
      '/planes': (context) => const LocalesPlanes(),
      '/planes/detalle': (context) {
        final args = ModalRoute.of(context)?.settings.arguments;
        final id = args is String
            ? args
            : (args is Map && args['id_plan'] != null
                ? args['id_plan'].toString()
                : '');
        return LocalesPlanDashboard(idPlan: id);
      },
      '/staff': (context) => const LocalesStaff(),
      '/calificaciones': (context) => const LocalesCalificaciones(),
      '/perfil_clientes': (context) => const LocalesPerfilClientes(),
      '/crear_cuenta': (context) => const LocalesCrearCuenta(),
      '/confirmar_email': (context) {
        final args = ModalRoute.of(context)?.settings.arguments;
        final email = args is ConfirmarEmailArgs ? args.email : '';
        return LocalesConfirmarEmail(email: email);
      },
    };

Route<dynamic>? generarRutaLocales(RouteSettings settings) {
  final nombre = settings.name;
  if (ServicioEstadoCuentaLocales.instancia.suspendida &&
      !ServicioEstadoCuentaLocales.instancia.rutaPermitida(nombre)) {
    return MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/cuenta_bloqueada'),
      builder: (_) => const LocalesCuentaBloqueada(),
    );
  }
  final builder = rutasLocales()[nombre];
  if (builder == null) return null;
  return MaterialPageRoute<void>(
    settings: settings,
    builder: builder,
  );
}

Route<dynamic> rutaDesconocidaLocales(RouteSettings settings) {
  return MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => Scaffold(
      body: Center(
        child: Text('Ruta no encontrada: ${settings.name ?? ''}'),
      ),
    ),
  );
}
