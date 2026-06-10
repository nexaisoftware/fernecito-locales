/// Servicio de caché local para flyers IA.
///
/// Flujo:
///   1. Edge genera imágenes y las sube a Supabase Storage.
///   2. Flutter recibe las URLs → llama a [guardarGeneracion] que descarga
///      cada imagen al directorio de documentos del dispositivo.
///   3. Flutter llama a [confirmarEntrega] en la edge → la edge borra el Storage.
///   4. La próxima vez que el usuario abre la pantalla, las imágenes se leen
///      desde el disco local sin necesidad de red.
///
/// Las imágenes se guardan como JPEG comprimido (calidad 75) para ahorrar espacio.
/// El índice de generaciones se persiste en SharedPreferences, incluyendo el
/// formulario capturado para poder pre-rellenar el retry.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../core/comprimir_imagen_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Modelo de formulario serializable ────────────────────────────────────
// Espejo plano de LocalesFlyerFormSnapshot sin depender del archivo de pantalla.

class FlyerCacheFormulario {
  const FlyerCacheFormulario({
    this.modo = 'estructurado',
    this.promptLibre,
    required this.claim,
    required this.fondo,
    required this.estiloId,
    required this.mostrarPropio,
    required this.textoPropio,
    required this.diaIdx,
    required this.diaMes,
    required this.mesIdx,
    required this.hora,
    required this.minuto,
  });

  /// `estructurado` | `libre`
  final String modo;
  final String? promptLibre;
  final String claim;
  final String fondo;
  final String estiloId;
  final bool mostrarPropio;
  final String textoPropio;
  final int diaIdx;
  final int diaMes;
  final int mesIdx;
  final int hora;
  final int minuto;

  Map<String, dynamic> toJson() => {
        'modo': modo,
        if (promptLibre != null && promptLibre!.isNotEmpty)
          'prompt_libre': promptLibre,
        'claim': claim,
        'fondo': fondo,
        'estilo_id': estiloId,
        'mostrar_propio': mostrarPropio,
        'texto_propio': textoPropio,
        'dia_idx': diaIdx,
        'dia_mes': diaMes,
        'mes_idx': mesIdx,
        'hora': hora,
        'minuto': minuto,
      };

  factory FlyerCacheFormulario.fromJson(Map<String, dynamic> m) =>
      FlyerCacheFormulario(
        modo: m['modo'] as String? ?? 'estructurado',
        promptLibre: m['prompt_libre'] as String?,
        claim: m['claim'] as String? ?? '',
        fondo: m['fondo'] as String? ?? '',
        estiloId: m['estilo_id'] as String? ?? '',
        mostrarPropio: m['mostrar_propio'] as bool? ?? false,
        textoPropio: m['texto_propio'] as String? ?? '',
        diaIdx: m['dia_idx'] as int? ?? 4,
        diaMes: m['dia_mes'] as int? ?? 1,
        mesIdx: m['mes_idx'] as int? ?? 0,
        hora: m['hora'] as int? ?? 22,
        minuto: m['minuto'] as int? ?? 0,
      );
}

// ─── Modelo de generación cacheada ─────────────────────────────────────────

class FlyerCacheGeneracion {
  const FlyerCacheGeneracion({
    required this.id,
    required this.titulo,
    required this.estiloNombre,
    required this.localPaths,
    required this.esRetry,
    required this.retryUsado,
    required this.createdAt,
    this.formulario,
  });

  final String id;
  final String titulo;
  final String estiloNombre;

  /// Rutas absolutas en el dispositivo de cada imagen (0–3).
  final List<String> localPaths;
  final bool esRetry;
  final bool retryUsado;
  final DateTime createdAt;

  /// Formulario capturado al generar — disponible para pre-rellenar el retry.
  final FlyerCacheFormulario? formulario;

  bool get puedeReintentar =>
      !retryUsado &&
      !esRetry &&
      DateTime.now().isBefore(createdAt.add(const Duration(minutes: 10)));

  int get minutosRestantesReintento {
    final fin = createdAt.add(const Duration(minutes: 10));
    final s = fin.difference(DateTime.now()).inSeconds;
    if (s <= 0) return 0;
    return (s / 60).ceil();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'titulo': titulo,
        'estilo_nombre': estiloNombre,
        'local_paths': localPaths,
        'es_retry': esRetry,
        'retry_usado': retryUsado,
        'created_at': createdAt.toIso8601String(),
        if (formulario != null) 'formulario': formulario!.toJson(),
      };

  factory FlyerCacheGeneracion.fromJson(Map<String, dynamic> m) =>
      FlyerCacheGeneracion(
        id: m['id'] as String,
        titulo: m['titulo'] as String? ?? '',
        estiloNombre: m['estilo_nombre'] as String? ?? '',
        localPaths: List<String>.from(m['local_paths'] as List? ?? []),
        esRetry: m['es_retry'] as bool? ?? false,
        retryUsado: m['retry_usado'] as bool? ?? false,
        createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
        formulario: m['formulario'] != null
            ? FlyerCacheFormulario.fromJson(m['formulario'] as Map<String, dynamic>)
            : null,
      );
}

// ─── Servicio de caché ──────────────────────────────────────────────────────

class FlyerCacheService {
  static final FlyerCacheService _instancia = FlyerCacheService._interno();
  factory FlyerCacheService() => _instancia;
  FlyerCacheService._interno();

  static const String _kPrefKey = 'flyer_ia_cache_v1';
  static const int _kCalidadJpeg = 75;

  // ── Directorio base ──────────────────────────────────────────────────────

  Future<Directory> _dirBase() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/flyers_ia_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ── Leer índice desde SharedPreferences ─────────────────────────────────

