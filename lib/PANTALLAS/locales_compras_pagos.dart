library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../core/comprimir_imagen_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../widgets/tema_locales_scope.dart';
import '../core/navegacion_locales.dart';
import '../core/programa_pioneros.dart';
import '../core/servicio_edges_eventos.dart';
import '../core/suscripcion_locales.dart';
import '../widgets/programa_pioneros_ui.dart';

/// Genera un UUID v4 criptográficamente seguro. Usado como idempotency key.
String _uuidV4() {
  final r = Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
  String h(int b) => b.toRadixString(16).padLeft(2, '0');
  final s = bytes.map(h).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-'
      '${s.substring(16, 20)}-${s.substring(20)}';
}

const Map<String, int> _planRank = {
  'gratis': 0,
  'standard': 1,
  'plus': 2,
  'premium': 3,
  'pionero': 3,
};

class LocalesComprasPagos extends StatefulWidget {
  const LocalesComprasPagos({super.key});

  @override
  State<LocalesComprasPagos> createState() => _LocalesComprasPagosState();
}

class _LocalesComprasPagosState extends State<LocalesComprasPagos> {
  bool _cargandoCotizacion = true;
  bool _enviandoComprobante = false;
  bool _mostrarAviso = true;
  double? _cotizacionBlue;
  String? _errorCotizacion;

  // ── Estado de solicitudes activas del local (anti-duplicado en UI) ──────
  bool _cargandoEstado = true;
  Map<String, dynamic>? _solicitudPendiente; // estado='pendiente'
  Map<String, dynamic>? _solicitudDiferida;  // aprobado_pendiente + renov/downgrade
  String? _planActualLocal;                  // plan_suscripcion actual
  DateTime? _vencimientoLocal;               // fecha_vencimiento_suscripcion
  bool _esPionero = false;
  bool _pioneroBeneficiosActivo = false;
  int? _pioneroMesBeneficio;
  String _tipoPlanEfectivo = 'Standard';

  // ── Idempotency key — uno por intención. Se regenera DESPUÉS de un envío
  // exitoso o cuando el usuario abre un sheet de plan distinto. Mientras el
  // envío está en vuelo, el mismo UUID hace dedup en la edge.
  String? _requestIdEnVuelo;

  static const String _alias = 'pagos.fernecito';
  static const String _cbu = '000-0000000000-00'; // TODO: reemplazar con CBU real
  static const String _titular = 'Nexai Software SRL';
  static const String _cuit = '20-39659932-6';

  @override
  void initState() {
    super.initState();
    _cargarCotizacionBlue();
    _cargarEstadoSolicitudes();
  }

