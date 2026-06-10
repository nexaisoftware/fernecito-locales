/// Servicio para generación de flyers con IA — conecta con las 3 edges de Supabase.
library;

import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';

class FlyerIaService {
  static final FlyerIaService _instancia = FlyerIaService._interno();
  factory FlyerIaService() => _instancia;
  FlyerIaService._interno();

  SupabaseClient get _cliente => ServicioSupabase().cliente;

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Future<String> _accessToken() async {
    var sesion = _cliente.auth.currentSession;
    sesion ??= (await _cliente.auth.refreshSession()).session;
    var token = sesion?.accessToken ?? '';
    token = token.trim();
    if (token.startsWith('Bearer ')) {
      token = token.replaceFirst('Bearer ', '').trim();
    }
    if (token.isEmpty) throw Exception('No hay sesion activa');
    return token;
  }

  String _urlBase() {
    final base = (dotenv.env['URL_SUPABASE'] ?? '').trim();
    if (base.isEmpty) throw Exception('Falta URL_SUPABASE en .env');
    return '${base.replaceFirst(RegExp(r'/+$'), '')}/functions/v1';
  }

  String _apiKey() {
    final key = (dotenv.env['CLAVE_PUBLICA_SUPABASE'] ?? '').trim();
    if (key.isEmpty) throw Exception('Falta CLAVE_PUBLICA_SUPABASE en .env');
    return key;
  }

  Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
    'apikey': _apiKey(),
    'Content-Type': 'application/json',
  };

  // ── Generar flyer (generación nueva o retry) ─────────────────────────────────

  /// [modo]: `estructurado` (templates) o `libre` (prompt de hasta 1000 caracteres).
  Future<FlyerIaResultado> generar({
    String modo = 'estructurado',
    required String titulo,
    String claim = '',
    String diaSemana = '',
    String fecha = '',
    String hora = '',
    String fondoDescripcion = '',
    String estiloId = 'dark_night',
    String? estiloPropio,
    String? promptLibre,
    String? generacionPadreId, // si viene = es retry
    // Opcionales (estructurado)
    String? promos,
    String? lineup,
    String? sponsors,
    String? dresscode,
  }) async {
    final token = await _accessToken();
    final esLibre = modo == 'libre';

    final body = <String, dynamic>{
      'modo': esLibre ? 'libre' : 'estructurado',
      'titulo': titulo,
      if (esLibre) ...{
        'prompt_libre': promptLibre ?? '',
      } else ...{
        'claim': claim,
        'dia_semana': diaSemana,
        'fecha': fecha,
        'hora': hora,
        'fondo_descripcion': fondoDescripcion,
        'estilo_id': estiloId,
        if (estiloPropio != null && estiloPropio.isNotEmpty)
          'estilo_propio': estiloPropio,
        if (promos != null && promos.isNotEmpty) 'promos': promos,
        if (lineup != null && lineup.isNotEmpty) 'lineup': lineup,
        if (sponsors != null && sponsors.isNotEmpty) 'sponsors': sponsors,
        if (dresscode != null && dresscode.isNotEmpty) 'dresscode': dresscode,
      },
      if (generacionPadreId != null) 'generacion_padre_id': generacionPadreId,
    };

    final resp = await http.post(
      Uri.parse('${_urlBase()}/generar_flyer_ia'),
      headers: _headers(token),
      body: jsonEncode(body),
    );

    final data = jsonDecode(resp.body) as Map<String, dynamic>;

    if (resp.statusCode != 200 || data['ok'] != true) {
      final code = data['code'] as String? ?? 'error';
      final mensaje = data['error'] as String? ?? 'Error al generar flyer';
      throw FlyerIaException(code: code, mensaje: mensaje);
    }

    return FlyerIaResultado(
      generacionId: data['generacion_id'] as String,
      urls: List<String>.from(data['urls'] as List),
      creditosRestantes: (data['creditos_restantes'] as num?)?.toInt() ?? 0,
    );
  }

  // ── Confirmar entrega (Flutter avisa que recibió las URLs) ───────────────────

  Future<void> confirmarEntrega(String generacionId) async {
    try {
      final token = await _accessToken();
      await http.post(
        Uri.parse('${_urlBase()}/confirmar_entrega_flyer'),
        headers: _headers(token),
        body: jsonEncode({'generacion_id': generacionId}),
      );
    } catch (_) {
      // No crítico — ignorar silenciosamente
    }
  }

  // ── Verificar si hay un flyer pendiente (recovery ante cortes) ───────────────

  Future<FlyerIaPendiente?> verificarPendiente() async {
    try {
      final token = await _accessToken();
      final resp = await http.get(
        Uri.parse('${_urlBase()}/verificar_flyer_pendiente'),
        headers: _headers(token),
      );
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true || data['pendiente'] == null) return null;

      final p = data['pendiente'] as Map<String, dynamic>;
      final urls = List<String>.from(p['urls'] as List? ?? []);
      if (urls.isEmpty) return null;

      return FlyerIaPendiente(
        generacionId: p['generacion_id'] as String,
        urls: urls,
        titulo: p['titulo'] as String? ?? '',
        estiloNombre: p['estilo_nombre'] as String? ?? '',
        esRetry: p['es_retry'] as bool? ?? false,
        retryUsado: p['retry_usado'] as bool? ?? false,
        createdAt: DateTime.tryParse(p['created_at'] as String? ?? '') ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  // ── Leer créditos reales desde perfiles_locales ──────────────────────────────

  Future<int> obtenerCreditos() async {
    try {
      final uid = _cliente.auth.currentUser?.id;
      if (uid == null) return 0;
      final resp = await _cliente
          .from('perfiles_locales')
          .select('cupos_flyers_ia')
          .eq('id', uid)
          .single();
      return (resp['cupos_flyers_ia'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ── Leer historial real desde flyer_generaciones ─────────────────────────────

  Future<List<FlyerIaGeneracionRemota>> obtenerHistorial() async {
    try {
      final uid = _cliente.auth.currentUser?.id;
      if (uid == null) return [];
      final resp = await _cliente
          .from('flyer_generaciones')
          .select('id, titulo, estilo_nombre, urls_generadas, es_retry, generacion_padre_id, retry_usado, created_at, error_mensaje')
          .eq('local_id', uid)
          .isFilter('error_mensaje', null)
          .order('created_at', ascending: false)
          .limit(50);

      return (resp as List).map((row) {
        final m = row as Map<String, dynamic>;
        return FlyerIaGeneracionRemota(
          id: m['id'] as String,
          titulo: m['titulo'] as String? ?? '',
          estiloNombre: m['estilo_nombre'] as String? ?? '',
          urls: List<String>.from(m['urls_generadas'] as List? ?? []),
          esRetry: m['es_retry'] as bool? ?? false,
          retryUsado: m['retry_usado'] as bool? ?? false,
          createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}

// ─── Modelos ──────────────────────────────────────────────────────────────────

class FlyerIaResultado {
  const FlyerIaResultado({
    required this.generacionId,
    required this.urls,
    required this.creditosRestantes,
  });
  final String generacionId;
  final List<String> urls;
  final int creditosRestantes;
}

class FlyerIaPendiente {
  const FlyerIaPendiente({
    required this.generacionId,
    required this.urls,
    required this.titulo,
    required this.estiloNombre,
    required this.esRetry,
    required this.retryUsado,
    required this.createdAt,
  });
  final String generacionId;
  final List<String> urls;
  final String titulo;
  final String estiloNombre;
  final bool esRetry;
  final bool retryUsado;
  final DateTime createdAt;
}

class FlyerIaGeneracionRemota {
  const FlyerIaGeneracionRemota({
    required this.id,
    required this.titulo,
    required this.estiloNombre,
    required this.urls,
    required this.esRetry,
    required this.retryUsado,
    required this.createdAt,
  });
  final String id;
  final String titulo;
  final String estiloNombre;
  final List<String> urls;
  final bool esRetry;
  final bool retryUsado;
  final DateTime createdAt;

  bool get puedeReintentar =>
      !retryUsado &&
      DateTime.now().isBefore(createdAt.add(const Duration(minutes: 10)));

  int get minutosRestantesReintento {
    final fin = createdAt.add(const Duration(minutes: 10));
    final s = fin.difference(DateTime.now()).inSeconds;
    if (s <= 0) return 0;
    return (s / 60).ceil();
  }
}

class FlyerIaException implements Exception {
  const FlyerIaException({required this.code, required this.mensaje});
  final String code;
  final String mensaje;

  @override
  String toString() => 'FlyerIaException($code): $mensaje';
}