  Future<List<FlyerCacheGeneracion>> cargarTodas() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPrefKey);
      if (raw == null || raw.isEmpty) return [];
      final lista = jsonDecode(raw) as List<dynamic>;
      return lista
          .map((e) => FlyerCacheGeneracion.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('FlyerCacheService.cargarTodas error: $e');
      return [];
    }
  }

  Future<void> _guardarIndice(List<FlyerCacheGeneracion> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kPrefKey, jsonEncode(items.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('FlyerCacheService._guardarIndice error: $e');
    }
  }

  // ── Guardar una nueva generación ─────────────────────────────────────────

  Future<FlyerCacheGeneracion> guardarGeneracion({
    required String id,
    required String titulo,
    required String estiloNombre,
    required List<String> urls,
    required bool esRetry,
    required bool retryUsado,
    required DateTime createdAt,
    FlyerCacheFormulario? formulario,
  }) async {
    final dir = await _dirBase();
    final genDir = Directory('${dir.path}/$id');
    if (!await genDir.exists()) await genDir.create(recursive: true);

    final localPaths = <String>[];

    for (var i = 0; i < urls.length; i++) {
      final url = urls[i];
      final destino = '${genDir.path}/$i.jpg';
      try {
        final bytes = await _descargarImagen(url);
        final comprimido = await _comprimir(bytes);
        await File(destino).writeAsBytes(comprimido);
        localPaths.add(destino);
      } catch (e) {
        debugPrint('FlyerCacheService: fallo descarga imagen $i: $e');
        localPaths.add('');
      }
    }

    final generacion = FlyerCacheGeneracion(
      id: id,
      titulo: titulo,
      estiloNombre: estiloNombre,
      localPaths: localPaths,
      esRetry: esRetry,
      retryUsado: retryUsado,
      createdAt: createdAt,
      formulario: formulario,
    );

    final todas = await cargarTodas();
    final idx = todas.indexWhere((g) => g.id == id);
    if (idx >= 0) {
      todas[idx] = generacion;
    } else {
      todas.insert(0, generacion);
    }
    await _guardarIndice(todas);

    return generacion;
  }

  // ── Marcar retry usado en el registro del PADRE ───────────────────────────
  // id = ID del padre (generación original), no del retry

  Future<void> marcarRetryUsado(String idPadre) async {
    final todas = await cargarTodas();
    final idx = todas.indexWhere((g) => g.id == idPadre);
    if (idx < 0) return;
    final g = todas[idx];
    todas[idx] = FlyerCacheGeneracion(
      id: g.id,
      titulo: g.titulo,
      estiloNombre: g.estiloNombre,
      localPaths: g.localPaths,
      esRetry: g.esRetry,
      retryUsado: true,
      createdAt: g.createdAt,
      formulario: g.formulario,
    );
    await _guardarIndice(todas);
  }

  // ── Actualizar paths locales del padre tras un retry exitoso ──────────────
  // Reemplaza las imágenes del padre con las nuevas del retry

  Future<void> actualizarPathsRetry({
    required String idPadre,
    required List<String> nuevosLocalPaths,
    required List<String> nuevasUrls,
  }) async {
    final dir = await _dirBase();
    final todas = await cargarTodas();
    final idx = todas.indexWhere((g) => g.id == idPadre);
    if (idx < 0) return;
    final g = todas[idx];

    // Descargar nuevas imágenes en el directorio del padre (sobreescribe las anteriores)
    final localPaths = <String>[];
    final genDir = Directory('${dir.path}/$idPadre');
    if (!await genDir.exists()) await genDir.create(recursive: true);

    for (var i = 0; i < nuevasUrls.length; i++) {
      final destino = '${genDir.path}/$i.jpg';
      if (nuevosLocalPaths.length > i && nuevosLocalPaths[i].isNotEmpty) {
        // Ya tenemos el path local del retry, moverlo al directorio del padre
        try {
          final src = File(nuevosLocalPaths[i]);
          if (await src.exists()) {
            await src.copy(destino);
            localPaths.add(destino);
            continue;
          }
        } catch (_) {}
      }
      // Fallback: descargar desde URL remota
      try {
        final bytes = await _descargarImagen(nuevasUrls[i]);
        final comprimido = await _comprimir(bytes);
        await File(destino).writeAsBytes(comprimido);
        localPaths.add(destino);
      } catch (e) {
        debugPrint('actualizarPathsRetry: fallo imagen $i: $e');
        localPaths.add('');
      }
    }

    todas[idx] = FlyerCacheGeneracion(
      id: g.id,
      titulo: g.titulo,
      estiloNombre: g.estiloNombre,
      localPaths: localPaths,
      esRetry: g.esRetry,
      retryUsado: true,
      createdAt: g.createdAt,
      formulario: g.formulario,
    );
    await _guardarIndice(todas);
  }

  // ── Verificar archivos físicos ───────────────────────────────────────────

  Future<bool> tieneImagenesLocales(String id) async {
    final todas = await cargarTodas();
    final gen = todas.where((g) => g.id == id).firstOrNull;
    if (gen == null) return false;
    for (final path in gen.localPaths) {
      if (path.isNotEmpty && await File(path).exists()) return true;
    }
    return false;
  }

  // ── Helpers privados ─────────────────────────────────────────────────────

  Future<Uint8List> _descargarImagen(String url) async {
    final resp =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode} al descargar $url');
    }
    return resp.bodyBytes;
  }

  Future<Uint8List> _comprimir(Uint8List bytes) async {
    try {
      final r = await comprimirImagenStorage(
        bytes,
        perfil: PerfilImagenStorage.flyerCacheLocal,
      );
      return r.bytes;
    } catch (_) {
      return bytes;
    }
  }
}
