/// UI compartida — flujo crear perfil local (estilo iOS/minimal, violeta fijo).
library;

import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/colores_onboarding_locales.dart';

class OnbProgreso extends StatelessWidget {
  const OnbProgreso({super.key, required this.pasoActual, this.total = 3});

  final int pasoActual;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
      child: Row(
        children: List.generate(total, (i) {
          final n = i + 1;
          final activo = n <= pasoActual;
          final esUltimo = i == total - 1;
          return Expanded(
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: activo ? Colors.white : ColoresOnboardingLocales.vidrio,
                    border: Border.all(
                      color: activo ? Colors.white : ColoresOnboardingLocales.vidrioBorde,
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$n',
                      style: GoogleFonts.baloo2(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: activo
                            ? ColoresOnboardingLocales.violetaOscuro
                            : ColoresOnboardingLocales.textoSuave,
                      ),
                    ),
                  ),
                ),
                if (!esUltimo)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: n < pasoActual
                            ? Colors.white
                            : ColoresOnboardingLocales.vidrioBorde,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class OnbSeccionCard extends StatelessWidget {
  const OnbSeccionCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ColoresOnboardingLocales.vidrio,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ColoresOnboardingLocales.vidrioBorde),
      ),
      child: child,
    );
  }
}

class OnbTituloSeccion extends StatelessWidget {
  const OnbTituloSeccion({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.icono,
  });

  final String titulo;
  final String? subtitulo;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icono != null) ...[
              Icon(icono, color: ColoresOnboardingLocales.texto, size: 22),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                titulo,
                style: GoogleFonts.baloo2(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: ColoresOnboardingLocales.texto,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
        if (subtitulo != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitulo!,
            style: GoogleFonts.baloo2(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: ColoresOnboardingLocales.textoSecundario,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class OnbCampo extends StatelessWidget {
  const OnbCampo({
    super.key,
    required this.controller,
    this.titulo,
    this.ayuda,
    this.hint,
    this.keyboardType,
    this.maxLines = 1,
    this.maxLength,
    this.onChanged,
    this.suffix,
  });

  final TextEditingController controller;
  final String? titulo;
  final String? ayuda;
  final String? hint;
  final TextInputType? keyboardType;
  final int maxLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final campo = TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: keyboardType,
      maxLines: maxLines,
      maxLength: maxLength,
      style: GoogleFonts.baloo2(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: ColoresOnboardingLocales.texto,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.baloo2(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: ColoresOnboardingLocales.textoSuave,
        ),
        filled: true,
        fillColor: ColoresOnboardingLocales.inputFill,
        suffixIcon: suffix,
        counterStyle: GoogleFonts.baloo2(
          color: ColoresOnboardingLocales.textoSuave,
          fontSize: 12,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ColoresOnboardingLocales.inputBorde),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: ColoresOnboardingLocales.inputBorde),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white, width: 1.5),
        ),
      ),
    );

    if (titulo == null && ayuda == null) return campo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (titulo != null)
          Text(
            titulo!,
            style: GoogleFonts.baloo2(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: ColoresOnboardingLocales.texto,
            ),
          ),
        if (ayuda != null) ...[
          if (titulo != null) const SizedBox(height: 4),
          Text(
            ayuda!,
            style: GoogleFonts.baloo2(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: ColoresOnboardingLocales.textoSecundario,
              height: 1.3,
            ),
          ),
        ],
        const SizedBox(height: 8),
        campo,
      ],
    );
  }
}

