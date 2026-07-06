import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants.dart';
import '../core/programa_pioneros.dart';
import '../core/servicio_edges_eventos.dart';
import '../core/suscripcion_locales.dart';
import '../widgets/badge_plan_suscripcion.dart';
import 'feedback_locales.dart';

/// Card dorada de invitación al Programa Pioneros (pestaña planes).
class CardInvitacionProgramaPioneros extends StatelessWidget {
  final VoidCallback? onCanjeado;

  const CardInvitacionProgramaPioneros({super.key, this.onCanjeado});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            ProgramaPioneros.dorado.withValues(alpha: 0.28),
            ColoresLocales.superficie,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: ProgramaPioneros.dorado.withValues(alpha: 0.45)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.star_circle_fill, color: ProgramaPioneros.dorado, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ProgramaPioneros.tituloInvitacion,
                  style: GoogleFonts.baloo2(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: ColoresLocales.textoOnFondoClaro,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            ProgramaPioneros.subtituloInvitacion,
            style: GoogleFonts.baloo2(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: ColoresLocales.textoSecundarioOnFondoClaro,
            ),
          ),
          const SizedBox(height: 14),
          ...ProgramaPioneros.beneficios.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(CupertinoIcons.checkmark_circle_fill, size: 16, color: ProgramaPioneros.dorado),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      b,
                      style: GoogleFonts.baloo2(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: ColoresLocales.textoOnFondoClaro,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: () => mostrarSheetCanjePionero(context, onCanjeado: onCanjeado),
            style: ElevatedButton.styleFrom(
              backgroundColor: ProgramaPioneros.dorado,
              foregroundColor: Colors.black87,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
            ),
            child: Text(
              'Canjear código Pioneros',
              style: GoogleFonts.baloo2(fontWeight: FontWeight.w900, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> mostrarSheetCanjePionero(
  BuildContext context, {
  VoidCallback? onCanjeado,
}) async {
  final controller = TextEditingController();
  var enviando = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ColoresLocales.superficie,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> enviar() async {
            if (enviando) return;
            final codigo = controller.text.trim();
            if (codigo.isEmpty) return;
            setSheet(() => enviando = true);
            try {
              await ServicioEdgesEventos().canjearCodigoPionero(codigo: codigo);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              FeedbackLocales.mostrarExito(context, '¡Programa Pioneros activado!');
              onCanjeado?.call();
            } catch (e) {
              if (!ctx.mounted) return;
              FeedbackLocales.mostrarError(context, e.toString());
            } finally {
              if (ctx.mounted) setSheet(() => enviando = false);
            }
          }

          final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ColoresLocales.textoSecundarioOnFondoClaro.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Canjear código Pioneros',
                  style: GoogleFonts.baloo2(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: ColoresLocales.textoOnFondoClaro,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'Código de invitación',
                    filled: true,
                    fillColor: ColoresLocales.cardInput.withValues(alpha: 0.6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: enviando ? null : enviar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ProgramaPioneros.dorado,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                  ),
                  child: enviando
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'Activar cuenta Pionero',
                          style: GoogleFonts.baloo2(fontWeight: FontWeight.w900, fontSize: 15),
                        ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

/// Chip "Pionero" debajo del nombre en la app de locales.
class ChipPioneroLocales extends StatelessWidget {
  const ChipPioneroLocales({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: ProgramaPioneros.dorado.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ProgramaPioneros.dorado.withValues(alpha: 0.45)),
      ),
      child: Text(
        'Pionero',
        style: GoogleFonts.baloo2(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: ProgramaPioneros.doradoOscuro,
        ),
      ),
    );
  }
}

/// Cabecera de resumen de suscripción para cuentas Pionero.
class CabeceraResumenPionero extends StatelessWidget {
  final EstadoSuscripcionLocal estado;

  const CabeceraResumenPionero({super.key, required this.estado});

  Color _colorPlan(String plan) => colorPlanSuscripcionUi(plan);

  @override
  Widget build(BuildContext context) {
    final contadores = ProgramaPioneros.contadoresBeneficios(
      mesBeneficio: estado.pioneroMesBeneficio,
      beneficiosActivos: estado.pioneroBeneficiosActivo,
    );
    final beneficiosActivos = estado.pioneroBeneficiosActivo;
    final enPremium = ProgramaPioneros.enFasePremiumBeneficios(
      beneficiosActivos: beneficiosActivos,
      mesBeneficio: estado.pioneroMesBeneficio,
    );
    final enPlus = ProgramaPioneros.enFasePlusBeneficios(
      beneficiosActivos: beneficiosActivos,
      mesBeneficio: estado.pioneroMesBeneficio,
    );
    final planActual = estado.tipoPlan;
    final planEtiqueta = ProgramaPioneros.etiquetaPlanSuscripcion(planActual);
    final colorPlan = _colorPlan(planActual);
    final vencimientoUi = estado.vencimientoTarjetaPionero;
    final premiumConPlus = estado.pioneroPremiumConPlusRegalo;
    final fechaUi = premiumConPlus
        ? (fecha: estado.fechaVencimiento, etiqueta: 'Premium vence el:')
        : enPlus && !premiumConPlus && estado.pioneroProximoReset != null
            ? (fecha: estado.pioneroProximoReset, etiqueta: 'Próximo ciclo Plus:')
            : vencimientoUi;
    final mostrarVencimiento = premiumConPlus
        ? estado.fechaVencimiento != null
        : beneficiosActivos
            ? fechaUi.fecha != null
            : estado.planActivo && estado.fechaVencimiento != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Mi plan',
              style: GoogleFonts.baloo2(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: ColoresLocales.textoSecundarioOnFondoClaro,
              ),
            ),
            const SizedBox(width: 8),
            const ChipPioneroLocales(),
          ],
        ),
        if (beneficiosActivos) ...[
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(CupertinoIcons.gift_fill, size: 18, color: ProgramaPioneros.dorado),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Beneficios:',
                      style: GoogleFonts.baloo2(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: ColoresLocales.textoOnFondoClaro,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (enPremium) ...[
                      Text(
                        '${contadores.premiumRestantes}/${ProgramaPioneros.mesesPremiumRegalo} meses Premium',
                        style: GoogleFonts.baloo2(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: ColoresLocales.textoSecundarioOnFondoClaro,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _BadgeBeneficioLuego(
                        texto: 'Luego, ${ProgramaPioneros.mesesPlusRegalo} meses Plus',
                      ),
                    ] else if (enPlus) ...[
                      Text(
                        '${contadores.plusRestantes}/${ProgramaPioneros.mesesPlusRegalo} meses Plus',
                        style: GoogleFonts.baloo2(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: ColoresLocales.textoSecundarioOnFondoClaro,
                        ),
                      ),
                      if (premiumConPlus) ...[
                        const SizedBox(height: 8),
                        _BadgeBeneficioLuego(
                          texto: 'Plus regalo sigue activo en paralelo',
                          color: const Color(0xFF0891B2),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        Container(height: 1, color: ColoresLocales.textoSecundarioOnFondoClaro.withValues(alpha: 0.15)),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mi suscripción',
                    style: GoogleFonts.baloo2(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: ColoresLocales.textoSecundarioOnFondoClaro,
                    ),
                  ),
                  Text(
                    planEtiqueta,
                    style: GoogleFonts.baloo2(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: colorPlan,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            if (mostrarVencimiento)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      fechaUi.etiqueta,
                      style: GoogleFonts.baloo2(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: ColoresLocales.textoSecundarioOnFondoClaro,
                      ),
                      textAlign: TextAlign.end,
                    ),
                    Text(
                      SuscripcionLocales.formatearFecha(
                        premiumConPlus
                            ? estado.fechaVencimiento!
                            : beneficiosActivos
                                ? fechaUi.fecha!
                                : estado.fechaVencimiento!,
                      ),
                      style: GoogleFonts.baloo2(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: ColoresLocales.textoOnFondoClaro,
                      ),
                      textAlign: TextAlign.end,
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (premiumConPlus) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _BadgeBeneficioLuego(
                texto: 'Renovación automática a Plus regalo al vencer Premium',
                color: ProgramaPioneros.doradoOscuro,
              ),
            ),
          ),
        ] else if (beneficiosActivos) ...[
          Builder(builder: (_) {
            final String texto;
            final int? partesDias;
            if (premiumConPlus && estado.fechaVencimiento != null) {
              texto = ProgramaPioneros.etiquetaTiempoRestanteBeneficio(
                estado.fechaVencimiento,
              );
              partesDias = estado.diasHastaVencimiento;
            } else if (enPlus && !premiumConPlus) {
              texto = ProgramaPioneros.etiquetaMesesPlusRegaloRestantes(
                contadores.plusRestantes,
              );
              partesDias = null;
            } else if (enPremium && vencimientoUi.fecha != null) {
              texto = ProgramaPioneros.etiquetaTiempoRestanteBeneficio(
                vencimientoUi.fecha,
              );
              partesDias = estado.diasHastaBeneficioGratisUi;
            } else if (fechaUi.fecha != null) {
              texto = ProgramaPioneros.etiquetaTiempoRestanteBeneficio(fechaUi.fecha);
              partesDias = estado.diasHastaBeneficioGratisUi;
            } else {
              return const SizedBox.shrink();
            }
            if (texto.isEmpty) return const SizedBox.shrink();
            final color = (partesDias ?? 999) <= 7
                ? ColoresLocales.mostazaDestacado
                : ColoresLocales.acentoVioleta;
            return Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(color: color.withValues(alpha: 0.32)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.timer, size: 14, color: color),
                        const SizedBox(width: 5),
                        Text(
                          texto,
                          style: GoogleFonts.baloo2(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}

class _BadgeBeneficioLuego extends StatelessWidget {
  final String texto;
  final Color? color;

  const _BadgeBeneficioLuego({required this.texto, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF0891B2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Text(
        texto,
        style: GoogleFonts.baloo2(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: c,
        ),
      ),
    );
  }
}

/// Aviso informativo en Mi suscripción / pagos para cuentas Pionero.
class BannerInfoPioneroSuscripcion extends StatelessWidget {
  final PioneroReglasSuscripcion reglas;
  final bool beneficiosTerminados;

  const BannerInfoPioneroSuscripcion({
    super.key,
    required this.reglas,
    this.beneficiosTerminados = false,
  });

  @override
  Widget build(BuildContext context) {
    final texto = beneficiosTerminados
        ? reglas.mensajePostBeneficios
        : reglas.mensajeRenovacionBloqueada;
    if (texto.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: ProgramaPioneros.dorado.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ProgramaPioneros.dorado.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.gift_fill, size: 20, color: ProgramaPioneros.dorado),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: GoogleFonts.baloo2(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: ColoresLocales.textoOnFondoClaro,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
