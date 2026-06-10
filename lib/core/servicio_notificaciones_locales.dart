library;

import 'package:flutter/foundation.dart';
import '../models/notificacion.dart';
import 'supabase_client.dart';

/// Servicio singleton para leer / marcar / borrar notificaciones del local.
///
/// Expone también un `ValueNotifier<int> contadorNoLeidas` para que el bottom
/// nav (o cualquier widget) muestre un badge reactivo. Se refresca cuando:
/// - se llama `refrescarContador()` (al abrir app o foreground)
/// - se marca una como leída
/// - se borra una notificación
class ServicioNotificacionesLocales {
  static final ServicioNotificacionesLocales _instancia = ServicioNotificacionesLocales._interno();
  factory ServicioNotificacionesLocales() => _instancia;
  ServicioNotificacionesLocales._interno();

  /// Total de notificaciones no leídas del local actual.
  /// Lo usa el badge del bottom nav.
  final ValueNotifier<int> contadorNoLeidas = ValueNotifier<int>(0);

  String? get _uid => ServicioSupabase().usuarioActual?.id;

  /// Lista las notificaciones del local actual (más recientes primero).
  /// Filtra automáticamente las expiradas.
  Future<List<Notificacion>> listar({int limit = 50}) async {
    final uid = _uid;
    if (uid == null) return const [];

    try {
      final data = await ServicioSupabase().cliente
          .from('notificaciones_locales')
          .select()
          .eq('id_local', uid)
          .gte('fecha_expiracion', DateTime.now().toUtc().toIso8601String())
          .order('fecha_creacion', ascending: false)
          .limit(limit);

      return (data as List)
          .cast<Map<String, dynamic>>()
          .map(Notificacion.fromMap)
          .toList();
    } catch (e) {
      debugPrint('⚠️ listar notificaciones: $e');
      return const [];
    }
  }

  /// Sincroniza el badge con una lista ya cargada (p. ej. tab Notificaciones).
  void sincronizarDesdeLista(List<Notificacion> lista) {
    contadorNoLeidas.value = lista.where((n) => !n.leida).length;
  }

  /// Refresca el contador de no leídas (consulta puntual a la DB).
  Future<int> refrescarContador() async {
    final uid = _uid;
    if (uid == null) {
      contadorNoLeidas.value = 0;
      return 0;
    }
    try {
      final rows = await ServicioSupabase().cliente
          .from('notificaciones_locales')
          .select('id')
          .eq('id_local', uid)
          .eq('leida', false)
          .gte('fecha_expiracion', DateTime.now().toUtc().toIso8601String());
      final count = (rows as List).length;
      contadorNoLeidas.value = count;
      return count;
    } catch (e) {
      debugPrint('⚠️ refrescarContador: $e');
      return contadorNoLeidas.value;
    }
  }

  /// Marca una notificación específica como leída.
  Future<bool> marcarLeida(String idNotif) async {
    try {
      await ServicioSupabase().cliente
          .from('notificaciones_locales')
          .update({
            'leida': true,
            'fecha_lectura': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', idNotif)
          .eq('leida', false); // idempotente: si ya estaba leída no hace nada
      return true;
    } catch (e) {
      debugPrint('⚠️ marcarLeida: $e');
      return false;
    }
  }

  /// Marca todas las no-leídas del local como leídas.
  Future<bool> marcarTodasLeidas() async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await ServicioSupabase().cliente
          .from('notificaciones_locales')
          .update({
            'leida': true,
            'fecha_lectura': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id_local', uid)
          .eq('leida', false);
      contadorNoLeidas.value = 0;
      return true;
    } catch (e) {
      debugPrint('⚠️ marcarTodasLeidas: $e');
      return false;
    }
  }

  /// Borra una notificación (deja al usuario "limpiar" su feed).
  Future<bool> borrar(String idNotif) async {
    try {
      await ServicioSupabase().cliente
          .from('notificaciones_locales')
          .delete()
          .eq('id', idNotif);
      await refrescarContador();
      return true;
    } catch (e) {
      debugPrint('⚠️ borrar notif: $e');
      return false;
    }
  }
}
