library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'supabase_client.dart';

/// Excepción tipada para errores de edges. Permite al UI distinguir códigos
/// específicos (ej. 'already_canjeado' → success silencioso) sin parsear
/// strings de error.
class EdgeException implements Exception {
  EdgeException({
    required this.funcion,
    required this.status,
    required this.code,
    required this.mensaje,
    this.detail,
  });

  final String funcion;
  final int status;
  final String code;
  final String mensaje;
  final String? detail;

  /// True si el error indica que la operación ya estaba aplicada (idempotente).
  bool get yaAplicada =>
      code == 'already_canjeado' ||
      code == 'already_rechazado' ||
      code == 'already_cancelado' ||
      code == 'stale_pending_state';

  @override
  String toString() =>
      'EdgeException($funcion → $status $code: $mensaje${detail != null ? " — $detail" : ""})';
}

class ServicioEdgesEventos {
  static final ServicioEdgesEventos _instancia =
      ServicioEdgesEventos._interno();
  factory ServicioEdgesEventos() => _instancia;
  ServicioEdgesEventos._interno();

  SupabaseClient get _cliente => ServicioSupabase().cliente;

  Future<String> _accessToken({bool forzarRefresh = false}) async {
    if (forzarRefresh) {
      await _cliente.auth.refreshSession();
    }

    var sesion = _cliente.auth.currentSession;
    sesion ??= (await _cliente.auth.refreshSession()).session;
    var token = sesion?.accessToken ?? '';
    token = token.trim();
    if (token.startsWith('Bearer ')) {
      token = token.replaceFirst('Bearer ', '').trim();
    }
    if (token.isEmpty) {
      throw Exception(
        'No hay sesion activa para invocar la Edge. Volve a iniciar sesion en la app.',
      );
    }
    if (token.split('.').length != 3) {
      throw Exception(
        'Token de sesion con formato invalido para JWT. Cerra sesion y volve a iniciar.',
      );
    }
    return token;
  }

  String _urlFunctionsBase() {
    final base = (ConfiguracionSupabase.obtenerUrl() ?? '').trim();
    if (base.isEmpty) {
      throw Exception('Falta URL_SUPABASE en .env');
    }
    return '${base.replaceFirst(RegExp(r'/+$'), '')}/functions/v1';
  }

