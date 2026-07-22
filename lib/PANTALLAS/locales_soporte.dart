library;

import 'dart:math';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants.dart';
import '../core/lanzador_externo.dart';
import '../widgets/tema_locales_scope.dart';
import '../core/servicio_edges_eventos.dart';

class LocalesSoporte extends StatefulWidget {
  const LocalesSoporte({super.key});

  @override
  State<LocalesSoporte> createState() => _LocalesSoporteState();
}

class _LocalesSoporteState extends State<LocalesSoporte> {
  bool _cargando = true;
  bool _procesando = false;
  bool _codigoVisible = false;
  String _codigoActual = 'ABC-000';
  String _estadoOperacion = 'terminada';
  String _localUsername = 'local';

  bool get _operacionAbierta => _estadoOperacion == 'abierta';

  @override
  void initState() {
    super.initState();
    _cargarEstadoSoporte();
  }

  String _nuevoCodigo() {
    const letras = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    final rnd = Random.secure();
    final l1 = letras[rnd.nextInt(letras.length)];
    final l2 = letras[rnd.nextInt(letras.length)];
    final l3 = letras[rnd.nextInt(letras.length)];
    final n = rnd.nextInt(1000).toString().padLeft(3, '0');
    return '$l1$l2$l3-$n';
  }