  /// Lee estado del local + solicitudes activas. Bloquea opciones inválidas.
  Future<void> _cargarEstadoSolicitudes() async {
    setState(() => _cargandoEstado = true);
    try {
      final sb = Supabase.instance.client;
      final uid = sb.auth.currentUser?.id;
      if (uid == null) {
        setState(() => _cargandoEstado = false);
        return;
      }

      // Perfil del local (plan + vencimiento)
      final perfil = await sb
          .from('perfiles_locales')
          .select(
            'plan_suscripcion, fecha_vencimiento_suscripcion, es_pionero, '
            'pionero_beneficios_fin, pionero_mes_beneficio, local_verificado',
          )
          .eq('id', uid)
          .maybeSingle();
      _planActualLocal = (perfil?['plan_suscripcion'] as String?)?.toLowerCase();
      final venc = perfil?['fecha_vencimiento_suscripcion'];
      _vencimientoLocal = venc != null ? DateTime.tryParse(venc.toString()) : null;
      _esPionero = perfil?['es_pionero'] == true;
      final pioneroFinRaw = perfil?['pionero_beneficios_fin'];
      final pioneroFin = pioneroFinRaw != null
          ? DateTime.tryParse(pioneroFinRaw.toString())?.toLocal()
          : null;
      _pioneroMesBeneficio = (perfil?['pionero_mes_beneficio'] as num?)?.toInt();
      _pioneroBeneficiosActivo = _esPionero &&
          pioneroFin != null &&
          pioneroFin.isAfter(DateTime.now());
      _tipoPlanEfectivo = SuscripcionLocales.tipoPlanEfectivo(
        rawDb: _planActualLocal,
        localVerificado: perfil?['local_verificado'] == true,
        esPionero: _esPionero,
        pioneroBeneficiosActivo: _pioneroBeneficiosActivo,
        pioneroMesBeneficio: _pioneroMesBeneficio,
        fechaVencimiento: _vencimientoLocal,
      );

      // Solicitudes activas del local
      final solicitudes = await sb
          .from('pagos_pendientes')
          .select('id, estado, tipo_solicitud, plan_solicitado, creado_en, aplica_desde')
          .eq('perfil_id', uid)
          .inFilter('estado', ['pendiente', 'aprobado_pendiente'])
          .order('creado_en', ascending: false);

      _solicitudPendiente = null;
      _solicitudDiferida = null;
      for (final row in (solicitudes as List).cast<Map<String, dynamic>>()) {
        final est = row['estado'];
        final tipo = row['tipo_solicitud'];
        if (est == 'pendiente' && _solicitudPendiente == null) {
          _solicitudPendiente = row;
        }
        if (est == 'aprobado_pendiente' &&
            (tipo == 'renovacion' || tipo == 'downgrade') &&
            _solicitudDiferida == null) {
          _solicitudDiferida = row;
        }
      }
    } catch (e) {
      // Fail-open de lectura: la edge igual valida; el usuario podrá intentar.
      debugPrint('cargar estado solicitudes: $e');
    } finally {
      if (mounted) setState(() => _cargandoEstado = false);
    }
  }

  bool _planActivo() {
    final v = _vencimientoLocal;
    if (v == null) return false;
    final p = _planActualLocal ?? 'gratis';
    return v.isAfter(DateTime.now()) && p != 'gratis' && p.isNotEmpty;
  }

  /// Devuelve null si el plan se puede pagar, o un motivo legible si está bloqueado.
  String? _motivoBloqueo(String planRaw) {
    if (_cargandoEstado) return 'Cargando estado...';

    if (_esPionero && _pioneroBeneficiosActivo) {
      final reglas = ProgramaPioneros.reglas(
        esPionero: _esPionero,
        beneficiosActivos: _pioneroBeneficiosActivo,
        mesBeneficio: _pioneroMesBeneficio,
        planActual: _tipoPlanEfectivo,
        premiumPagoActivo: ProgramaPioneros.premiumPagoActivo(
          planRaw: _planActualLocal,
          fechaVencimiento: _vencimientoLocal,
        ),
      );
      final motivoPionero = reglas.motivoBloqueoPlan(planRaw);
      if (motivoPionero != null) return motivoPionero;
    }

    if (_solicitudPendiente != null) {
      return 'Ya tenés un pago pendiente de aprobación.';
    }
    if (_solicitudDiferida != null) {
      // Si hay una renov/downgrade aprobada esperando, solo permite UPGRADE
      // sobre el plan SOLICITADO en esa diferida (no el plan actual).
      final planDiferido =
          (_solicitudDiferida!['plan_solicitado'] as String?)?.toLowerCase() ?? '';
      final rankDif = _planRank[planDiferido] ?? 0;
      final rankNuevo = _planRank[planRaw] ?? 0;
      if (rankNuevo <= rankDif) {
        return 'Ya tenés una solicitud agendada para "$planDiferido". Solo podés pagar un plan mayor.';
      }
    }
    return null;
  }

