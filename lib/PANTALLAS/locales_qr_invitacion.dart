library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants.dart';
import '../core/servicio_edges_eventos.dart';

/// Prefijo del payload del QR de invitación de RRPP.
/// El scanner de la app de usuarios reconoce este prefijo para abrir el evento
/// en modo invitación. Mantener sincronizado con fernecito_frontend.
const String kPrefijoQrInvitacion = 'FERNECITO_INV:';

/// Abre un bottom sheet que genera (o recupera) el QR de invitación de RRPP
/// para [idEvento] y lo muestra. Reutilizable sin tope.
Future<void> mostrarQrInvitacionRrpp(
  BuildContext context, {
  required String idEvento,
  required String tituloEvento,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SheetQrInvitacion(
      idEvento: idEvento,
      tituloEvento: tituloEvento,
    ),
  );
}

class _SheetQrInvitacion extends StatefulWidget {
  const _SheetQrInvitacion({
    required this.idEvento,
    required this.tituloEvento,
  });

  final String idEvento;
  final String tituloEvento;

  @override
  State<_SheetQrInvitacion> createState() => _SheetQrInvitacionState();
}

class _SheetQrInvitacionState extends State<_SheetQrInvitacion> {
  bool _cargando = true;
  String? _error;
  String? _idInvitacion;
  bool _pasarCupo = false;

  @override
  void initState() {
    super.initState();
    _generar();
  }

  Future<void> _generar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final res = await ServicioEdgesEventos()
          .generarInvitacionRrpp(idEvento: widget.idEvento);
      final id = res['id_invitacion']?.toString();
      if (id == null || id.isEmpty) {
        throw Exception('Respuesta inválida del servidor');
      }
      if (!mounted) return;
      setState(() {
        _idInvitacion = id;
        _pasarCupo = res['pasar_cupo'] == true;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _mensajeError(e);
        _cargando = false;
      });
    }
  }

  String _mensajeError(Object e) {
    if (e is EdgeException) {
      if (e.code == 'forbidden') {
        return 'No tenés permiso para generar el QR de invitación de este evento.';
      }
      return e.mensaje.isNotEmpty ? e.mensaje : 'No se pudo generar el QR.';
    }
    return 'No se pudo generar el QR. Revisá tu conexión.';
  }

  String get _payload => '$kPrefijoQrInvitacion${_idInvitacion ?? ''}';

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: ColoresLocales.fondoClaro,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(
              color: ColoresLocales.separador,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 18),
          Icon(CupertinoIcons.qrcode, size: 30, color: ColoresLocales.acentoVioleta),
          const SizedBox(height: 8),
          Text(
            'QR de invitación',
            style: GoogleFonts.baloo2(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: ColoresLocales.textoOnFondoClaro,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            widget.tituloEvento,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.baloo2(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: ColoresLocales.textoSecundarioOnFondoClaro,
            ),
          ),
          const SizedBox(height: 18),
          _contenido(),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _contenido() {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: CupertinoActivityIndicator(radius: 16),
      );
    }
    if (_error != null) {
      return Column(
        children: [
          const SizedBox(height: 12),
          Icon(CupertinoIcons.exclamationmark_triangle,
              size: 34, color: Colors.red.shade400),
          const SizedBox(height: 10),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: GoogleFonts.baloo2(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: ColoresLocales.textoOnFondoClaro,
            ),
          ),
          const SizedBox(height: 16),
          CupertinoButton(
            color: ColoresLocales.botonVioletaFondo,
            borderRadius: BorderRadius.circular(14),
            onPressed: _generar,
            child: Text(
              'Reintentar',
              style: GoogleFonts.baloo2(
                fontWeight: FontWeight.w800,
                color: ColoresLocales.botonVioletaTexto,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: ColoresLocales.decoracionCard(radius: 22, sinBorde: true),
          child: QrImageView(
            data: _payload,
            version: QrVersions.auto,
            size: 220,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Color(0xFF1A1A1A),
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Color(0xFF1A1A1A),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _pasarCupo
                ? const Color(0xFF16A34A).withValues(alpha: 0.12)
                : ColoresLocales.cardLavanda,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _pasarCupo
                    ? IconosLocales.exito
                    : CupertinoIcons.person_2_fill,
                size: 15,
                color: _pasarCupo
                    ? const Color(0xFF16A34A)
                    : ColoresLocales.acentoVioleta,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _pasarCupo
                      ? 'Puede pasar el cupo del evento'
                      : 'Respeta el cupo del evento',
                  style: GoogleFonts.baloo2(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ColoresLocales.textoOnFondoClaro,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Quien lo escanee desde la app de Fernecito entra directo a la lista, '
          'aceptado al instante. Reutilizable sin límite.',
          textAlign: TextAlign.center,
          style: GoogleFonts.baloo2(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: ColoresLocales.textoSecundarioOnFondoClaro,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              SharePlus.instance.share(
                ShareParams(
                  text:
                      '¡Sumate a "${widget.tituloEvento}"!\n\n'
                      'Abrí la app Fernecito → botón QR abajo a la derecha → escaneá:\n'
                      '$_payload',
                ),
              );
            },
            icon: const Icon(CupertinoIcons.share, size: 18),
            label: Text(
              'Compartir',
              style: GoogleFonts.baloo2(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: ColoresLocales.botonVioletaFondo,
              foregroundColor: ColoresLocales.botonVioletaTexto,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