  Future<void> _cargarEstadoSoporte() async {
    try {
      final data = await ServicioEdgesEventos().administrarSoporteLocal(
        accion: 'get_estado',
      );
      if (!mounted) return;
      final soporteRaw = data['soporte'];
      final soporte = soporteRaw is Map
          ? Map<String, dynamic>.from(soporteRaw)
          : null;
      final estado = (soporte?['estado_operacion'] as String?)
          ?.trim()
          .toLowerCase();
      final codigo = (soporte?['codigo_antiestafa'] as String?)?.trim();
      final username = (data['local_username'] as String?)?.trim();

      setState(() {
        _estadoOperacion = (estado == 'abierta' || estado == 'terminada')
            ? estado!
            : 'terminada';
        _localUsername = (username != null && username.isNotEmpty)
            ? username
            : 'local';
        _codigoActual = (codigo != null && codigo.isNotEmpty)
            ? codigo
            : _nuevoCodigo();
        _codigoVisible = _operacionAbierta;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      _mostrarDialogo('Error', 'No se pudo cargar el estado de soporte: $e');
    }
  }

  Future<void> _abrirWhatsAppConMensaje() async {
    final usernameConArroba = _localUsername.startsWith('@')
        ? _localUsername
        : '@$_localUsername';
    final msg =
        'Hola! 😊 Soy $usernameConArroba de Fernecito.\n\n'
        'Necesito ayuda con mi cuenta de local.\n\n'
        'Para mi tranquilidad, ¿podés decirme primero mi código anti-estafas?\n\n'
        '¡Muchas gracias! 🥃';
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}');
    final ok = await lanzarExternoConFallback(uri);
    if (!ok && mounted) {
      _mostrarDialogo(
        'No se pudo abrir WhatsApp',
        'Intentá de nuevo en unos segundos.',
      );
    }
  }

  Future<void> _abrirOperacionSoporte({required bool abrirChat}) async {
    if (_procesando) return;
    final nuevoCodigo = _nuevoCodigo();
    setState(() => _procesando = true);
    try {
      final data = await ServicioEdgesEventos().administrarSoporteLocal(
        accion: 'abrir',
        codigoAntiEstafa: nuevoCodigo,
        viaContacto: abrirChat ? 'whatsapp' : 'email',
      );
      final soporteRaw = data['soporte'];
      final soporte = soporteRaw is Map
          ? Map<String, dynamic>.from(soporteRaw)
          : null;
      if (mounted) {
        setState(() {
          _estadoOperacion =
              (soporte?['estado_operacion'] as String?) ?? 'abierta';
          _codigoActual =
              (soporte?['codigo_antiestafa'] as String?) ?? nuevoCodigo;
          _codigoVisible = true;
        });
      }
      if (abrirChat) {
        await _abrirWhatsAppConMensaje();
      }
    } catch (e) {
      if (mounted) {
        _mostrarDialogo('No se pudo generar código', '$e');
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _reiniciarOperacionSoporteYAbrirChat() async {
    if (_procesando) return;
    final nuevoCodigo = _nuevoCodigo();
    setState(() => _procesando = true);
    try {
      final data = await ServicioEdgesEventos().administrarSoporteLocal(
        accion: 'reiniciar',
        codigoAntiEstafa: nuevoCodigo,
        viaContacto: 'whatsapp', // reiniciar siempre arranca chat WSP
      );
      final soporteRaw = data['soporte'];
      final soporte = soporteRaw is Map
          ? Map<String, dynamic>.from(soporteRaw)
          : null;
      if (mounted) {
        setState(() {
          _estadoOperacion =
              (soporte?['estado_operacion'] as String?) ?? 'abierta';
          _codigoActual =
              (soporte?['codigo_antiestafa'] as String?) ?? nuevoCodigo;
          _codigoVisible = true;
        });
      }
      await _abrirWhatsAppConMensaje();
    } catch (e) {
      if (mounted) {
        _mostrarDialogo('No se pudo iniciar nueva conversación', '$e');
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _onTapWhatsApp() async {
    if (_operacionAbierta) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Operación abierta',
            style: GoogleFonts.baloo2(fontWeight: FontWeight.w900),
          ),
          content: Text(
            'Tenés una operación abierta.\n\nPodés continuar la conversación actual o iniciar una nueva con otro código.',
            style: GoogleFonts.baloo2(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancelar', style: GoogleFonts.baloo2()),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _abrirWhatsAppConMensaje();
              },
              child: Text(
                'Ir al chat',
                style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
              ),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _reiniciarOperacionSoporteYAbrirChat();
              },
              style: FilledButton.styleFrom(
                backgroundColor: ColoresLocales.acentoVioleta,
              ),
              child: Text(
                'Iniciar nueva conversación',
                style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Antes de contactar soporte',
          style: GoogleFonts.baloo2(fontWeight: FontWeight.w900),
        ),
        content: Text(
          'Primero generá tu código anti-estafas.\n\n'
          'Esto protege tu cuenta durante la conversación con soporte oficial.',
          style: GoogleFonts.baloo2(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancelar', style: GoogleFonts.baloo2()),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _abrirOperacionSoporte(abrirChat: true);
            },
            style: FilledButton.styleFrom(
              backgroundColor: ColoresLocales.acentoVioleta,
            ),
            child: Text(
              'Generar y contactar',
              style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogo(String titulo, String msg) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          titulo,
          style: GoogleFonts.baloo2(fontWeight: FontWeight.w900),
        ),
        content: Text(msg, style: GoogleFonts.baloo2()),
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
    if (_cargando) {
      return Scaffold(
        backgroundColor: ColoresLocales.superficie,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: ColoresLocales.superficie,
          centerTitle: true,
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.pop(context),
            child: Icon(
              CupertinoIcons.chevron_back,
              color: ColoresLocales.acentoVioleta,
            ),
          ),
          title: Text(
            'Ayuda y soporte',
            style: GoogleFonts.baloo2(
              color: ColoresLocales.acentoVioleta,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        body: Center(
          child: CircularProgressIndicator(color: ColoresLocales.acentoVioleta),
        ),
      );
    }

    return Scaffold(
      backgroundColor: ColoresLocales.superficie,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: ColoresLocales.superficie,
        centerTitle: true,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: Icon(
            CupertinoIcons.chevron_back,
            color: ColoresLocales.acentoVioleta,
          ),
        ),
        title: Text(
          'Ayuda y soporte',
          style: GoogleFonts.baloo2(
            color: ColoresLocales.acentoVioleta,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Contacto',
                          style: GoogleFonts.baloo2(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: ColoresLocales.textoOnFondoClaro,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _itemAccion(
                          icon: CupertinoIcons.chat_bubble_2_fill,
                          titulo: 'WhatsApp (recomendado)',
                          subtitulo: 'Respuesta más rápida.',
                          onTap: _onTapWhatsApp,
                        ),
                        SizedBox(height: 10),
                        _item(
                          icon: CupertinoIcons.envelope_fill,
                          titulo: 'Email',
                          subtitulo: 'Próximamente',
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12),
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.lock_shield_fill,
                              size: 22,
                              color: ColoresLocales.acentoVioleta,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Código ANTI-ESTAFAS',
                                style: GoogleFonts.baloo2(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: ColoresLocales.acentoVioleta,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.red.withOpacity(0.18),
                            ),
                          ),
                          child: Text(
                            'IMPORTANTE: NO COMPARTAS ESTE CÓDIGO',
                            style: GoogleFonts.baloo2(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              height: 1.25,
                              color: Colors.red.shade800,
                            ),
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Solo el soporte oficial de Fernecito conoce este código.\n\n'
                          'Ellos te lo dirán primero. Vos solo verificás si coincide.\n\n'
                          'Si no te lo brindan o no coincide, terminá la comunicación.',
                          style: GoogleFonts.baloo2(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.red.shade700,
                            height: 1.28,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildCajaCodigo(),
                        SizedBox(height: 8),
                        Text(
                          'Tip: guardalo y usalo solo para verificar que estás hablando con soporte oficial.',
                          style: GoogleFonts.baloo2(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: ColoresLocales.textoSecundarioOnFondoClaro,
                          ),
                        ),
                      ],
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

  Widget _buildCajaCodigo() {
    return Container(
      height: 92,
      decoration: BoxDecoration(
        color: ColoresLocales.cardLavanda,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ColoresLocales.acentoVioleta.withOpacity(0.18),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            _codigoActual,
            style: GoogleFonts.baloo2(
              fontSize: 44,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.5,
              color: ColoresLocales.acentoVioleta,
            ),
          ),
          if (!_codigoVisible)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(17),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                  child: Container(
                    color: Colors.white.withOpacity(0.24),
                    alignment: Alignment.center,
                    child: FilledButton.icon(
                      onPressed: _procesando
                          ? null
                          : () async {
                              await _abrirOperacionSoporte(abrirChat: false);
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: ColoresLocales.acentoVioleta,
                        foregroundColor: ColoresLocales.textoEnBoton,
                        padding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      icon: _procesando
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: ColoresLocales.textoEnBoton,
                              ),
                            )
                          : Icon(CupertinoIcons.eye_fill, size: 18),
                      label: Text(
                        _procesando ? 'Generando...' : 'Eh leído, ver código',
                        style: GoogleFonts.baloo2(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ColoresLocales.superficie,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ColoresLocales.acentoVioleta.withOpacity(0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: ColoresLocales.acentoVioleta.withOpacity(0.06),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _item({
    required IconData icon,
    required String titulo,
    required String subtitulo,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: ColoresLocales.acentoVioleta.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: ColoresLocales.acentoVioleta, size: 18),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: GoogleFonts.baloo2(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: ColoresLocales.textoOnFondoClaro,
                ),
              ),
              SizedBox(height: 1),
              Text(
                subtitulo,
                style: GoogleFonts.baloo2(
                  fontSize: 12,
                  color: ColoresLocales.textoSecundarioOnFondoClaro,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _itemAccion({
    required IconData icon,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: ColoresLocales.acentoVioleta.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: ColoresLocales.acentoVioleta,
                  size: 18,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: GoogleFonts.baloo2(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: ColoresLocales.textoOnFondoClaro,
                      ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      subtitulo,
                      style: GoogleFonts.baloo2(
                        fontSize: 12,
                        color: ColoresLocales.textoSecundarioOnFondoClaro,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Icon(
                CupertinoIcons.chevron_right,
                size: 18,
                color: ColoresLocales.textoSecundarioOnFondoClaro,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