class OnbBotonPrimario extends StatelessWidget {
  const OnbBotonPrimario({
    super.key,
    required this.label,
    required this.onPressed,
    this.icono,
    this.cargando = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icono;
  final bool cargando;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: FilledButton(
        onPressed: cargando ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: ColoresOnboardingLocales.botonClaro,
          foregroundColor: ColoresOnboardingLocales.botonClaroTexto,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: cargando
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ColoresOnboardingLocales.violetaOscuro,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icono != null) ...[
                    Icon(icono, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: GoogleFonts.baloo2(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class OnbBotonMostaza extends StatelessWidget {
  const OnbBotonMostaza({
    super.key,
    required this.label,
    required this.onPressed,
    this.icono,
    this.cargando = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icono;
  final bool cargando;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      width: double.infinity,
      child: FilledButton(
        onPressed: cargando ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: ColoresOnboardingLocales.mostaza,
          foregroundColor: ColoresOnboardingLocales.botonMostazaTexto,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: cargando
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ColoresOnboardingLocales.violetaProfundo,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icono != null) ...[
                    Icon(icono, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.baloo2(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class OnbBotonOutline extends StatelessWidget {
  const OnbBotonOutline({
    super.key,
    required this.label,
    required this.onPressed,
    this.icono,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: ColoresOnboardingLocales.texto,
          side: const BorderSide(color: ColoresOnboardingLocales.vidrioBorde, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icono != null) ...[
              Icon(icono, size: 18),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: GoogleFonts.baloo2(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class OnbAvatarSlot extends StatelessWidget {
  const OnbAvatarSlot({
    super.key,
    required this.onTap,
    this.bytes,
    this.radio = 56,
  });

  final VoidCallback onTap;
  final Uint8List? bytes;
  final double radio;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: radio * 2,
        height: radio * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ColoresOnboardingLocales.vidrio,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: bytes == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.person_crop_circle_badge_plus,
                    color: ColoresOnboardingLocales.texto,
                    size: radio * 0.65,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Avatar',
                    style: GoogleFonts.baloo2(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: ColoresOnboardingLocales.textoSecundario,
                    ),
                  ),
                ],
              )
            : ClipOval(child: Image.memory(bytes!, fit: BoxFit.cover)),
      ),
    );
  }
}

class OnbBannerSlot extends StatelessWidget {
  const OnbBannerSlot({super.key, required this.onTap, this.bytes});

  final VoidCallback onTap;
  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    // Vertical 4:5 — misma proporción con la que el banner se ve como hero
    // en el perfil del local (evita que suban fotos panorámicas).
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          height: 220,
          child: AspectRatio(
            aspectRatio: 4 / 5,
            child: Container(
              decoration: BoxDecoration(
                color: ColoresOnboardingLocales.vidrio,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: bytes == null
                      ? ColoresOnboardingLocales.vidrioBorde
                      : Colors.white,
                  width: bytes == null ? 1.5 : 2,
                ),
              ),
              child: bytes == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          CupertinoIcons.photo_on_rectangle,
                          color: ColoresOnboardingLocales.texto,
                          size: 32,
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'Banner vertical',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.baloo2(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: ColoresOnboardingLocales.textoSecundario,
                            ),
                          ),
                        ),
                      ],
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(bytes!, fit: BoxFit.cover),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class OnbFotoCuadradaSlot extends StatelessWidget {
  const OnbFotoCuadradaSlot({
    super.key,
    required this.onTap,
    this.bytes,
    this.indice,
  });

  final VoidCallback onTap;
  final Uint8List? bytes;
  final int? indice;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            color: ColoresOnboardingLocales.vidrio,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: bytes == null
                  ? ColoresOnboardingLocales.vidrioBorde
                  : Colors.white,
              width: bytes == null ? 1.5 : 2,
            ),
          ),
          child: bytes == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.plus_circle_fill,
                      color: ColoresOnboardingLocales.texto,
                      size: 28,
                    ),
                    if (indice != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Foto ${indice! + 1}',
                        style: GoogleFonts.baloo2(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: ColoresOnboardingLocales.textoSuave,
                        ),
                      ),
                    ],
                  ],
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(bytes!, fit: BoxFit.cover),
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            CupertinoIcons.pencil,
                            size: 12,
                            color: ColoresOnboardingLocales.violetaOscuro,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// Ítem informativo intro — icono grande + texto, sin card.
class OnbBeneficioIntro extends StatelessWidget {
  const OnbBeneficioIntro({
    super.key,
    required this.icono,
    required this.texto,
    this.colorIcono,
  });

  final IconData icono;
  final String texto;
  final Color? colorIcono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icono,
            size: 42,
            color: colorIcono ?? ColoresOnboardingLocales.mostaza,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                texto,
                style: GoogleFonts.baloo2(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: ColoresOnboardingLocales.texto,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OnbBeneficioPlan extends StatelessWidget {
  const OnbBeneficioPlan({
    super.key,
    required this.icono,
    required this.texto,
    this.colorIcono,
  });

  final IconData icono;
  final String texto;
  final Color? colorIcono;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ColoresOnboardingLocales.vidrio,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ColoresOnboardingLocales.vidrioBorde),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icono,
              size: 18,
              color: colorIcono ?? ColoresOnboardingLocales.mostaza,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              texto,
              style: GoogleFonts.baloo2(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ColoresOnboardingLocales.texto,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OnbChipRubro extends StatelessWidget {
  const OnbChipRubro({
    super.key,
    required this.label,
    required this.seleccionado,
    required this.onTap,
  });

  final String label;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: seleccionado ? Colors.white : ColoresOnboardingLocales.vidrio,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: seleccionado ? Colors.white : ColoresOnboardingLocales.vidrioBorde,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.baloo2(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: seleccionado
                ? ColoresOnboardingLocales.violetaOscuro
                : ColoresOnboardingLocales.texto,
          ),
        ),
      ),
    );
  }
}