  Map<String, dynamic> _planInfoFromArg(String arg) {
    final plan = arg.trim().toLowerCase();
    if (plan == 'premium') {
      return {'label': 'Premium', 'raw': 'premium', 'usd': 65.0};
    }
    if (plan == 'plus') return {'label': 'Plus', 'raw': 'plus', 'usd': 35.0};
    if (plan == 'pionero') {
      return {'label': 'Pionero', 'raw': 'pionero', 'usd': 0.0};
    }
    return {'label': 'Standard', 'raw': 'standard', 'usd': 15.0};
  }

  Color _chipColor(String planLabel) {
    switch (planLabel.toLowerCase()) {
      case 'premium':
        return Color(0xFFF59E0B);
      case 'plus':
        return const Color(0xFF0891B2);
      case 'pionero':
        return Color(0xFF16A34A);
      default:
        return ColoresLocales.acentoVioleta;
    }
  }

  Future<void> _cargarCotizacionBlue() async {
    setState(() {
      _cargandoCotizacion = true;
      _errorCotizacion = null;
    });
    try {
      final res = await http.get(Uri.parse('https://dolarapi.com/v1/dolares/blue'));
      if (res.statusCode >= 400) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) throw Exception('Respuesta inválida');
      final value = decoded['venta'];
      final cot = value is num ? value.toDouble() : double.tryParse(value.toString());
      if (cot == null || cot <= 0) throw Exception('Cotización inválida');
      if (!mounted) return;
      setState(() => _cotizacionBlue = cot);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorCotizacion = 'No se pudo cargar el monto en ARS');
    } finally {
      if (mounted) setState(() => _cargandoCotizacion = false);
    }
  }

  String _formatMoney(double value) {
    final fixed = value.toStringAsFixed(2);
    return fixed.replaceAll('.', ',');
  }

  String _formatMoneyArs(double value) {
    // Formato con separadores de miles: 18.750,00
    final fixed = value.toStringAsFixed(0);
    final buffer = StringBuffer();
    final chars = fixed.split('').reversed.toList();
    for (int i = 0; i < chars.length; i++) {
      if (i > 0 && i % 3 == 0) buffer.write('.');
      buffer.write(chars[i]);
    }
    return buffer.toString().split('').reversed.join();
  }

  String _mimeFromExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _copiar(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copiado', style: GoogleFonts.baloo2(color: ColoresLocales.textoPrincipal)),
        backgroundColor: ColoresLocales.acentoVioleta,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _seleccionarYEnviarComprobante({
    required String planRaw,
    required double montoUsd,
    required double montoArs,
    required double cotizacionBlue,
  }) async {
    PlatformFile? comprobante;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> elegirArchivo() async {
              final picked = await FilePicker.pickFiles(
                allowMultiple: false,
                withData: true,
                type: FileType.custom,
                allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
              );
              if (picked == null || picked.files.isEmpty) return;
              setModalState(() {
                comprobante = picked.files.first;
              });
            }

            Future<void> enviar() async {
              final file = comprobante;
              if (file == null || file.bytes == null || file.bytes!.isEmpty) return;
              if (_enviandoComprobante) return; // lock estricto: doble-tap no entra

              // Re-chequeo de bloqueo en el momento del envío (estado puede
              // haber cambiado mientras el sheet estaba abierto).
              final motivo = _motivoBloqueo(planRaw);
              if (motivo != null) {
                _mostrarDialogo(titulo: 'No se puede enviar', mensaje: motivo);
                return;
              }

              // Idempotency key: si ya hay uno "en vuelo" (reintento por error),
              // reusamos. Si no, generamos nuevo.
              _requestIdEnVuelo ??= _uuidV4();
              final reqId = _requestIdEnVuelo!;

              setState(() => _enviandoComprobante = true);
              try {
                final ext = (file.extension ?? '').toLowerCase();
                final preparado = await prepararComprobantePago(
                  bytes: file.bytes!,
                  nombreOriginal: file.name,
                  extension: ext,
                );
                final bytes = preparado.bytes;
                final mime = preparado.mime;
                final nombre = preparado.nombre;

                final base64Comprobante = base64Encode(bytes);

                await ServicioEdgesEventos().crearPagoPendiente(
                  planSolicitado: planRaw,
                  montoArs: montoArs,
                  cotizacionBlue: cotizacionBlue,
                  comprobanteNombre: nombre,
                  comprobanteMime: mime,
                  comprobanteBase64: base64Comprobante,
                  clientRequestId: reqId,
                );

                // Envío exitoso: invalidamos el request id para la próxima intención.
                _requestIdEnVuelo = null;

                if (!mounted) return;
                Navigator.of(ctx).pop();
                // Refrescamos estado para que la próxima vez se vea bloqueado.
                unawaited(_cargarEstadoSolicitudes());
                await Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => _ExitoComprobanteScreen(),
                  ),
                );
              } catch (e) {
                // Mantenemos _requestIdEnVuelo para que un retry sea idempotente.
                if (mounted) {
                  _mostrarDialogo(
                    titulo: 'No se pudo enviar',
                    mensaje: '$e',
                  );
                }
              } finally {
                if (mounted) setState(() => _enviandoComprobante = false);
              }
            }

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
                decoration: BoxDecoration(
                  color: ColoresLocales.superficie,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 18),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    // Alerta amarilla
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: ColoresLocales.mostazaDestacado.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFF59E0B).withOpacity(0.45),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFFF59E0B),
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '¡Es importante! Enviá el comprobante para que podamos verificar tu pago y activar tu plan.',
                              style: GoogleFonts.baloo2(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF92400E),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'Enviar comprobante',
                      style: GoogleFonts.baloo2(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: ColoresLocales.textoOnFondoClaro,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Subí la imagen o PDF de tu transferencia.',
                      style: GoogleFonts.baloo2(
                        fontSize: 13.5,
                        color: ColoresLocales.textoSecundarioOnFondoClaro,
                      ),
                    ),
                    SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: elegirArchivo,
                      icon: Icon(CupertinoIcons.doc_on_clipboard),
                      label: Text(
                        comprobante == null ? 'Seleccionar archivo' : comprobante!.name,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ColoresLocales.acentoVioleta,
                        side: BorderSide(color: ColoresLocales.acentoVioleta.withOpacity(0.45)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 12),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: ElevatedButton.icon(
                        onPressed: (comprobante?.bytes == null || _enviandoComprobante)
                            ? null
                            : enviar,
                        icon: _enviandoComprobante
                            ? SizedBox(
                                width: 19,
                                height: 19,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: ColoresLocales.chipInactivo,
                                ),
                              )
                            : Icon(IconosLocales.exito, size: 21),
                        label: Text(
                          _enviandoComprobante
                              ? 'Enviando...'
                              : 'Enviar comprobante',
                          style: GoogleFonts.baloo2(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: comprobante?.bytes != null
                              ? const Color(0xFF16A34A)
                              : Colors.grey.shade300,
                          disabledBackgroundColor: Colors.grey.shade300,
                          foregroundColor: ColoresLocales.textoEnBoton,
                          disabledForegroundColor: Colors.grey.shade500,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: comprobante?.bytes != null ? 3 : 0,
                          shadowColor: const Color(0xFF16A34A).withOpacity(0.4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmarEnvioComprobante({
    required String planRaw,
    required double montoUsd,
    required double montoArs,
    required double cotizacionBlue,
  }) async {
    await _seleccionarYEnviarComprobante(
      planRaw: planRaw,
      montoUsd: montoUsd,
      montoArs: montoArs,
      cotizacionBlue: cotizacionBlue,
    );
  }

  void _mostrarDialogo({required String titulo, required String mensaje}) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(titulo, style: GoogleFonts.baloo2(fontWeight: FontWeight.w900)),
        content: Text(mensaje, style: GoogleFonts.baloo2()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'OK',
              style: GoogleFonts.baloo2(
                fontWeight: FontWeight.w800,
                color: ColoresLocales.acentoVioleta,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final planArg = (ModalRoute.of(context)?.settings.arguments as String?) ?? 'Standard';
    final plan = _planInfoFromArg(planArg);
    final planLabel = plan['label'] as String;
    final planRaw = plan['raw'] as String;
    final montoUsd = plan['usd'] as double;
    final cot = _cotizacionBlue;
    final montoArs = cot == null ? null : montoUsd * cot;
    final chipColor = _chipColor(planLabel);

    return Scaffold(
      backgroundColor: ColoresLocales.superficie,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: ColoresLocales.superficie,
        centerTitle: true,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => NavegacionLocales.volver(context),
          child: Icon(CupertinoIcons.chevron_back, color: ColoresLocales.acentoVioleta),
        ),
        title: Text(
          'Compras y pagos',
          style: GoogleFonts.baloo2(
            color: ColoresLocales.acentoVioleta,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(18, 14, 18, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Título de sección con chip de plan ──────────────────
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        'Verificado con plan',
                        style: GoogleFonts.baloo2(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: ColoresLocales.textoOnFondoClaro,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: chipColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: chipColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          planLabel,
                          style: GoogleFonts.baloo2(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: chipColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Aviso amarillo descartable ───────────────────────────
                  if (_mostrarAviso) ...[
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                      decoration: BoxDecoration(
                        color: ColoresLocales.mostazaDestacado.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFFBC02D).withOpacity(0.5),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.info_outline_rounded,
                              color: Color(0xFFF59E0B),
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              'Por ahora aceptamos transferencias bancarias. Estamos trabajando para sumar más métodos de pago próximamente.',
                              style: GoogleFonts.baloo2(
                                fontSize: 12.5,
                                color: const Color(0xFF78350F),
                                height: 1.35,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _mostrarAviso = false),
                            child: const Padding(
                              padding: EdgeInsets.only(left: 6, top: 1),
                              child: Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: Color(0xFFA16207),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],

                  if (_esPionero && _pioneroBeneficiosActivo)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: BannerInfoPioneroSuscripcion(
                        reglas: ProgramaPioneros.reglas(
                          esPionero: _esPionero,
                          beneficiosActivos: _pioneroBeneficiosActivo,
                          mesBeneficio: _pioneroMesBeneficio,
                          planActual: _tipoPlanEfectivo,
                          premiumPagoActivo: ProgramaPioneros.premiumPagoActivo(
                            planRaw: _planActualLocal,
                            fechaVencimiento: _vencimientoLocal,
                          ),
                        ),
                      ),
                    ),

                  // ── Card de transferencia ─────────────────────────────────
                  _transferCard(
                    montoUsd: montoUsd,
                    montoArs: montoArs,
                  ),
                  SizedBox(height: 22),

                  // ── Banner de bloqueo si hay solicitud activa ────────────
                  Builder(builder: (_) {
                    final motivo = _motivoBloqueo(planRaw);
                    if (motivo == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.5)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.lock_outline_rounded,
                                color: Color(0xFFB91C1C), size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                motivo,
                                style: GoogleFonts.baloo2(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF7F1D1D),
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                  // ── Botón CTA ─────────────────────────────────────────────
                  ElevatedButton.icon(
                    onPressed: (_cotizacionBlue == null ||
                            _enviandoComprobante ||
                            _cargandoEstado ||
                            _motivoBloqueo(planRaw) != null)
                        ? null
                        : () => _confirmarEnvioComprobante(
                              planRaw: planRaw,
                              montoUsd: montoUsd,
                              montoArs: montoArs!,
                              cotizacionBlue: _cotizacionBlue!,
                            ),
                    icon: Icon(Icons.check_circle_outline_rounded, size: 22),
                    label: Text(
                      '¡Ya hice la transferencia!',
                      style: GoogleFonts.baloo2(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ColoresLocales.acentoVioleta,
                      foregroundColor: ColoresLocales.textoEnBoton,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                      padding: EdgeInsets.symmetric(vertical: 15),
                      elevation: 3,
                      shadowColor: ColoresLocales.acentoVioleta.withOpacity(0.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _transferCard({required double montoUsd, required double? montoArs}) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 16, 22),
      decoration: BoxDecoration(
        color: ColoresLocales.superficie,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ColoresLocales.acentoVioleta.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: ColoresLocales.acentoVioleta.withOpacity(0.07),
            blurRadius: 18,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Título de card ────────────────────────────────────────
          Text(
            'Transferir:',
            style: GoogleFonts.baloo2(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: ColoresLocales.acentoVioleta,
              letterSpacing: 0.2,
            ),
          ),
          SizedBox(height: 4),

          // ── Monto USD ─────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  'USD \$ ${_formatMoney(montoUsd)}',
                  style: GoogleFonts.baloo2(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: ColoresLocales.acentoVioleta,
                    height: 1.1,
                  ),
                ),
              ),
              _iconoCopiar(
                tooltip: 'Copiar monto USD',
                onTap: () => _copiar(_formatMoney(montoUsd), 'Monto USD'),
              ),
            ],
          ),

          // ── Monto ARS ─────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.only(top: 2, bottom: 4),
            child: _bloqueArs(montoArs),
          ),

          Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, thickness: 1, color: ColoresLocales.separador),
          ),

          // ── Alias ─────────────────────────────────────────────────
          Text(
            'al alias:',
            style: GoogleFonts.baloo2(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: ColoresLocales.acentoVioleta,
            ),
          ),
          SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  _alias,
                  style: GoogleFonts.baloo2(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: ColoresLocales.textoOnFondoClaro,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              _iconoCopiar(
                tooltip: 'Copiar alias',
                onTap: () => _copiar(_alias, 'Alias'),
              ),
            ],
          ),
          SizedBox(height: 4),
          GestureDetector(
            onTap: () => _copiar(_cbu, 'CBU'),
            child: Text(
              'o CBU: $_cbu',
              style: GoogleFonts.baloo2(
                fontSize: 11.5,
                color: ColoresLocales.textoSecundarioOnFondoClaro,
                decoration: TextDecoration.underline,
                decorationColor: ColoresLocales.textoSecundarioOnFondoClaro.withOpacity(0.5),
              ),
            ),
          ),

          Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, thickness: 1, color: ColoresLocales.separador),
          ),

          // ── Titular ───────────────────────────────────────────────
          Text(
            'Aparece a nombre de:',
            style: GoogleFonts.baloo2(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: ColoresLocales.acentoVioleta,
            ),
          ),
          SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  _titular,
                  style: GoogleFonts.baloo2(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: ColoresLocales.textoOnFondoClaro,
                  ),
                ),
              ),
              _iconoCopiar(
                tooltip: 'Copiar titular',
                onTap: () => _copiar(_titular, 'Titular'),
              ),
            ],
          ),
          SizedBox(height: 5),
          Text(
            'CUIT: $_cuit',
            style: GoogleFonts.baloo2(
              fontSize: 12,
              color: ColoresLocales.textoSecundarioOnFondoClaro,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bloqueArs(double? montoArs) {
    if (_cargandoCotizacion) {
      return Row(
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: ColoresLocales.acentoVioleta,
            ),
          ),
          SizedBox(width: 7),
          Text(
            'Calculando en ARS...',
            style: GoogleFonts.baloo2(
              fontSize: 12.5,
              color: ColoresLocales.textoSecundarioOnFondoClaro,
            ),
          ),
        ],
      );
    }

    if (_errorCotizacion != null) {
      return Row(
        children: [
          Icon(Icons.refresh_rounded, size: 14, color: ColoresLocales.acentoVioleta),
          SizedBox(width: 6),
          GestureDetector(
            onTap: _cargarCotizacionBlue,
            child: Text(
              'No se pudo calcular en ARS · Reintentar',
              style: GoogleFonts.baloo2(
                fontSize: 12,
                color: ColoresLocales.acentoVioleta,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      );
    }

    if (montoArs == null) return SizedBox.shrink();

    return RichText(
      text: TextSpan(
        style: GoogleFonts.baloo2(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: ColoresLocales.textoSecundarioOnFondoClaro,
        ),
        children: [
          TextSpan(text: 'en pesos:  '),
          TextSpan(
            text: '≈ \$ ${_formatMoneyArs(montoArs)}',
            style: GoogleFonts.baloo2(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: ColoresLocales.textoOnFondoClaro,
            ),
          ),
          TextSpan(
            text: '  ARS',
            style: GoogleFonts.baloo2(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: ColoresLocales.textoSecundarioOnFondoClaro,
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconoCopiar({required String tooltip, required VoidCallback onTap}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: Icon(
            Icons.content_copy_rounded,
            size: 18,
            color: ColoresLocales.acentoVioleta.withOpacity(0.7),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pantalla de éxito fullscreen — reemplaza el diálogo de confirmación
// ─────────────────────────────────────────────────────────────────────────────
class _ExitoComprobanteScreen extends StatelessWidget {
  const _ExitoComprobanteScreen();

  static const _verde = Color(0xFF16A34A);
  static const _verdeOscuro = Color(0xFF14532D);
  static const _blanco = Colors.white;

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return Scaffold(
      backgroundColor: _verde,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),

              // ── Ícono grande centrado ─────────────────────────────
              const Center(
                child: Icon(
                  Icons.check_circle_rounded,
                  color: _blanco,
                  size: 100,
                ),
              ),
              const SizedBox(height: 28),

              // ── Título ────────────────────────────────────────────
              Text(
                '¡Comprobante enviado!',
                textAlign: TextAlign.center,
                style: GoogleFonts.baloo2(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: _blanco,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 14),

              // ── Descripción ───────────────────────────────────────
              Text(
                'Tu pago está en revisión. Si es aprobado, tu plan se actualizará automáticamente.',
                textAlign: TextAlign.center,
                style: GoogleFonts.baloo2(
                  fontSize: 15.5,
                  color: Colors.white.withOpacity(0.92),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Si hay algún problema, un agente se pondrá en contacto contigo.',
                textAlign: TextAlign.center,
                style: GoogleFonts.baloo2(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.75),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),

              // ── Cuadro recordatorio anti-estafa ───────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.shield_rounded, color: _blanco, size: 18),
                        const SizedBox(width: 7),
                        Text(
                          'Recordatorio de seguridad',
                          style: GoogleFonts.baloo2(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: _blanco,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ..._tips.map(
                      (tip) => Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 5),
                              child: CircleAvatar(
                                radius: 3,
                                backgroundColor: Colors.white70,
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                tip,
                                style: GoogleFonts.baloo2(
                                  fontSize: 12.5,
                                  color: Colors.white.withOpacity(0.88),
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // ── Botón: Ir a mi dashboard ──────────────────────────
              ElevatedButton(
                onPressed: () => NavegacionLocales.exitoComprobanteIrHome(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blanco,
                  foregroundColor: _verdeOscuro,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  elevation: 0,
                ),
                child: Text(
                  'Ir a mi dashboard',
                  style: GoogleFonts.baloo2(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Botón: Ir a mis suscripciones ─────────────────────
              OutlinedButton(
                onPressed: () => NavegacionLocales.exitoComprobanteVerSuscripcion(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _blanco,
                  side: const BorderSide(color: Colors.white60, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: Text(
                  'Ver mi suscripción',
                  style: GoogleFonts.baloo2(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const List<String> _tips = [
    'Solicitá siempre el código anti-estafas antes de realizar cualquier acción.',
    'Nunca compartas tu código: solo usalo para verificar que quien te contacta es de Fernecito.',
    'Si alguien no puede brindarte el código o el código es incorrecto, no continúes la conversación.',
  ];
}