  String _apiKeyPublica() {
    final key = (ConfiguracionSupabase.obtenerClavePublica() ?? '').trim();
    if (key.isEmpty) {
      throw Exception('Falta CLAVE_PUBLICA_SUPABASE en .env');
    }
    return key;
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  Map<String, dynamic> _jwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return {};
      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final payload = jsonDecode(decoded);
      if (payload is Map<String, dynamic>) return payload;
      if (payload is Map) return Map<String, dynamic>.from(payload);
      return {};
    } catch (_) {
      return {};
    }
  }

  void _logAuthDebug({
    required String funcion,
    required String etapa,
    required String token,
    Object? extra,
  }) {
    final payload = _jwtPayload(token);
    final iss = (payload['iss'] ?? '').toString();
    final ref = iss.contains('/auth/v1')
        ? iss.split('.supabase.co').first.split('//').last
        : iss;
    final sub = (payload['sub'] ?? '').toString();
    final exp = (payload['exp'] ?? '').toString();
    print(
      '[EDGE_AUTH][$funcion][$etapa] ref=$ref sub=$sub exp=$exp extra=$extra',
    );
  }

  String _estadoExpToken(String token) {
    final payload = _jwtPayload(token);
    final expRaw = payload['exp'];
    final exp = expRaw is int ? expRaw : int.tryParse(expRaw?.toString() ?? '');
    if (exp == null) return 'exp_desconocida';
    final ahora = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final delta = exp - ahora;
    if (delta <= 0) return 'expirado_hace_${delta.abs()}s';
    return 'vigente_${delta}s';
  }

  String _mensaje401Diagnostico({
    required String funcion,
    required String token,
    Object? detalle,
  }) {
    final payload = _jwtPayload(token);
    final iss = (payload['iss'] ?? '').toString();
    final refToken = iss.contains('/auth/v1')
        ? iss.split('.supabase.co').first.split('//').last
        : 'desconocido';
    final refApp = _refDesdeEnv();
    final sub = (payload['sub'] ?? '').toString();
    final estadoExp = _estadoExpToken(token);

    return [
      'No autenticado (401) al invocar "$funcion".',
      'Ref app: $refApp',
      'Ref token: $refToken',
      'User(sub): ${sub.isEmpty ? "desconocido" : sub}',
      'Estado token: $estadoExp',
      if (detalle != null) 'Detalle Edge: $detalle',
      'Tip: si Ref app y Ref token no coinciden, la app y la Edge estan en proyectos distintos.',
    ].join('\n');
  }

  String _refDesdeEnv() {
    try {
      final url = (ConfiguracionSupabase.obtenerUrl() ?? '').trim();
      if (url.isEmpty) return 'desconocido_env_vacio';
      final host = Uri.parse(url).host;
      if (!host.contains('.supabase.co')) return host;
      return host.split('.supabase.co').first;
    } catch (_) {
      return 'desconocido_env_error';
    }
  }

  String _mensajeEdgeHttpError({
    required String funcion,
    required int status,
    required Map<String, dynamic> data,
  }) {
    final ok = data['ok'];
    final error = data['error']?.toString();
    final detail = data['detail']?.toString();
    final code = data['code']?.toString();
    final base = 'Edge "$funcion" respondio HTTP $status (ok=$ok).';
    final partes = <String>[base];
    if (error != null && error.isNotEmpty) partes.add('Error: $error');
    if (detail != null && detail.isNotEmpty) partes.add('Detalle: $detail');
    if (code != null && code.isNotEmpty) partes.add('Code: $code');
    return partes.join('\n');
  }

  /// Timeout duro: 15s. Más que suficiente para edges normales (~200-800ms)
  /// y un buffer para mala red. Si excede, el bouncer ve error claro en vez
  /// de spinner infinito.
  static const Duration _edgeTimeout = Duration(seconds: 15);

  Future<_EdgeHttpResult> _invokeHttp(
    String nombreFuncion, {
    required String token,
    required Map<String, dynamic> body,
    Duration? timeout,
  }) async {
    final url = Uri.parse('${_urlFunctionsBase()}/$nombreFuncion');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'apikey': _apiKeyPublica(),
      'Authorization': 'Bearer $token',
    };

    final http.Response response;
    try {
      response = await http
          .post(url, headers: headers, body: jsonEncode(body))
          .timeout(timeout ?? _edgeTimeout);
    } on TimeoutException {
      throw EdgeException(
        funcion: nombreFuncion,
        status: 0,
        code: 'edge_timeout',
        mensaje:
            'La operación tardó demasiado. Revisá tu conexión e intentá de nuevo.',
      );
    } catch (e) {
      throw EdgeException(
        funcion: nombreFuncion,
        status: 0,
        code: 'network_error',
        mensaje: 'No se pudo conectar con el servidor. Revisá tu conexión.',
        detail: e.toString(),
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (e) {
      // Body no es JSON válido — loggear para diagnóstico futuro.
      debugPrint(
        '⚠️ edge[$nombreFuncion] body no-JSON (status ${response.statusCode}): ${response.body}',
      );
      decoded = null;
    }
    final data = _asMap(decoded);
    return _EdgeHttpResult(
      status: response.statusCode,
      data: data,
      rawBody: response.body,
    );
  }

  Future<_EdgeHttpResult> _invocarConReintento(
    String nombreFuncion, {
    required Map<String, dynamic> body,
    Duration? timeout,
  }) async {
    final tokenInicial = await _accessToken();
    _logAuthDebug(
      funcion: nombreFuncion,
      etapa: 'primer_intento',
      token: tokenInicial,
    );

    final primer = await _invokeHttp(
      nombreFuncion,
      token: tokenInicial,
      body: body,
      timeout: timeout,
    );
    if (primer.status != 401) return primer;
    _logAuthDebug(
      funcion: nombreFuncion,
      etapa: 'error_401_primer_intento',
      token: tokenInicial,
      extra: primer.data.isNotEmpty ? primer.data : primer.rawBody,
    );

    final tokenRefrescado = await _accessToken(forzarRefresh: true);
    _logAuthDebug(
      funcion: nombreFuncion,
      etapa: 'segundo_intento',
      token: tokenRefrescado,
    );

    final segundo = await _invokeHttp(
      nombreFuncion,
      token: tokenRefrescado,
      body: body,
      timeout: timeout,
    );
    if (segundo.status != 401) return segundo;

    final detalle401 = segundo.data.isNotEmpty ? segundo.data : segundo.rawBody;
    throw EdgeException(
      funcion: nombreFuncion,
      status: 401,
      code: 'auth_refresh_failed',
      mensaje: _mensaje401Diagnostico(
        funcion: nombreFuncion,
        token: tokenRefrescado,
        detalle: detalle401,
      ),
      detail: detalle401.toString(),
    );
  }

  Future<_EdgeHttpResult> _handleEdge(
    String funcion, {
    required Map<String, dynamic> body,
    Duration? timeout,
  }) async {
    final res = await _invocarConReintento(
      funcion,
      body: body,
      timeout: timeout,
    );

    // Caso éxito real: HTTP 2xx + body.ok truthy (bool o string "true")
    final okBody = res.data['ok'];
    final okTruthy =
        okBody == true ||
        okBody == 1 ||
        (okBody is String && okBody.toLowerCase() == 'true');
    if (res.status >= 200 && res.status < 300 && okTruthy) {
      return res;
    }

    // Caso falla: extraer code y mensaje del body de la edge si vienen
    final code = (res.data['code']?.toString() ?? '').trim();
    final mensaje =
        (res.data['error']?.toString() ?? res.data['message']?.toString() ?? '')
            .trim();
    final detail = res.data['detail']?.toString();

    // Log diagnóstico: si la edge dió 2xx pero ok!=true (body raro) → loggear
    if (res.status >= 200 && res.status < 300 && res.data['ok'] != true) {
      debugPrint(
        '⚠️ edge[$funcion] status ${res.status} pero ok!=true. body=${res.rawBody}',
      );
    }

    if (res.status == 401) {
      final token = await _accessToken();
      throw EdgeException(
        funcion: funcion,
        status: 401,
        code: code.isNotEmpty ? code : 'unauthorized',
        mensaje: _mensaje401Diagnostico(
          funcion: funcion,
          token: token,
          detalle: res.data.isNotEmpty ? res.data : res.rawBody,
        ),
      );
    }

    throw EdgeException(
      funcion: funcion,
      status: res.status,
      code: code.isNotEmpty ? code : 'edge_error',
      mensaje: mensaje.isNotEmpty
          ? mensaje
          : _mensajeEdgeHttpError(
              funcion: funcion,
              status: res.status,
              data: res.data,
            ),
      detail: detail,
    );
  }

  Future<String> subirEvento({
    required Map<String, dynamic> payloadEvento,
    required List<Map<String, dynamic>> promociones,
  }) async {
    try {
      final res = await _handleEdge(
        'subir_evento',
        body: {'payload_evento': payloadEvento, 'promociones': promociones},
      );
      final data = res.data;
      return data['id_evento'].toString();
    } on Exception {
      rethrow;
    }
  }

  /// Edita un evento. [campos] es un mapa plano con solo los campos a cambiar
  /// (nombre_evento, descripcion, modo_lista, cupo_lista_max, hora_limite_canje,
  ///  permite_squads, edad_minima, ciudad_evento, provincia_evento, flyer_url,
  ///  precio_entrada, dresscode, lineup, sponsors, estado_publicacion, etc.)
  Future<Map<String, dynamic>> editarEvento({
    required String idEvento,
    required Map<String, dynamic> campos,
  }) async {
    try {
      final res = await _handleEdge(
        'editar_evento',
        body: {'id_evento': idEvento, 'payload_evento': campos},
      );
      return res.data;
    } on Exception {
      rethrow;
    }
  }

  /// Cancela (despublica) un evento publicado.
  /// El evento pasa a estado 'cancelado' y aparece en historial con badge de cancelado.
  Future<void> cancelarEvento({required String idEvento}) async {
    try {
      await _handleEdge(
        'editar_evento',
        body: {
          'id_evento': idEvento,
          'payload_evento': {'estado_publicacion': 'cancelado'},
        },
      );
    } on Exception {
      rethrow;
    }
  }

  /// Re-publica un evento previamente cancelado.
  Future<void> republicarEvento({required String idEvento}) async {
    try {
      await _handleEdge(
        'editar_evento',
        body: {
          'id_evento': idEvento,
          'payload_evento': {'estado_publicacion': 'publicado'},
        },
      );
    } on Exception {
      rethrow;
    }
  }

  Future<void> borrarEvento({required String idEvento}) async {
    try {
      await _handleEdge('borrar_evento', body: {'id_evento': idEvento});
    } on Exception {
      rethrow;
    }
  }

  /// Acepta o rechaza una reserva pendiente. Devuelve el resultado incluyendo
  /// [overflow]=true si se aceptó por encima del cupo_lista_max (modo manual).
  Future<Map<String, dynamic>> gestionarAsistencia({
    String? idToken,
    String? idReservaGrupal,
    required String accion,
  }) async {
    final res = await _handleEdge(
      'gestionar_asistencia',
      body: {
        if (idToken != null && idToken.isNotEmpty) 'id_token': idToken,
        if (idReservaGrupal != null && idReservaGrupal.isNotEmpty)
          'id_reserva_grupal': idReservaGrupal,
        'accion': accion,
      },
    );
    return res.data;
  }

  /// Valida o rechaza un token de asistencia en la puerta del evento.
  /// [accion]: 'validar' (default) | 'rechazar'
  Future<Map<String, dynamic>> canjearAsistencia({
    required String codigoPuerta,
    required String idLocal,
    required String idEvento,
    String accion = 'validar',
  }) async {
    final res = await _handleEdge(
      'canjear_asistencia',
      body: {
        'codigo_puerta': codigoPuerta.trim().toUpperCase(),
        'id_local': idLocal,
        'id_evento': idEvento,
        'accion': accion,
      },
    );
    return res.data;
  }

  /// Valida o rechaza un token de promoción.
  /// [accion]: 'validar' (default) | 'rechazar'

  Future<void> guardarPerfilLocal({
    required Map<String, dynamic> perfil,
    String modo = 'basico',
    bool solicitarVerificacion = false,
  }) async {
    await _handleEdge(
      'guardar_perfil_local',
      body: {
        'perfil': perfil,
        'modo': modo,
        'solicitar_verificacion': solicitarVerificacion,
      },
    );
  }

  Future<void> eliminarCuentaLocal() async {
    await _handleEdge('eliminar_cuenta_local', body: const {});
  }

  /// Promptera del chatbot de creación de EVENTO (capa aditiva, NO guarda nada).
  /// [intent]: 'fechas' | 'tipo' | 'descripcion'.
  /// - fechas → { entendido, fecha_inicio, fecha_fin, resumen }.
  /// - tipo → { tipo }.
  /// - descripcion → { descripcion }.
  Future<Map<String, dynamic>> asistenteEventoLocal({
    required String intent,
    required String texto,
    Map<String, dynamic>? contexto,
  }) async {
    final res = await _handleEdge(
      'asistente_evento_local',
      body: {
        'intent': intent,
        'texto': texto,
        if (contexto != null) 'contexto': contexto,
      },
    );
    return res.data;
  }

  /// Promptera del chatbot de creación de perfil (capa aditiva, NO guarda nada).
  /// [intent]: 'horarios' | 'descripcion'.
  /// - horarios → { horarios_json, resumen, entendido } (contexto opcional: es_correccion, texto_anterior, resumen_anterior).
  /// - descripcion → { descripcion, rubros } (contexto opcional: nombre_local, rubros).
  Future<Map<String, dynamic>> asistentePerfilLocal({
    required String intent,
    required String texto,
    Map<String, dynamic>? contexto,
  }) async {
    final res = await _handleEdge(
      'asistente_perfil_local',
      body: {
        'intent': intent,
        'texto': texto,
        if (contexto != null) 'contexto': contexto,
      },
    );
    return res.data;
  }

  /// Asistente de carta/precios del local.
  /// - accion=parsear: devuelve { items, advertencias } sin guardar.
  /// - accion=guardar: reemplaza la carta activa con items confirmados.
  Future<Map<String, dynamic>> asistenteCartaLocal({
    required String accion,
    String modo = 'texto',
    String? texto,
    String? url,
    String? archivoDataUri,
    String? archivoNombre,
    String? imagenDataUri,
    List<String>? imagenesDataUri,
    String? archivoPath,
    List<String>? imagenesPaths,
    List<Map<String, dynamic>>? items,
    String? origen,
  }) async {
    final res = await _handleEdge(
      'asistente_carta_local',
      timeout: const Duration(seconds: 105),
      body: {
        'accion': accion,
        'modo': modo,
        if (texto != null) 'texto': texto,
        if (url != null) 'url': url,
        if (archivoDataUri != null) 'archivo_data_uri': archivoDataUri,
        if (archivoNombre != null) 'archivo_nombre': archivoNombre,
        if (imagenDataUri != null) 'imagen_data_uri': imagenDataUri,
        if (imagenesDataUri != null) 'imagenes_data_uri': imagenesDataUri,
        if (archivoPath != null) 'archivo_path': archivoPath,
        if (imagenesPaths != null) 'imagenes_paths': imagenesPaths,
        if (items != null) 'items': items,
        if (origen != null) 'origen': origen,
      },
    );
    return res.data;
  }

  /// Gestión de staff del local (owner) o vinculación (usuario staff).
  Future<Map<String, dynamic>> gestionarStaff({
    required String accion,
    String? idStaff,
    String? idLocal,
    bool? activo,
    String? localUsername,
    String? claveVinculacion,
    bool? habilitadoQrPromos,
    bool? habilitadoQrPases,
    bool? habilitadoAceptarListas,
    bool? habilitadoVerListaAceptados,
    bool? habilitadoQrInvitacion,
    bool? qrInvitacionPasarCupo,
  }) async {
    final res = await _handleEdge(
      'gestionar_staff',
      body: {
        'accion': accion,
        if (idStaff != null && idStaff.isNotEmpty) 'id_staff': idStaff,
        if (idLocal != null && idLocal.isNotEmpty) 'id_local': idLocal,
        'activo': ?activo,
        if (localUsername != null && localUsername.trim().isNotEmpty)
          'local_username': localUsername.trim(),
        if (claveVinculacion != null && claveVinculacion.trim().isNotEmpty)
          'clave_vinculacion': claveVinculacion.trim().toUpperCase(),
        'habilitado_qr_promos': ?habilitadoQrPromos,
        'habilitado_qr_pases': ?habilitadoQrPases,
        'habilitado_aceptar_listas': ?habilitadoAceptarListas,
        'habilitado_ver_lista_aceptados': ?habilitadoVerListaAceptados,
        'habilitado_qr_invitacion': ?habilitadoQrInvitacion,
        'qr_invitacion_pasar_cupo': ?qrInvitacionPasarCupo,
      },
    );
    return res.data;
  }

  /// Genera (o recupera) el QR de invitación de RRPP para un evento.
  /// Devuelve {id_invitacion, tipo, pasar_cupo}. El id_invitacion es el payload
  /// del QR. Reutilizable sin tope. Lo puede llamar el dueño o un staff con el
  /// permiso habilitado_qr_invitacion.
  Future<Map<String, dynamic>> generarInvitacionRrpp({
    required String idEvento,
  }) async {
    final res = await _handleEdge(
      'invitacion_rrpp',
      body: {'accion': 'generar', 'id_evento': idEvento},
    );
    return res.data;
  }

  Future<Map<String, dynamic>> administrarSoporteLocal({
    required String accion,
    String? codigoAntiEstafa,
    String? viaContacto, // 'email' | 'whatsapp' | null
  }) async {
    final body = <String, dynamic>{
      'accion': accion,
      if (codigoAntiEstafa != null && codigoAntiEstafa.trim().isNotEmpty)
        'codigo_antiestafa': codigoAntiEstafa.trim(),
      if (viaContacto != null && viaContacto.trim().isNotEmpty)
        'via_contacto': viaContacto.trim().toLowerCase(),
    };
    final res = await _handleEdge('administrador_soporte_local', body: body);
    return res.data;
  }

  Future<Map<String, dynamic>> crearPagoPendiente({
    required String planSolicitado,
    required double montoArs,
    required double cotizacionBlue,
    required String comprobanteNombre,
    required String comprobanteMime,
    required String comprobanteBase64,
    required String clientRequestId,
  }) async {
    final res = await _handleEdge(
      'crear_pago_pendiente',
      body: {
        'plan_solicitado': planSolicitado,
        'monto_ars': montoArs,
        'cotizacion_blue': cotizacionBlue,
        'comprobante_nombre': comprobanteNombre,
        'comprobante_mime': comprobanteMime,
        'comprobante_base64': comprobanteBase64,
        'client_request_id': clientRequestId,
      },
    );
    return res.data;
  }

  Future<Map<String, dynamic>> aprobarPagoLocal({
    required String pagoId,
    String accion = 'aprobar',
    String? notas,
  }) async {
    final res = await _handleEdge(
      'aprobar_pago_local',
      body: {
        'pago_id': pagoId,
        'accion': accion,
        if (notas != null && notas.trim().isNotEmpty) 'notas': notas.trim(),
      },
    );
    return res.data;
  }

  Future<Map<String, dynamic>> mejorarJerarquia({
    required String idEvento,
    required String jerarquiaDestino,
  }) async {
    final res = await _handleEdge(
      'mejorar_jerarquia',
      body: {'id_evento': idEvento, 'jerarquia_destino': jerarquiaDestino},
    );
    return res.data;
  }

  /// Valida o rechaza un token de promoción.
  /// [accion]: 'validar' (default) | 'rechazar'
  Future<Map<String, dynamic>> canjearPromocion({
    required String tokenCodigo,
    required String idLocal,
    required String idEvento,
    String accion = 'validar',
  }) async {
    final res = await _handleEdge(
      'canjear_promocion',
      body: {
        'token_codigo': tokenCodigo.trim().toUpperCase(),
        'id_local': idLocal,
        'id_evento': idEvento,
        'accion': accion,
      },
    );
    return res.data;
  }

  Future<Map<String, dynamic>> canjearCodigoPionero({
    required String codigo,
  }) async {
    final res = await _handleEdge(
      'canjear_codigo_pionero',
      body: {'codigo': codigo.trim().toUpperCase()},
    );
    return res.data;
  }
}

class _EdgeHttpResult {
  final int status;
  final Map<String, dynamic> data;
  final String rawBody;

  const _EdgeHttpResult({
    required this.status,
    required this.data,
    required this.rawBody,
  });
}
