/// Wrapper que se aplica al home cuando la cuenta del local está pausada.
/// Muestra un banner rojo arriba + intercepta TODOS los taps con un modal
/// que solo permite ir a Soporte o cerrar sesión.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/recarga_cuenta_locales.dart';
import '../core/vault_sesiones_locales.dart';

class WrapperPausada extends StatelessWidget {
  /// Si `false`, el wrapper es transparente y renderiza el child como si nada.
  final bool pausada;
  final String? motivo;
  final Widget child;

  const WrapperPausada({
    super.key,
    required this.pausada,
    required this.motivo,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!pausada) return child;

    return Stack(
      children: [
        // 1) Contenido original — visible pero NO interactivo
        Positioned.fill(
          child: AbsorbPointer(absorbing: true, child: child),
        ),
        // 2) Capa transparente que captura CUALQUIER tap y abre modal
        Positioned.fill(
          top: 56, // deja libre el banner para que no pelee con su CTA
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _mostrarModal(context),
            child: const SizedBox.shrink(),
          ),
        ),
        // 3) Banner rojo arriba (SafeArea)
        SafeArea(
          bottom: false,
          child: _Banner(motivo: motivo, onTap: () => _mostrarModal(context)),
        ),
      ],
    );
  }

  Future<void> _mostrarModal(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEE2E2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.pause_circle_filled,
                    size: 52, color: Color(0xFFB91C1C)),
              ),
              const SizedBox(height: 16),
              Text(
                'Cuenta pausada',
                style: GoogleFonts.baloo2(
                  fontSize: 22, fontWeight: FontWeight.w900,
                  color: const Color(0xFF222033),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tu cuenta fue desactivada temporalmente por el equipo de Fernecito. '
                'Para reactivarla, contactá a soporte.',
                textAlign: TextAlign.center,
                style: GoogleFonts.baloo2(
                  fontSize: 13.5, color: Colors.black54, height: 1.35,
                ),
              ),
              if ((motivo ?? '').isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Motivo',
                          style: GoogleFonts.baloo2(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF991B1B))),
                      const SizedBox(height: 2),
                      Text(motivo!,
                          style: GoogleFonts.baloo2(
                              fontSize: 13,
                              color: const Color(0xFF7F1D1D),
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pushNamed('/soporte');
                  },
                  icon: const Icon(Icons.support_agent, size: 20),
                  label: Text(
                    'Ir a soporte',
                    style: GoogleFonts.baloo2(
                        fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5A2EFF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    final vault = VaultSesionesLocales();
                    final uid = vault.uidActivo;
                    if (uid != null) {
                      final res = await vault.salirDe(uid);
                      if (res == ResultadoSalirCuenta.cambioAOtra) {
                        await recargarAppTrasCambioCuenta();
                        return;
                      }
                    }
                    await Supabase.instance.client.auth.signOut();
                  },
                  icon: const Icon(Icons.logout, size: 18, color: Colors.black54),
                  label: Text(
                    'Cerrar sesión',
                    style: GoogleFonts.baloo2(
                        fontWeight: FontWeight.w700,
                        color: Colors.black54),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  'Entendido',
                  style: GoogleFonts.baloo2(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black38),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String? motivo;
  final VoidCallback onTap;
  const _Banner({required this.motivo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFDC2626), Color(0xFFB91C1C)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF991B1B).withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'CUENTA PAUSADA',
                      style: GoogleFonts.baloo2(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.4,
                      ),
                    ),
                    Text(
                      'Tocá acá para contactar a soporte',
                      style: GoogleFonts.baloo2(
                        fontSize: 11.5,
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
