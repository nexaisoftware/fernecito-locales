library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants.dart';
import '../core/instalar_pwa_web.dart';

/// Snackbar persistente para instalar la PWA en Android/Chrome.
class ControlInstalarPwa extends StatefulWidget {
  const ControlInstalarPwa({super.key, required this.child});

  final Widget child;

  @override
  State<ControlInstalarPwa> createState() => _ControlInstalarPwaState();
}

class _ControlInstalarPwaState extends State<ControlInstalarPwa> {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _controller;
  bool _mostrandoExplicacion = false;
  bool _oculto = false;

  @override
  void initState() {
    super.initState();
    final svc = InstalarPwaWeb.instancia;
    if (!svc.soportado) return;

    svc.configurar();
    if (svc.yaInstalada) {
      _oculto = true;
      return;
    }

    svc.alDisponible(_intentarMostrarOferta);
    svc.alInstalada(_cerrarPorInstalada);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 2), _intentarMostrarOferta);
    });
  }

  @override
  void dispose() {
    _controller?.close();
    super.dispose();
  }

  void _cerrarPorInstalada() {
    if (!mounted) return;
    _controller?.close();
    _controller = null;
    setState(() {
      _oculto = true;
      _mostrandoExplicacion = false;
    });
  }

  void _intentarMostrarOferta() {
    if (!mounted || _oculto || _mostrandoExplicacion) return;
    final svc = InstalarPwaWeb.instancia;
    if (svc.yaInstalada || !svc.instalacionDisponible) return;
    if (_controller != null) return;

    _mostrarOferta();
  }

  double _margenInferior(BuildContext context) {
    return MediaQuery.paddingOf(context).bottom + 80;
  }

  SnackBar _snackBase({
    required Widget content,
    required BuildContext context,
  }) {
    return SnackBar(
      content: content,
      backgroundColor: const Color(0xFF1A1A2E),
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(16, 0, 16, _margenInferior(context)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      duration: const Duration(days: 1),
      showCloseIcon: true,
      closeIconColor: Colors.white70,
      onVisible: () {},
    );
  }

  void _mostrarOferta() {
    if (!mounted || _oculto) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.clearSnackBars();
    _controller = messenger.showSnackBar(
      _snackBase(
        context: context,
        content: InkWell(
          onTap: _mostrarExplicacion,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: ColoresLocales.acentoVioleta,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.install_mobile,
                    color: ColoresLocales.textoEnBoton,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Instalar app',
                    style: GoogleFonts.baloo2(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _mostrarExplicacion() {
    if (!mounted || _oculto) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    setState(() => _mostrandoExplicacion = true);
    _controller?.close();

    _controller = messenger.showSnackBar(
      _snackBase(
        context: context,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Es posible que Chrome diga que instalar desde aquí puede ser '
              'peligroso. Tranquilo: Fernecito Locales es segura.',
              style: GoogleFonts.baloo2(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _instalar,
                style: FilledButton.styleFrom(
                  backgroundColor: ColoresLocales.acentoVioleta,
                  foregroundColor: ColoresLocales.textoEnBoton,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  'Instalar',
                  style: GoogleFonts.baloo2(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _instalar() async {
    final aceptada = await InstalarPwaWeb.instancia.solicitarInstalacion();
    if (!mounted) return;

    if (InstalarPwaWeb.instancia.yaInstalada || aceptada) {
      _cerrarPorInstalada();
      return;
    }

    // Si cerró el modal de Chrome, mantener explicación + botón Instalar.
    if (!_mostrandoExplicacion) {
      _mostrarExplicacion();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
