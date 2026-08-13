/// Switcher de cuentas multi-local (estilo Instagram/iOS).
///
/// Modal reutilizable: se abre con hold en el avatar del navbar o desde el
/// dropdown del dashboard. Lista las cuentas guardadas en el vault, permite
/// cambiar sin contraseña, agregar otra ("+ Agregar cuenta") y quitar (hold).
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../PANTALLAS/locales_login_interno.dart';
import '../core/constants.dart';
import '../core/recarga_cuenta_locales.dart';
import '../core/vault_sesiones_locales.dart';
import '../models/cuenta_guardada.dart';

/// Abre el switcher de cuentas. Devuelve cuando el modal se cierra.
Future<void> mostrarSwitcherCuentasLocales(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _SwitcherCuentasSheet(),
  );
}

class _SwitcherCuentasSheet extends StatefulWidget {
  const _SwitcherCuentasSheet();

  @override
  State<_SwitcherCuentasSheet> createState() => _SwitcherCuentasSheetState();
}

class _SwitcherCuentasSheetState extends State<_SwitcherCuentasSheet> {
  List<CuentaGuardada> _cuentas = const [];
  bool _cargando = true;
  bool _cambiando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final cuentas = await VaultSesionesLocales().listar();
    if (!mounted) return;
    setState(() {
      _cuentas = cuentas;
      _cargando = false;
    });
  }

  Future<void> _agregarCuenta() async {
    // Capturar el navigator raíz ANTES de cerrar el sheet: después del pop el
    // context del bottomsheet ya no es válido y el push fallaba / se colgaba.
    final nav = Navigator.of(context, rootNavigator: true);
    Navigator.of(context).pop();
    await Future<void>.delayed(Duration.zero);
    nav.push(
      MaterialPageRoute(builder: (_) => const LocalesLoginInterno()),
    );
  }

  Future<void> _cambiar(CuentaGuardada c) async {
    if (_cambiando) return;
    final activo = VaultSesionesLocales().uidActivo;
    if (c.uid == activo) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _cambiando = true);
    final res = await VaultSesionesLocales().cambiarA(c.uid);
    if (!mounted) return;

    switch (res) {
      case ResultadoCambioCuenta.ok:
        if (mounted) Navigator.of(context).pop();
        // No depender solo del AuthGate: forzar splash + remount del Home.
        await recargarAppTrasCambioCuenta();
        break;
      case ResultadoCambioCuenta.yaActiva:
      case ResultadoCambioCuenta.noEncontrada:
        Navigator.of(context).pop();
        break;
      case ResultadoCambioCuenta.requiereRelogin:
        final nav = Navigator.of(context, rootNavigator: true);
        Navigator.of(context).pop();
        await Future<void>.delayed(Duration.zero);
        nav.push(
          MaterialPageRoute(
            builder: (_) => LocalesLoginInterno(
              emailSugerido: c.email,
              titulo: 'Reingresá a tu local',
              subtitulo:
                  'La sesión de ${c.displayNombre} venció. Entrá una vez y queda guardada.',
            ),
          ),
        );
        break;
      case ResultadoCambioCuenta.error:
        setState(() => _cambiando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo cambiar de cuenta. Probá de nuevo.')),
        );
        break;
    }
  }

  Future<void> _confirmarCerrar(CuentaGuardada c) async {
    final esActiva = c.uid == VaultSesionesLocales().uidActivo;
    final cerrar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ColoresLocales.superficie,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Cerrar sesión',
            style: GoogleFonts.baloo2(color: ColoresLocales.textoOnFondoClaro, fontWeight: FontWeight.w800)),
        content: Text(
          esActiva
              ? 'Vas a cerrar la sesión de "${c.displayNombre}". Si tenés otra cuenta guardada, entrás a esa; si no, volvés al inicio de sesión.'
              : 'Se cierra "${c.displayNombre}" en este dispositivo. Para volver a usarla vas a tener que iniciar sesión de nuevo.',
          style: GoogleFonts.baloo2(color: ColoresLocales.textoSecundarioOnFondoClaro, height: 1.3),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar', style: GoogleFonts.baloo2(color: ColoresLocales.textoSecundarioOnFondoClaro)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cerrar', style: GoogleFonts.baloo2(color: const Color(0xFFE5484D), fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (cerrar != true) return;
    await _cerrarCuenta(c, esActiva);
  }

  /// Cierra la cuenta [c]. Si es la activa, salta a otra guardada (con remount)
  /// o vuelve al login. Si no es la activa, solo la saca del vault.
  Future<void> _cerrarCuenta(CuentaGuardada c, bool esActiva) async {
    final vault = VaultSesionesLocales();

    if (!esActiva) {
      await vault.quitar(c.uid);
      await _cargar();
      return;
    }

    setState(() => _cambiando = true);
    final res = await vault.salirDe(c.uid);
    if (!mounted) return;

    switch (res) {
      case ResultadoSalirCuenta.cambioAOtra:
        Navigator.of(context).pop();
        await recargarAppTrasCambioCuenta();
        return;
      case ResultadoSalirCuenta.requiereRelogin:
        final paraRelogin = await vault.primeraParaRelogin();
        final nav = Navigator.of(context, rootNavigator: true);
        Navigator.of(context).pop();
        await Future<void>.delayed(Duration.zero);
        if (paraRelogin != null) {
          nav.push(
            MaterialPageRoute(
              builder: (_) => LocalesLoginInterno(
                emailSugerido: paraRelogin.email,
                titulo: 'Reingresá a tu local',
                subtitulo:
                    'La sesión de ${paraRelogin.displayNombre} venció. Entrá una vez y queda guardada.',
              ),
            ),
          );
        } else {
          await Supabase.instance.client.auth.signOut();
        }
        return;
      case ResultadoSalirCuenta.sinCuentas:
        Navigator.of(context).pop();
        await Supabase.instance.client.auth.signOut();
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final activo = VaultSesionesLocales().uidActivo;
    return Container(
      decoration: BoxDecoration(
        color: ColoresLocales.superficie,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ColoresLocales.bordeSuave,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Text('Cambiar de cuenta',
                style: GoogleFonts.baloo2(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: ColoresLocales.textoOnFondoClaro,
                )),
            const SizedBox(height: 4),
            Text('Mantené apretada una cuenta para cerrarla',
                style: GoogleFonts.baloo2(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: ColoresLocales.textoSecundarioOnFondoClaro,
                )),
            const SizedBox(height: 12),
            if (_cargando)
              const Padding(
                padding: EdgeInsets.all(28),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _cuentas.length,
                  itemBuilder: (_, i) {
                    final c = _cuentas[i];
                    return _FilaCuenta(
                      cuenta: c,
                      activa: c.uid == activo,
                      deshabilitada: _cambiando,
                      onTap: () => _cambiar(c),
                      onLongPress: () => _confirmarCerrar(c),
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),
              _FilaAgregar(onTap: _cambiando ? null : _agregarCuenta),
            ],
            const SizedBox(height: 12),
            if (_cambiando)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Text('Cambiando…',
                        style: GoogleFonts.baloo2(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: ColoresLocales.textoSecundarioOnFondoClaro,
                        )),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FilaCuenta extends StatelessWidget {
  const _FilaCuenta({
    required this.cuenta,
    required this.activa,
    required this.deshabilitada,
    required this.onTap,
    required this.onLongPress,
  });

  final CuentaGuardada cuenta;
  final bool activa;
  final bool deshabilitada;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: deshabilitada && !activa ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: deshabilitada ? null : onTap,
          onLongPress: deshabilitada ? null : onLongPress,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            margin: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: activa ? ColoresLocales.violetaLogoMarca.withValues(alpha: 0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: activa ? ColoresLocales.violetaLogoMarca.withValues(alpha: 0.35) : ColoresLocales.bordeSuave,
              ),
            ),
            child: Row(
              children: [
                _AvatarCuenta(cuenta: cuenta),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cuenta.displayNombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.baloo2(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: ColoresLocales.textoOnFondoClaro,
                        ),
                      ),
                      if (cuenta.localUsername != null && cuenta.localUsername!.isNotEmpty)
                        Text(
                          '@${cuenta.localUsername}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.baloo2(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: ColoresLocales.textoSecundarioOnFondoClaro,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (cuenta.requiereRelogin)
                  const Icon(CupertinoIcons.exclamationmark_circle_fill, color: Color(0xFFF5A623), size: 20)
                else if (activa)
                  Icon(CupertinoIcons.checkmark_alt_circle_fill, color: ColoresLocales.violetaLogoMarca, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarCuenta extends StatelessWidget {
  const _AvatarCuenta({required this.cuenta});
  final CuentaGuardada cuenta;

  @override
  Widget build(BuildContext context) {
    final url = cuenta.fotoPerfilUrl;
    final inicial = cuenta.displayNombre.characters.firstOrNull?.toUpperCase() ?? 'L';
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ColoresLocales.violetaLogoMarca.withValues(alpha: 0.14),
      ),
      clipBehavior: Clip.antiAlias,
      child: (url != null && url.isNotEmpty)
          ? Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _inicial(inicial),
              loadingBuilder: (ctx, child, prog) =>
                  prog == null ? child : _inicial(inicial),
            )
          : _inicial(inicial),
    );
  }

  Widget _inicial(String inicial) => Center(
        child: Text(
          inicial,
          style: GoogleFonts.baloo2(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: ColoresLocales.violetaLogoMarca,
          ),
        ),
      );
}

class _FilaAgregar extends StatelessWidget {
  const _FilaAgregar({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ColoresLocales.violetaLogoMarca.withValues(alpha: 0.10),
                    border: Border.all(color: ColoresLocales.violetaLogoMarca.withValues(alpha: 0.4)),
                  ),
                  child: const Icon(CupertinoIcons.add, color: ColoresLocales.violetaLogoMarca, size: 22),
                ),
                const SizedBox(width: 12),
                Text('Agregar cuenta',
                    style: GoogleFonts.baloo2(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: ColoresLocales.violetaLogoMarca,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
