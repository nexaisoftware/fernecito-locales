/// Perfil del local (Mi local): mismo formato que pantalla_local_perfil pero editable.
/// Imágenes: ícono lápiz, al tocar abren picker/cámara. Textos y URLs: bottom sheet para editar.
library;

import 'dart:async';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../widgets/icono_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/comprimir_imagen_storage.dart';
import '../core/constants.dart';
import '../widgets/feedback_locales.dart';
import '../widgets/recorte_web_safe.dart';
import '../core/servicio_edges_eventos.dart';
import '../core/supabase_client.dart';
import '../core/vault_sesiones_locales.dart';
import '../core/recarga_cuenta_locales.dart';
import '../core/navegacion_locales.dart';
import '../core/suscripcion_locales.dart';
import '../core/programa_pioneros.dart';
import '../core/horarios_local.dart';
import '../widgets/programa_pioneros_ui.dart';
import '../widgets/badge_megusta_local.dart';
import '../widgets/badge_plan_suscripcion.dart';
import '../widgets/asistente_carta_sheet.dart';
import 'locales_calificaciones.dart';

class LocalesPerfil extends StatefulWidget {
  const LocalesPerfil({super.key});

  @override
  State<LocalesPerfil> createState() => _LocalesPerfilState();
}

class _FilaTramoHorario extends StatelessWidget {
  const _FilaTramoHorario({
    required this.tramo,
    this.onTapAbre,
    this.onTapCierra,
    this.onEliminar,
  });

  final TramoHorarioLocal tramo;
  final VoidCallback? onTapAbre;
  final VoidCallback? onTapCierra;
  final VoidCallback? onEliminar;

  @override
  Widget build(BuildContext context) {
    final cruzaMedianoche = tramo.cruzaMedianoche;

    Widget hora(String label, String value, VoidCallback? onTap) {
      return Flexible(
        fit: FlexFit.tight,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: ColoresMiLocalPerfil.rellenoInput,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.baloo2(
                    color: ColoresMiLocalPerfil.textoSecundario,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.baloo2(
                    color: ColoresMiLocalPerfil.textoPrincipal,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  hora('Abre', tramo.abre, onTapAbre),
                  const SizedBox(width: 8),
                  hora('Cierra', tramo.cierra, onTapCierra),
                ],
              ),
              if (cruzaMedianoche) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.moon_stars_fill,
                      size: 12,
                      color: ColoresMiLocalPerfil.principalMarca,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Cierra al día siguiente',
                        style: GoogleFonts.baloo2(
                          color: ColoresMiLocalPerfil.principalMarca,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (onEliminar != null) ...[
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(top: 9),
            child: IconButton(
              onPressed: onEliminar,
              icon: const Icon(CupertinoIcons.trash),
              color: ColoresMiLocalPerfil.textoSecundario,
            ),
          ),
        ],
      ],
    );
  }
}

class _BotonEditarHorariosLocal extends StatelessWidget {
  const _BotonEditarHorariosLocal({required this.estado, required this.onTap});

  final EstadoHorarioLocal estado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = estado.abierto
        ? const Color(0xFF27D66D)
        : ColoresMiLocalPerfil.textoSecundario;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: ColoresMiLocalPerfil.rellenoInput.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Icon(CupertinoIcons.clock_fill, size: 17, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    estado.tieneHorarios ? estado.titulo : 'Horarios',
                    style: GoogleFonts.baloo2(
                      color: ColoresMiLocalPerfil.textoPrincipal,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    estado.tieneHorarios
                        ? estado.detalle
                        : 'Ver y editar horarios del local',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.baloo2(
                      color: ColoresMiLocalPerfil.textoSecundario,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              CupertinoIcons.chevron_right,
              size: 17,
              color: ColoresMiLocalPerfil.textoSecundario,
            ),
          ],
        ),
      ),
    );
  }
}

class _BotonWhatsappEditableLocal extends StatelessWidget {
  const _BotonWhatsappEditableLocal({
    required this.tieneWhatsapp,
    required this.label,
    required this.onTap,
  });

  final bool tieneWhatsapp;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = tieneWhatsapp
        ? const Color(0xFF25D366)
        : ColoresMiLocalPerfil.textoSecundario;
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: ColoresMiLocalPerfil.rellenoInput.withValues(alpha: 0.66),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FontAwesomeIcons.whatsapp, size: 13, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  tieneWhatsapp ? label : 'Agregar WhatsApp de consultas',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.baloo2(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BotonCartaEditableLocal extends StatelessWidget {
  const _BotonCartaEditableLocal({
    required this.cantidadItems,
    required this.onTap,
  });

  final int cantidadItems;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tieneCarta = cantidadItems > 0;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: ColoresMiLocalPerfil.rellenoInput.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.list_bullet,
              size: 17,
              color: tieneCarta
                  ? const Color(0xFFFFD166)
                  : ColoresMiLocalPerfil.principalMarca,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tieneCarta ? 'Carta cargada' : 'Agregar carta con IA',
                    style: GoogleFonts.baloo2(
                      color: ColoresMiLocalPerfil.textoPrincipal,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    tieneCarta
                        ? '$cantidadItems items visibles para usuarios e IA'
                        : 'Precios, promos y productos para aparecer mejor en búsquedas',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.baloo2(
                      color: ColoresMiLocalPerfil.textoSecundario,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              CupertinoIcons.chevron_right,
              size: 17,
              color: ColoresMiLocalPerfil.textoSecundario,
            ),
          ],
        ),
      ),
    );
  }
}

class _BotonVerMiCartaLocal extends StatelessWidget {
  const _BotonVerMiCartaLocal({
    required this.cantidadItems,
    required this.onTap,
  });

  final int cantidadItems;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFFFD166).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                CupertinoIcons.eye_fill,
                size: 13,
                color: Color(0xFFFFD166),
              ),
              const SizedBox(width: 6),
              Text(
                'Ver mi carta',
                style: GoogleFonts.baloo2(
                  color: const Color(0xFFFFD166),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '$cantidadItems',
                style: GoogleFonts.baloo2(
                  color: ColoresMiLocalPerfil.textoSecundario,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool?> _mostrarMiCartaLocalSheet({
  required BuildContext context,
  required String nombreLocal,
  required List<CartaItemDraft> items,
}) {
  if (items.isEmpty) return Future.value(false);
  final editables = items.map((e) => e.copia()).toList();
  var guardando = false;

  Future<void> editarItem(
    BuildContext ctx,
    CartaItemDraft item,
    VoidCallback refresh,
  ) async {
    final categoriaCtrl = TextEditingController(text: item.categoria);
    final nombreCtrl = TextEditingController(text: item.nombre);
    final precioCtrl = TextEditingController(text: item.precio?.toStringAsFixed(0) ?? '');
    final descCtrl = TextEditingController(text: item.descripcion);
    await showCupertinoModalPopup<void>(
      context: ctx,
      builder: (_) => CupertinoActionSheet(
        title: Text(
          'Editar producto',
          style: GoogleFonts.baloo2(fontWeight: FontWeight.w900),
        ),
        message: Material(
          color: Colors.transparent,
          child: Column(
            children: [
              _campoEditorCarta(categoriaCtrl, 'Sección / categoría'),
              const SizedBox(height: 8),
              _campoEditorCarta(nombreCtrl, 'Nombre del producto'),
              const SizedBox(height: 8),
              _campoEditorCarta(
                precioCtrl,
                'Precio ARS',
                keyboard: TextInputType.number,
              ),
              const SizedBox(height: 8),
              _campoEditorCarta(descCtrl, 'Descripción breve', maxLines: 2),
            ],
          ),
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              final nombre = nombreCtrl.text.trim();
              final categoria = categoriaCtrl.text.trim();
              if (nombre.isEmpty || categoria.isEmpty) return;
              item
                ..categoria = categoria
                ..nombre = nombre
                ..descripcion = descCtrl.text.trim()
                ..precio = double.tryParse(precioCtrl.text.replaceAll(',', '.'))
                ..tipoPrecio = precioCtrl.text.trim().isEmpty ? 'consultar' : 'fijo';
              refresh();
              Navigator.pop(ctx);
            },
            child: const Text('Aplicar'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
      ),
    );
    categoriaCtrl.dispose();
    nombreCtrl.dispose();
    precioCtrl.dispose();
    descCtrl.dispose();
  }

  Future<void> agregarItem(
    BuildContext ctx,
    String categoria,
    VoidCallback refresh,
  ) async {
    final nuevo = CartaItemDraft(categoria: categoria, nombre: '');
    await editarItem(ctx, nuevo, () {
      if (nuevo.nombre.trim().isNotEmpty && nuevo.categoria.trim().isNotEmpty) {
        editables.add(nuevo);
      }
      refresh();
    });
  }

  Future<void> agregarSeccion(BuildContext ctx, VoidCallback refresh) async {
    final ctrl = TextEditingController();
    await showCupertinoDialog<void>(
      context: ctx,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Agregar sección'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(
            controller: ctrl,
            placeholder: 'Ej: Meriendas, Tragos, Promos',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              final categoria = ctrl.text.trim();
              if (categoria.isNotEmpty) {
                editables.add(CartaItemDraft(categoria: categoria, nombre: 'Nuevo producto'));
                refresh();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }

  Future<void> guardar(BuildContext ctx, VoidCallback refresh) async {
    if (guardando) return;
    final validos = editables
        .where((e) => e.nombre.trim().isNotEmpty && e.categoria.trim().isNotEmpty)
        .map((e) => e.toMap())
        .toList();
    if (validos.isEmpty) return;
    guardando = true;
    refresh();
    try {
      await ServicioEdgesEventos().asistenteCartaLocal(
        accion: 'guardar',
        items: validos,
        origen: 'manual',
      );
      if (!ctx.mounted) return;
      Navigator.of(ctx).pop(true);
    } catch (e) {
      guardando = false;
      refresh();
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la carta: $e')),
      );
    }
  }

  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (ctx) {
      final media = MediaQuery.of(ctx);
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          final grupos = <String, List<CartaItemDraft>>{};
          for (final item in editables) {
            final key = item.categoria.trim().isEmpty ? 'Otros' : item.categoria.trim();
            grupos.putIfAbsent(key, () => <CartaItemDraft>[]).add(item);
          }
          void refresh() => setModalState(() {});
          return SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: media.size.height * 0.86),
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF161618),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD166).withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            CupertinoIcons.list_bullet,
                            size: 17,
                            color: Color(0xFFFFD166),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Carta de $nombreLocal',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.baloo2(
                                  color: ColoresMiLocalPerfil.textoPrincipal,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  height: 1.05,
                                ),
                              ),
                              Text(
                                'Tocá un producto para editar nombre, precio o sección',
                                style: GoogleFonts.baloo2(
                                  color: ColoresMiLocalPerfil.textoSecundario,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: guardando ? null : () => Navigator.pop(ctx, false),
                          icon: const Icon(CupertinoIcons.xmark),
                          color: ColoresMiLocalPerfil.textoSecundario,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.only(
                          bottom: media.viewPadding.bottom > 0 ? 8 : 0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final entry in grupos.entries) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: 8, bottom: 7),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        entry.key,
                                        style: GoogleFonts.baloo2(
                                          color: const Color(0xFFFFD166),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: guardando
                                          ? null
                                          : () => agregarItem(ctx, entry.key, refresh),
                                      child: Text(
                                        'Agregar ítem',
                                        style: GoogleFonts.baloo2(
                                          color: ColoresMiLocalPerfil.principalMarca,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              for (final item in entry.value)
                                _MiCartaLocalItemTile(
                                  item: item,
                                  onTap: () => editarItem(ctx, item, refresh),
                                  onDelete: () {
                                    editables.remove(item);
                                    refresh();
                                  },
                                ),
                            ],
                            const SizedBox(height: 8),
                            _BotonMiniCarta(
                              texto: 'Agregar sección',
                              icono: CupertinoIcons.plus_circle,
                              onTap: guardando ? null : () => agregarSeccion(ctx, refresh),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _BotonMiniCarta(
                            texto: 'Editar con IA',
                            icono: CupertinoIcons.sparkles,
                            onTap: guardando
                                ? null
                                : () {
                                    Navigator.pop(ctx, false);
                                    abrirAsistenteCartaLocal(
                                      context,
                                      cartaItemsPrevios: editables.length,
                                    );
                                  },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _BotonMiniCarta(
                            texto: guardando ? 'Guardando...' : 'Guardar cambios',
                            icono: CupertinoIcons.checkmark_circle_fill,
                            primario: true,
                            onTap: guardando ? null : () => guardar(ctx, refresh),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class _MiCartaLocalItemTile extends StatelessWidget {
  const _MiCartaLocalItemTile({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  final CartaItemDraft item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  String _precio() {
    final precio = item.precio;
    if (precio == null) return 'Consultar';
    final p = precio.round().toString();
    if (item.tipoPrecio == 'desde') return 'Desde \$$p';
    if (item.tipoPrecio == 'rango' && item.precioHasta != null) {
      return '\$$p - \$${item.precioHasta!.round()}';
    }
    if (item.tipoPrecio == 'aproximado') return '~\$$p';
    return '\$$p';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF202024),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.nombre,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.baloo2(
                          color: ColoresMiLocalPerfil.textoPrincipal,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                    ),
                    if (item.destacado) ...[
                      const SizedBox(width: 5),
                      const Icon(
                        CupertinoIcons.star_fill,
                        size: 12,
                        color: Color(0xFFFFD166),
                      ),
                    ],
                  ],
                ),
                if (item.descripcion.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.descripcion,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.baloo2(
                      color: ColoresMiLocalPerfil.textoSecundario,
                      fontSize: 12,
                      height: 1.15,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _precio(),
                style: GoogleFonts.baloo2(
                  color: const Color(0xFFFFD166),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              GestureDetector(
                onTap: onDelete,
                child: Icon(
                  CupertinoIcons.trash,
                  size: 15,
                  color: Colors.white.withValues(alpha: 0.42),
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}

Widget _campoEditorCarta(
  TextEditingController ctrl,
  String hint, {
  int maxLines = 1,
  TextInputType? keyboard,
}) {
  return CupertinoTextField(
    controller: ctrl,
    maxLines: maxLines,
    keyboardType: keyboard,
    placeholder: hint,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: ColoresLocales.superficieElevada,
      borderRadius: BorderRadius.circular(12),
    ),
    style: GoogleFonts.baloo2(
      color: ColoresLocales.textoOnFondoClaro,
      fontWeight: FontWeight.w700,
    ),
    placeholderStyle: GoogleFonts.baloo2(
      color: ColoresLocales.textoSecundarioOnFondoClaro,
    ),
  );
}

class _BotonMiniCarta extends StatelessWidget {
  const _BotonMiniCarta({
    required this.texto,
    required this.icono,
    required this.onTap,
    this.primario = false,
  });

  final String texto;
  final IconData icono;
  final VoidCallback? onTap;
  final bool primario;

  @override
  Widget build(BuildContext context) {
    final color = primario ? const Color(0xFFFFD166) : const Color(0xFF2A2A30);
    final textoColor = primario ? const Color(0xFF211700) : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: onTap == null ? 0.55 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icono, size: 15, color: textoColor),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  texto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.baloo2(
                    color: textoColor,
                    fontSize: 12.6,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverlayPickerHora extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        height: 42,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: ColoresMiLocalPerfil.principalMarca.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ColoresMiLocalPerfil.principalMarca.withValues(alpha: 0.22),
          ),
        ),
      ),
    );
  }
}

class _LocalesPerfilState extends State<LocalesPerfil> {
  static const int _maxFotosLocales = 10;
  static final String _selectFotosLocales = List.generate(
    _maxFotosLocales,
    (i) => 'foto_local_${i + 1}',
  ).join(', ');

  bool _cargando = true;
  String? _nombreLocal;
  String? _fotoPerfilUrl;
  String? _urlBanner;
  String? _descripcion;
  String? _direccion;
  String? _urlMaps;
  String? _urlInstagram;
  String? _urlTiktok;
  String? _urlWebsite;
  String? _telefonoWhatsapp;
  String? _whatsappLabel;
  final List<String?> _fotosLocal = List<String?>.filled(
    _maxFotosLocales,
    null,
  );
  double? _calificacion;
  int _calificacionCantidad = 0;
  int _cantidadMegusta = 0;
  int _cantidadItemsCarta = 0;
  List<CartaItemDraft> _itemsCarta = [];
  bool _localVerificado = false;
  String? _ciudad;
  String? _provincia;
  List<String> _rubros = [];
  HorariosLocal _horarios = {};
  bool _infoExpandida =
      true; // info del lugar desplegada por defecto (como app usuarios)
  EstadoSuscripcionLocal? _estadoSuscripcion;
  final ImagePicker _picker = ImagePicker();

  static const _rubrosDisponibles = <String>[
    'Bar',
    'Boliche',
    'Cerveceria',
    'Restaurante',
    'Pub',
    'Cafe',
    'Eventos',
    'After',
  ];

  /// Versiones para cache-bust: Android/navegador cachean por URL; al subir nueva foto la URL no cambia.
  int _versionAvatar = 0;
  int _versionBanner = 0;
  int _versionFotosLocal = 0;

  static const Set<String> _camposUrl = {
    'url_maps',
    'url_instagram',
    'url_tiktok',
    'url_website',
    'foto_perfil_url',
    'url_foto_banner',
    'foto_local_1',
    'foto_local_2',
    'foto_local_3',
    'foto_local_4',
    'foto_local_5',
    'foto_local_6',
    'foto_local_7',
    'foto_local_8',
    'foto_local_9',
    'foto_local_10',
  };

  String _urlConCacheBust(String? url, int version) {
    if (url == null || url.isEmpty) return '';
    return '$url${url.contains('?') ? '&' : '?'}v=$version';
  }

  String? _normalizarUrlOpcional(String? raw) {
    final v = raw?.trim() ?? '';
    if (v.isEmpty) return null;
    final conEsquema = v.contains('://') ? v : 'https://$v';
    final uri = Uri.tryParse(conEsquema);
    if (uri == null) return null;
    final esquemaValido = uri.scheme == 'http' || uri.scheme == 'https';
    if (!esquemaValido || uri.host.isEmpty) return null;
    return uri.toString();
  }

  bool _esCampoUrlEditable(String campoDb) => campoDb.startsWith('url_');

  String? _normalizarWhatsappOpcional(String? raw) {
    var digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (digits.length >= 10 && !digits.startsWith('54')) {
      digits = '549$digits';
    }
    if (digits.startsWith('54') && !digits.startsWith('549')) {
      digits = '549${digits.substring(2)}';
    }
    if (digits.isEmpty) return null;
    if (digits.length < 10 || digits.length > 15) return null;
    return digits;
  }

  String _telefonoWhatsappVisible(String? raw) {
    final n = raw?.trim() ?? '';
    if (n.isEmpty) return '';
    return n.startsWith('+') ? n : '+$n';
  }

  String _labelWhatsappVisible(String? raw) {
    final label = raw?.trim() ?? '';
    return label.isEmpty ? 'Consultas por WhatsApp' : label;
  }

  String? _normalizarWhatsappLabelOpcional(String? raw) {
    final clean = (raw ?? '')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[<>{}\\[\\]`]'), '');
    if (clean.isEmpty) return null;
    return clean.length > 28 ? clean.substring(0, 28) : clean;
  }

  Future<void> _pegarTextoEnControlador(
    TextEditingController controller,
  ) async {
    final data = await Clipboard.getData('text/plain');
    final pegado = data?.text?.trim() ?? '';
    if (pegado.isEmpty) return;

    final textoActual = controller.text;
    final sel = controller.selection;
    final inicio = sel.start >= 0 ? sel.start : textoActual.length;
    final fin = sel.end >= 0 ? sel.end : textoActual.length;
    final nuevoTexto = textoActual.replaceRange(inicio, fin, pegado);

    controller.value = TextEditingValue(
      text: nuevoTexto,
      selection: TextSelection.collapsed(offset: inicio + pegado.length),
    );
  }

  @override
  void initState() {
    super.initState();
    _cargarPerfil();
  }

  Future<void> _cargarPerfil() async {
    final uid = ServicioSupabase().usuarioActual?.id;
    if (uid == null) {
      setState(() => _cargando = false);
      return;
    }
    try {
      final row = await ServicioSupabase().cliente
          .from('perfiles_locales')
          .select(
            'nombre_local, direccion, foto_perfil_url, url_foto_banner, descripcion_local, '
            'url_maps, url_instagram, url_tiktok, url_website, telefono_whatsapp, whatsapp_label, '
            '$_selectFotosLocales, '
            'calificacion_promedio, calificacion_cantidad, cantidad_megusta, local_verificado, plan_suscripcion, '
            'ciudad, provincia, rubro, horarios_json',
          )
          .eq('id', uid)
          .maybeSingle();
      final estadoSuscripcion = await SuscripcionLocales.cargarEstadoCompleto(
        uid,
      );
      final cartaRaw = await ServicioSupabase().cliente
          .from('locales_carta_items')
          .select(
            'categoria, nombre, descripcion, precio, precio_hasta, moneda, tipo_precio, tags, destacado, confidence',
          )
          .eq('id_local', uid)
          .eq('activo', true)
          .order('categoria')
          .order('orden')
          .limit(100);
      final itemsCarta = cartaRaw
          .whereType<Map>()
          .map((e) => CartaItemDraft.fromMap(Map<String, dynamic>.from(e)))
          .where((e) => e.nombre.trim().isNotEmpty)
          .toList();
      final cantidadItemsCarta = itemsCarta.length;
      if (!mounted) return;
      setState(() {
        _nombreLocal = row?['nombre_local'] as String?;
        _direccion = row?['direccion'] as String?;
        _fotoPerfilUrl = row?['foto_perfil_url'] as String?;
        _urlBanner = row?['url_foto_banner'] as String?;
        _descripcion = row?['descripcion_local'] as String?;
        _urlMaps = row?['url_maps'] as String?;
        _urlInstagram = row?['url_instagram'] as String?;
        _urlTiktok = row?['url_tiktok'] as String?;
        _urlWebsite = row?['url_website'] as String?;
        _telefonoWhatsapp = row?['telefono_whatsapp'] as String?;
        _whatsappLabel = row?['whatsapp_label'] as String?;
        for (var i = 0; i < _maxFotosLocales; i++) {
          _fotosLocal[i] = row?['foto_local_${i + 1}'] as String?;
        }
        final prom = row?['calificacion_promedio'];
        _calificacion = prom != null ? (prom as num).toDouble() : null;
        final cant = row?['calificacion_cantidad'];
        _calificacionCantidad = cant is int
            ? cant
            : (cant != null ? int.tryParse(cant.toString()) ?? 0 : 0);
        final mg = row?['cantidad_megusta'];
        _cantidadMegusta = mg is int
            ? mg
            : (mg != null ? int.tryParse(mg.toString()) ?? 0 : 0);
        _cantidadItemsCarta = cantidadItemsCarta;
        _itemsCarta = itemsCarta;
        if (_calificacion != null && _calificacion! <= 0) _calificacion = null;
        _localVerificado = row?['local_verificado'] as bool? ?? false;
        _ciudad = row?['ciudad'] as String?;
        _provincia = row?['provincia'] as String?;
        final rubroRaw = row?['rubro'];
        _rubros = rubroRaw is List
            ? rubroRaw
                  .map((r) => r.toString())
                  .where((s) => s.trim().isNotEmpty)
                  .toList()
            : <String>[];
        _horarios = parseHorariosLocal(row?['horarios_json']);
        _estadoSuscripcion = estadoSuscripcion;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _cargando = false);
        _mostrarError('No se pudo cargar el perfil: $e');
      }
    }
  }

  Future<void> _abrirAsistenteCarta() async {
    final guardo = await abrirAsistenteCartaLocal(
      context,
      cartaItemsPrevios: _cantidadItemsCarta,
    );
    if (guardo == true) {
      await _cargarPerfil();
    }
  }

  Future<void> _verMiCarta() async {
    final guardo = await _mostrarMiCartaLocalSheet(
      context: context,
      nombreLocal: (_nombreLocal ?? 'tu local').trim().isEmpty
          ? 'tu local'
          : _nombreLocal!.trim(),
      items: _itemsCarta,
    );
    if (guardo == true) {
      await _cargarPerfil();
      if (mounted) _mostrarExito('Carta actualizada');
    }
  }

  Future<bool> _actualizarCampo(String key, dynamic value) async {
    if (ServicioSupabase().usuarioActual?.id == null) return false;
    dynamic valorFinal = value;

    if (key == 'rubro') {
      if (value is! List) return false;
      valorFinal = value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .take(10)
          .toList();
    } else if (_camposUrl.contains(key)) {
      if (value == null) {
        valorFinal = null;
      } else {
        final normalizada = _normalizarUrlOpcional(value.toString());
        if (normalizada == null) {
          if (mounted) {
            _mostrarError(
              'URL inválida. Usá un formato como https://tu-url.com.\n\n'
              'Tip: podés pegar sin https y la app lo completa automáticamente.',
            );
          }
          return false;
        }
        valorFinal = normalizada;
      }
    } else if (key == 'telefono_whatsapp') {
      if (value == null || value.toString().trim().isEmpty) {
        valorFinal = null;
      } else {
        final normalizado = _normalizarWhatsappOpcional(value.toString());
        if (normalizado == null) {
          if (mounted) {
            _mostrarError(
              'WhatsApp inválido. Usá un número con característica, por ejemplo 3511234567 o +5493511234567.',
            );
          }
          return false;
        }
        valorFinal = normalizado;
      }
    } else if (key == 'whatsapp_label') {
      valorFinal = _normalizarWhatsappLabelOpcional(value?.toString());
    }

    try {
      await ServicioEdgesEventos().guardarPerfilLocal(
        perfil: {key: valorFinal},
        modo: 'basico',
      );
      if (!mounted) return true;
      await _cargarPerfil();
      if (!mounted) return true;
      _mostrarExito('Guardado correctamente');
      return true;
    } catch (e) {
      if (mounted) _mostrarError('No se pudo guardar: $e');
      return false;
    }
  }

  void _mostrarExito(String msg) {
    FeedbackLocales.mostrarExito(context, msg);
  }

  PerfilImagenStorage _perfilBucket(String bucket) {
    switch (bucket) {
      case 'avatars_locales':
        return PerfilImagenStorage.avatarLocal;
      case 'banners_locales':
        return PerfilImagenStorage.bannerLocal;
      case 'fotos_locales':
      default:
        return PerfilImagenStorage.fotoLocal;
    }
  }

  /// Extrae el path relativo del bucket desde URL pública o path ya relativo.
  String? _pathStorageDesdeUrlOPath(String? urlOPath, String bucket) {
    final raw = urlOPath?.trim() ?? '';
    if (raw.isEmpty) return null;
    final sinQuery = raw.split('?').first;
    if (!sinQuery.startsWith('http')) {
      return sinQuery.startsWith('/') ? sinQuery.substring(1) : sinQuery;
    }
    final marker = '/object/public/$bucket/';
    final i = sinQuery.indexOf(marker);
    if (i < 0) return null;
    return Uri.decodeComponent(sinQuery.substring(i + marker.length));
  }

  String? _urlActualDelCampo(String campoDb) {
    if (campoDb == 'foto_perfil_url') return _fotoPerfilUrl;
    if (campoDb == 'url_foto_banner') return _urlBanner;
    if (campoDb.startsWith('foto_local_')) {
      final n = int.tryParse(campoDb.replaceFirst('foto_local_', ''));
      if (n == null || n < 1 || n > _maxFotosLocales) return null;
      return _fotosLocal[n - 1];
    }
    return null;
  }

  /// Borra el archivo anterior del slot. Best-effort: no falla el flujo visual.
  Future<void> _borrarArchivoStorageAnterior({
    required String bucket,
    required String pathSuffix,
    required String pathNuevo,
    required String? urlAnterior,
  }) async {
    final uid = ServicioSupabase().usuarioActual?.id;
    if (uid == null) return;

    final paths = <String>{};
    final pathViejo = _pathStorageDesdeUrlOPath(urlAnterior, bucket);
    if (pathViejo != null && pathViejo.isNotEmpty) paths.add(pathViejo);

    // Paths legacy fijos (antes del timestamp) por si quedó huérfano.
    for (final ext in const ['jpg', 'jpeg', 'webp', 'png']) {
      paths.add('$uid/$pathSuffix.$ext');
    }

    paths.removeWhere(
      (p) =>
          p.isEmpty ||
          p == pathNuevo ||
          !p.startsWith('$uid/') ||
          p.contains('..'),
    );
    if (paths.isEmpty) return;

    try {
      await ServicioSupabase().cliente.storage
          .from(bucket)
          .remove(paths.toList());
    } catch (_) {
      // No bloquear el reemplazo si el borrado falla (CDN/policy).
    }
  }

  Future<({String url, String path})> _subirImagen(
    String bucket,
    String pathBase,
    Uint8List bytes,
  ) async {
    final comprimida = await comprimirImagenStorage(
      bytes,
      perfil: _perfilBucket(bucket),
    );
    final path = pathBase.contains('.')
        ? pathBase
        : '$pathBase${comprimida.pathSuffix}';
    await ServicioSupabase().cliente.storage
        .from(bucket)
        .uploadBinary(
          path,
          comprimida.bytes,
          fileOptions: FileOptions(
            // Path único por subida → siempre INSERT (no depende de policy UPDATE).
            upsert: false,
            contentType: comprimida.contentType,
          ),
        );
    final url = ServicioSupabase().cliente.storage
        .from(bucket)
        .getPublicUrl(path);
    return (url: url, path: path);
  }

  Future<void> _elegirImagen({
    required String bucket,
    required String pathSuffix,
    required String campoDb,
    required int minWidth,
    required VoidCallback onSuccess,
  }) async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 88,
    );
    if (file == null || !mounted) return;
    var bytes = await file.readAsBytes();
    if (!mounted) return;
    // Logo del local: mismo paso de recorte circular que en crear perfil.
    if (campoDb == 'foto_perfil_url') {
      final recortada = await mostrarRecorteLogoSheet(context, bytes);
      if (recortada == null || !mounted) return; // canceló el recorte
      bytes = recortada;
    }
    final uid = ServicioSupabase().usuarioActual?.id;
    if (uid == null) return;

    // Capturar URL vieja ANTES de subir/guardar, para borrarla después.
    final urlAnterior = _urlActualDelCampo(campoDb);

    try {
      // Path con timestamp: la URL pública cambia siempre (evita CDN viejo).
      final ts = DateTime.now().millisecondsSinceEpoch;
      final pathBase = '$uid/${pathSuffix}_$ts';
      final subida = await _subirImagen(bucket, pathBase, bytes);
      final ok = await _actualizarCampo(campoDb, subida.url);
      if (!mounted) return;
      if (ok) {
        // Solo borramos la vieja si la nueva ya quedó persistida en DB.
        await _borrarArchivoStorageAnterior(
          bucket: bucket,
          pathSuffix: pathSuffix,
          pathNuevo: subida.path,
          urlAnterior: urlAnterior,
        );
        setState(() {
          if (campoDb == 'foto_perfil_url') {
            _versionAvatar++;
          } else if (campoDb == 'url_foto_banner') {
            _versionBanner++;
          } else if (campoDb.startsWith('foto_local_')) {
            _versionFotosLocal++;
          }
        });
        onSuccess();
      }
    } catch (e) {
      if (mounted) _mostrarError('No se pudo subir la imagen: $e');
    }
  }

  void _mostrarError(String msg) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: ColoresLocales.fondoSuperficie,
        title: Text(
          'Error',
          style: GoogleFonts.baloo2(color: ColoresLocales.textoPrincipal),
        ),
        content: Text(msg, style: GoogleFonts.baloo2(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(
              'OK',
              style: GoogleFonts.baloo2(color: ColoresLocales.acentoVioleta),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _eliminarCuenta() async {
    final confirmado = await Navigator.of(context, rootNavigator: true)
        .push<bool>(
          MaterialPageRoute<bool>(
            fullscreenDialog: true,
            builder: (_) => const _PantallaConfirmarEliminarCuenta(),
          ),
        );

    if (confirmado != true || !mounted) return;

    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (c) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CupertinoActivityIndicator(),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Eliminando tu cuenta…',
                  style: GoogleFonts.baloo2(
                    color: ColoresLocales.textoOnFondoClaro,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      await ServicioEdgesEventos().eliminarCuentaLocal();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      // Sacar del vault la cuenta eliminada y saltar a otra (o al login).
      await _salirCuentaActual();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _mostrarError('No se pudo eliminar tu cuenta: $e');
    }
  }

  /// Cierra sesión de la cuenta ACTUAL: la saca del vault multi-cuenta y, si hay
  /// otra guardada, salta a ella (sin login) forzando el remount de la UI.
  /// Si no queda ninguna usable, sale al login.
  Future<void> _salirCuentaActual() async {
    final vault = VaultSesionesLocales();
    final actual = vault.uidActivo;
    if (actual != null) await vault.quitar(actual);

    // Probar cuentas restantes hasta encontrar una con sesión viva.
    for (final c in await vault.listar()) {
      final res = await vault.cambiarA(c.uid);
      if (res == ResultadoCambioCuenta.ok) {
        // Clave: forzar splash + remount (si no, la UI queda con la cuenta vieja).
        await recargarAppTrasCambioCuenta();
        return;
      }
    }
    // Sin otra cuenta usable → cierre normal (el AuthGate va al login).
    await Supabase.instance.client.auth.signOut();
  }

  Future<void> _mostrarRecordatorioMaps() async {
    await showCupertinoDialog(
      context: context,
      builder: (c) => CupertinoAlertDialog(
        title: Text('Ubicación en Google Maps', style: GoogleFonts.baloo2()),
        content: Padding(
          padding: EdgeInsets.only(top: 8.0),
          child: Text(
            'Recordá agregar la URL de tu ubicación exacta en Google Maps. ¡Así los usuarios pueden llegar a tu local con un solo click!',
            style: GoogleFonts.baloo2(),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(c).pop(),
            child: Text(
              'Por ahora no',
              style: GoogleFonts.baloo2(
                color: ColoresLocales.textoSecundarioOnFondoClaro,
              ),
            ),
          ),
          CupertinoDialogAction(
            onPressed: () {
              Navigator.of(c).pop();
              _showEditSheet(
                titulo: 'URL de Google Maps',
                valorActual: _urlMaps ?? '',
                hint: 'Pegá la URL de Google Maps aquí',
                campoDb: 'url_maps',
              );
            },
            child: Text(
              'Agregar URL de Maps',
              style: GoogleFonts.baloo2(color: ColoresLocales.acentoVioleta),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditSheet({
    required String titulo,
    required String valorActual,
    required String hint,
    required String campoDb,
    int maxLines = 1,
    int? maxLength,
  }) {
    final c = TextEditingController(text: valorActual);
    final inputRadius = maxLines > 1 ? 25.0 : 50.0;
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(inputRadius),
      borderSide: BorderSide.none,
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        var guardando = false;
        return StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: ColoresMiLocalPerfil.superficie,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    titulo,
                    style: GoogleFonts.baloo2(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: ColoresMiLocalPerfil.acentoVioleta,
                    ),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: c,
                    enabled: !guardando,
                    maxLines: maxLines,
                    maxLength: maxLength,
                    keyboardType: campoDb == 'telefono_whatsapp'
                        ? TextInputType.phone
                        : (_esCampoUrlEditable(campoDb)
                              ? TextInputType.url
                              : TextInputType.text),
                    decoration: InputDecoration(
                      hintText: hint,
                      counterText: maxLength != null ? null : '',
                      hintStyle: GoogleFonts.baloo2(
                        color: ColoresMiLocalPerfil.textoSecundario,
                        fontSize: 14,
                      ),
                      filled: true,
                      fillColor: ColoresMiLocalPerfil.rellenoInput,
                      enabledBorder: inputBorder,
                      focusedBorder: inputBorder,
                      border: inputBorder,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      suffixIcon:
                          (_esCampoUrlEditable(campoDb) ||
                              campoDb == 'telefono_whatsapp')
                          ? IconButton(
                              tooltip: 'Pegar',
                              onPressed: guardando
                                  ? null
                                  : () => _pegarTextoEnControlador(c),
                              icon: Icon(Icons.paste_rounded),
                              color: ColoresMiLocalPerfil.acentoVioleta,
                            )
                          : null,
                    ),
                    style: GoogleFonts.baloo2(
                      color: ColoresMiLocalPerfil.textoPrincipal,
                    ),
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton(
                        onPressed: guardando ? null : () => Navigator.pop(ctx),
                        child: Text(
                          'Cancelar',
                          style: GoogleFonts.baloo2(
                            color: ColoresMiLocalPerfil.textoSecundario,
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: guardando
                              ? null
                              : () async {
                                  setSheetState(() => guardando = true);
                                  final v = c.text.trim();
                                  final ok = await _actualizarCampo(
                                    campoDb,
                                    v.isEmpty ? null : v,
                                  );
                                  if (!ctx.mounted) return;
                                  if (ok) {
                                    Navigator.pop(ctx);
                                    if (campoDb == 'direccion' &&
                                        v.isNotEmpty) {
                                      await _mostrarRecordatorioMaps();
                                    }
                                  } else {
                                    setSheetState(() => guardando = false);
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                ColoresMiLocalPerfil.principalMarca,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(50),
                            ),
                          ),
                          child: guardando
                              ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Guardar',
                                  style: GoogleFonts.baloo2(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _editarBanner() {
    HapticFeedback.lightImpact();
    _elegirImagen(
      bucket: 'banners_locales',
      pathSuffix: 'foto_banner',
      campoDb: 'url_foto_banner',
      minWidth: 1600,
      onSuccess: () => setState(() {}),
    );
  }

  void _editarDescripcion() {
    HapticFeedback.lightImpact();
    _showEditSheet(
      titulo: 'Descripción del local',
      valorActual: _descripcion ?? '',
      hint: 'Contanos qué hace especial a tu local',
      campoDb: 'descripcion_local',
      maxLines: 6,
      maxLength: LimitesMiLocalPerfil.maxCaracteresDescripcion,
    );
  }

  void _editarWhatsapp() {
    HapticFeedback.lightImpact();
    _showWhatsappSheet();
  }

  void _showWhatsappSheet() {
    final telefonoCtrl = TextEditingController(
      text: _telefonoWhatsappVisible(_telefonoWhatsapp),
    );
    final labelCtrl = TextEditingController(
      text: _labelWhatsappVisible(_whatsappLabel),
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide.none,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        var guardando = false;
        return StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: ColoresMiLocalPerfil.superficie,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'WhatsApp del local',
                    style: GoogleFonts.baloo2(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: ColoresMiLocalPerfil.acentoVioleta,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Personalizá el texto del botón público. Cortito: reservas, consultas o pedidos.',
                    style: GoogleFonts.baloo2(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ColoresMiLocalPerfil.textoSecundario,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Texto del botón',
                    style: GoogleFonts.baloo2(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: ColoresMiLocalPerfil.textoPrincipal,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: labelCtrl,
                    enabled: !guardando,
                    maxLength: 28,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: 'Reservas por WhatsApp',
                      counterText: '',
                      hintStyle: GoogleFonts.baloo2(
                        color: ColoresMiLocalPerfil.textoSecundario,
                        fontSize: 14,
                      ),
                      filled: true,
                      fillColor: ColoresMiLocalPerfil.rellenoInput,
                      enabledBorder: inputBorder,
                      focusedBorder: inputBorder,
                      border: inputBorder,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    style: GoogleFonts.baloo2(
                      color: ColoresMiLocalPerfil.textoPrincipal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Número de WhatsApp',
                    style: GoogleFonts.baloo2(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: ColoresMiLocalPerfil.textoPrincipal,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: telefonoCtrl,
                    enabled: !guardando,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      hintText: '+54 9 351 123 4567',
                      hintStyle: GoogleFonts.baloo2(
                        color: ColoresMiLocalPerfil.textoSecundario,
                        fontSize: 14,
                      ),
                      filled: true,
                      fillColor: ColoresMiLocalPerfil.rellenoInput,
                      enabledBorder: inputBorder,
                      focusedBorder: inputBorder,
                      border: inputBorder,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      suffixIcon: IconButton(
                        tooltip: 'Pegar',
                        onPressed: guardando
                            ? null
                            : () => _pegarTextoEnControlador(telefonoCtrl),
                        icon: const Icon(Icons.paste_rounded),
                        color: ColoresMiLocalPerfil.acentoVioleta,
                      ),
                    ),
                    style: GoogleFonts.baloo2(
                      color: ColoresMiLocalPerfil.textoPrincipal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      TextButton(
                        onPressed: guardando ? null : () => Navigator.pop(ctx),
                        child: Text(
                          'Cancelar',
                          style: GoogleFonts.baloo2(
                            color: ColoresMiLocalPerfil.textoSecundario,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: guardando
                              ? null
                              : () async {
                                  setSheetState(() => guardando = true);
                                  final telefonoRaw = telefonoCtrl.text.trim();
                                  final telefono = telefonoRaw.isEmpty
                                      ? null
                                      : _normalizarWhatsappOpcional(
                                          telefonoRaw,
                                        );
                                  if (telefonoRaw.isNotEmpty &&
                                      telefono == null) {
                                    if (mounted) {
                                      _mostrarError(
                                        'WhatsApp inválido. Usá un número con característica, por ejemplo 3511234567 o +5493511234567.',
                                      );
                                    }
                                    setSheetState(() => guardando = false);
                                    return;
                                  }

                                  final label =
                                      _normalizarWhatsappLabelOpcional(
                                        labelCtrl.text,
                                      );
                                  try {
                                    await ServicioEdgesEventos()
                                        .guardarPerfilLocal(
                                          perfil: {
                                            'telefono_whatsapp': telefono,
                                            'whatsapp_label': label,
                                          },
                                          modo: 'basico',
                                        );
                                    if (!mounted || !ctx.mounted) return;
                                    await _cargarPerfil();
                                    if (!mounted || !ctx.mounted) return;
                                    Navigator.pop(ctx);
                                    _mostrarExito('WhatsApp guardado');
                                  } catch (e) {
                                    if (mounted) {
                                      _mostrarError('No se pudo guardar: $e');
                                    }
                                    if (ctx.mounted) {
                                      setSheetState(() => guardando = false);
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                ColoresMiLocalPerfil.principalMarca,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(50),
                            ),
                          ),
                          child: guardando
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Guardar',
                                  style: GoogleFonts.baloo2(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String get _ubicacionTextoComputed {
    final c = (_ciudad ?? '').trim();
    final p = (_provincia ?? '').trim();
    if (c.isNotEmpty && p.isNotEmpty) return '$c, $p';
    if (c.isNotEmpty) return c;
    if (p.isNotEmpty) return p;
    return '';
  }

  void _editarRubros() {
    HapticFeedback.lightImpact();
    final seleccion = Set<String>.from(_rubros);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        var guardando = false;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                decoration: BoxDecoration(
                  color: ColoresMiLocalPerfil.superficie,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(22),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Tipo de local',
                      style: GoogleFonts.baloo2(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: ColoresMiLocalPerfil.acentoVioleta,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Elegí uno o más rubros. Así te ven los usuarios en el perfil.',
                      style: GoogleFonts.baloo2(
                        fontSize: 13,
                        color: ColoresMiLocalPerfil.textoSecundario,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final rubro in _rubrosDisponibles)
                          FilterChip(
                            label: Text(
                              rubro,
                              style: GoogleFonts.baloo2(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            selected: seleccion.contains(rubro),
                            onSelected: guardando
                                ? null
                                : (v) {
                                    setSheetState(() {
                                      if (v) {
                                        seleccion.add(rubro);
                                      } else {
                                        seleccion.remove(rubro);
                                      }
                                    });
                                  },
                            selectedColor: ColoresMiLocalPerfil.principalMarca
                                .withValues(alpha: 0.28),
                            checkmarkColor: ColoresMiLocalPerfil.textoPrincipal,
                            backgroundColor:
                                ColoresMiLocalPerfil.superficieElevada,
                            labelStyle: GoogleFonts.baloo2(
                              color: seleccion.contains(rubro)
                                  ? ColoresMiLocalPerfil.textoPrincipal
                                  : ColoresMiLocalPerfil.textoSecundario,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        TextButton(
                          onPressed: guardando
                              ? null
                              : () => Navigator.pop(ctx),
                          child: Text(
                            'Cancelar',
                            style: GoogleFonts.baloo2(
                              color: ColoresMiLocalPerfil.textoSecundario,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: guardando
                                ? null
                                : () async {
                                    setSheetState(() => guardando = true);
                                    final ok = await _actualizarCampo(
                                      'rubro',
                                      seleccion.toList(),
                                    );
                                    if (!ctx.mounted) return;
                                    if (ok) Navigator.pop(ctx);
                                    setSheetState(() => guardando = false);
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  ColoresMiLocalPerfil.principalMarca,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(50),
                              ),
                            ),
                            child: guardando
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    'Guardar',
                                    style: GoogleFonts.baloo2(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                          ),
                        ),
                      ],
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

  void _editarHorarios() {
    HapticFeedback.lightImpact();
    final seleccion = <int, List<TramoHorarioLocal>>{
      for (final e in _horarios.entries) e.key: [...e.value],
    };
    var diaActivo = DateTime.now().weekday - 1;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        var guardando = false;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final tramos = seleccion[diaActivo] ?? <TramoHorarioLocal>[];
            final cerrado = tramos.isEmpty;

            Future<void> elegirHora(int index, bool esApertura) async {
              final actual = tramos.length > index
                  ? (esApertura ? tramos[index].abre : tramos[index].cierra)
                  : (esApertura ? '09:00' : '18:00');
              final value = await _mostrarSelectorHoraCupertino(ctx, actual);
              if (value == null) return;
              setSheetState(() {
                final list = [
                  ...(seleccion[diaActivo] ?? <TramoHorarioLocal>[]),
                ];
                while (list.length <= index) {
                  list.add(
                    const TramoHorarioLocal(abre: '09:00', cierra: '18:00'),
                  );
                }
                final old = list[index];
                list[index] = esApertura
                    ? TramoHorarioLocal(abre: value, cierra: old.cierra)
                    : TramoHorarioLocal(abre: old.abre, cierra: value);
                seleccion[diaActivo] = list;
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(ctx).height * 0.86,
                ),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                decoration: const BoxDecoration(
                  color: ColoresMiLocalPerfil.superficie,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Horarios de atención',
                        style: GoogleFonts.baloo2(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: ColoresMiLocalPerfil.textoPrincipal,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Mostrale a tus clientes si estás abierto y cuándo volvés.',
                        style: GoogleFonts.baloo2(
                          fontSize: 13,
                          color: ColoresMiLocalPerfil.textoSecundario,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (var i = 0; i < 7; i++)
                            ChoiceChip(
                              selected: diaActivo == i,
                              label: Text(nombresDiasHorarios[i]),
                              onSelected: (_) =>
                                  setSheetState(() => diaActivo = i),
                              selectedColor:
                                  ColoresMiLocalPerfil.principalMarca,
                              backgroundColor:
                                  ColoresMiLocalPerfil.rellenoInput,
                              labelStyle: GoogleFonts.baloo2(
                                color: diaActivo == i
                                    ? Colors.white
                                    : ColoresMiLocalPerfil.textoSecundario,
                                fontWeight: FontWeight.w800,
                              ),
                              shape: StadiumBorder(
                                side: BorderSide(
                                  color: diaActivo == i
                                      ? ColoresMiLocalPerfil.principalMarca
                                      : Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile.adaptive(
                        value: cerrado,
                        onChanged: guardando
                            ? null
                            : (v) => setSheetState(() {
                                if (v) {
                                  seleccion[diaActivo] = [];
                                } else {
                                  seleccion[diaActivo] = [
                                    const TramoHorarioLocal(
                                      abre: '09:00',
                                      cierra: '18:00',
                                    ),
                                  ];
                                }
                              }),
                        activeThumbColor: ColoresMiLocalPerfil.principalMarca,
                        activeTrackColor: ColoresMiLocalPerfil.principalMarca
                            .withValues(alpha: 0.28),
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Cerrado este día',
                          style: GoogleFonts.baloo2(
                            color: ColoresMiLocalPerfil.textoPrincipal,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (!cerrado) ...[
                        for (var i = 0; i < tramos.length; i++) ...[
                          _FilaTramoHorario(
                            tramo: tramos[i],
                            onTapAbre: guardando
                                ? null
                                : () => elegirHora(i, true),
                            onTapCierra: guardando
                                ? null
                                : () => elegirHora(i, false),
                            onEliminar: guardando || tramos.length <= 1
                                ? null
                                : () => setSheetState(() {
                                    final list = [...tramos]..removeAt(i);
                                    seleccion[diaActivo] = list;
                                  }),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (tramos.length < 3)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: guardando
                                  ? null
                                  : () => setSheetState(() {
                                      final list = [
                                        ...tramos,
                                        const TramoHorarioLocal(
                                          abre: '19:00',
                                          cierra: '23:00',
                                        ),
                                      ];
                                      seleccion[diaActivo] = list;
                                    }),
                              icon: const Icon(CupertinoIcons.plus_circle),
                              label: const Text('Agregar otra jornada'),
                              style: TextButton.styleFrom(
                                foregroundColor:
                                    ColoresMiLocalPerfil.principalMarca,
                                textStyle: GoogleFonts.baloo2(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                      ],
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: guardando
                                ? null
                                : () => setSheetState(() {
                                    for (var d = 0; d <= 4; d++) {
                                      seleccion[d] = [
                                        ...(seleccion[diaActivo] ??
                                            const <TramoHorarioLocal>[]),
                                      ];
                                    }
                                  }),
                            child: const Text('Copiar a lun-vie'),
                          ),
                          OutlinedButton(
                            onPressed: guardando
                                ? null
                                : () => setSheetState(() {
                                    for (var d = 0; d < 7; d++) {
                                      seleccion[d] = [
                                        ...(seleccion[diaActivo] ??
                                            const <TramoHorarioLocal>[]),
                                      ];
                                    }
                                  }),
                            child: const Text('Copiar a todos'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          TextButton(
                            onPressed: guardando
                                ? null
                                : () => Navigator.pop(ctx),
                            child: Text(
                              'Cancelar',
                              style: GoogleFonts.baloo2(
                                color: ColoresMiLocalPerfil.textoSecundario,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: guardando
                                  ? null
                                  : () async {
                                      setSheetState(() => guardando = true);
                                      final ok = await _actualizarCampo(
                                        'horarios_json',
                                        horariosLocalToJson(seleccion),
                                      );
                                      if (!ctx.mounted) return;
                                      if (ok) {
                                        Navigator.pop(ctx);
                                      } else {
                                        setSheetState(() => guardando = false);
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    ColoresMiLocalPerfil.principalMarca,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                              ),
                              child: guardando
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      'Guardar horarios',
                                      style: GoogleFonts.baloo2(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _mostrarSelectorHoraCupertino(
    BuildContext context,
    String horaInicial,
  ) async {
    final parts = horaInicial.split(':');
    var hora = (int.tryParse(parts.first) ?? 9).clamp(0, 23);
    var minuto =
        ((parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0) ~/ 5).clamp(
          0,
          11,
        ) *
        5;
    final horaCtrl = FixedExtentScrollController(initialItem: hora);
    final minutoCtrl = FixedExtentScrollController(initialItem: minuto ~/ 5);

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: 310,
          decoration: const BoxDecoration(
            color: ColoresMiLocalPerfil.superficie,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        'Cancelar',
                        style: GoogleFonts.baloo2(
                          color: ColoresMiLocalPerfil.textoSecundario,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Elegí horario',
                      style: GoogleFonts.baloo2(
                        color: ColoresMiLocalPerfil.textoPrincipal,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(
                        ctx,
                        '${hora.toString().padLeft(2, '0')}:${minuto.toString().padLeft(2, '0')}',
                      ),
                      child: Text(
                        'OK',
                        style: GoogleFonts.baloo2(
                          color: ColoresMiLocalPerfil.principalMarca,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 92,
                      child: CupertinoPicker(
                        scrollController: horaCtrl,
                        itemExtent: 42,
                        magnification: 1.12,
                        squeeze: 1.08,
                        useMagnifier: true,
                        selectionOverlay: _OverlayPickerHora(),
                        onSelectedItemChanged: (v) => hora = v,
                        children: [
                          for (var i = 0; i < 24; i++)
                            Center(
                              child: Text(
                                i.toString().padLeft(2, '0'),
                                style: GoogleFonts.baloo2(
                                  color: ColoresMiLocalPerfil.textoPrincipal,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      ':',
                      style: GoogleFonts.baloo2(
                        color: ColoresMiLocalPerfil.textoPrincipal,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(
                      width: 92,
                      child: CupertinoPicker(
                        scrollController: minutoCtrl,
                        itemExtent: 42,
                        magnification: 1.12,
                        squeeze: 1.08,
                        useMagnifier: true,
                        selectionOverlay: _OverlayPickerHora(),
                        onSelectedItemChanged: (v) => minuto = v * 5,
                        children: [
                          for (var i = 0; i < 12; i++)
                            Center(
                              child: Text(
                                (i * 5).toString().padLeft(2, '0'),
                                style: GoogleFonts.baloo2(
                                  color: ColoresMiLocalPerfil.textoPrincipal,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Text(
                  'Formato 24 hs',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.baloo2(
                    color: ColoresMiLocalPerfil.textoSecundario,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _editarDireccion() {
    HapticFeedback.lightImpact();
    _showEditSheet(
      titulo: 'Editar dirección',
      valorActual: _direccion ?? '',
      hint: 'Dirección del local',
      campoDb: 'direccion',
    );
  }

  void _showVisorFotos(int initialIndex) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: PageController(initialPage: initialIndex.clamp(0, 4)),
              itemCount: _maxFotosLocales,
              itemBuilder: (context, index) {
                final url = _fotosLocal[index];
                final urlBust = _urlConCacheBust(url, _versionFotosLocal);
                return InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4,
                  child: urlBust.isNotEmpty
                      ? Image.network(
                          urlBust,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => _placeholderVisor(),
                        )
                      : _placeholderVisor(),
                );
              },
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 16,
              child: IconButton(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: Icon(
                  Icons.close,
                  color: ColoresLocales.textoEnBoton,
                  size: 28,
                ),
                style: IconButton.styleFrom(backgroundColor: Colors.black45),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholderVisor() => Container(
    color: ColoresLocales.fondoSuperficie,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.photo,
            size: 64,
            color: ColoresLocales.textoSecundario,
          ),
          SizedBox(height: 12),
          Text(
            'Sin foto',
            style: GoogleFonts.baloo2(
              fontSize: 16,
              color: ColoresLocales.textoSecundario,
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _irASuscripciones() async {
    await NavegacionLocales.irASuscripciones();
    if (mounted) await _cargarPerfil();
  }

  String _tipoPlanBanner() {
    final estado = _estadoSuscripcion;
    if (estado == null) {
      return (!_localVerificado) ? 'Gratuita' : 'Standard';
    }
    return estado.tipoPlan;
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return Scaffold(
        backgroundColor: ColoresMiLocalPerfil.fondo,
        body: Center(
          child: CircularProgressIndicator(
            color: ColoresMiLocalPerfil.acentoVioleta,
          ),
        ),
      );
    }

    final size = MediaQuery.of(context).size;
    final screenHeight = size.height;
    final screenWidth = size.width;
    final padding = MediaQuery.of(context).padding;
    // ~15% más alto que el hero base (0.43) para evitar scroll interno en iPhone.
    final bannerHeight = (screenHeight * 0.4945).clamp(368.0, 529.0);
    final isNarrow = screenWidth < 400;
    final avatarSize = isNarrow ? 72.0 : 100.0;
    final horizontalPadding = isNarrow ? 16.0 : 24.0;
    const carouselAlto = 280.0;
    final nombre = _nombreLocal?.trim().isEmpty != false
        ? 'Mi local'
        : _nombreLocal!.trim();
    final tipoPlanBanner = _tipoPlanBanner();
    final esPionero = _estadoSuscripcion?.esPionero ?? false;
    final ubiOk =
        _ubicacionTextoComputed.isNotEmpty ||
        (_direccion ?? '').trim().isNotEmpty ||
        (_urlMaps ?? '').trim().isNotEmpty;
    final igOk = _urlInstagram?.trim().isNotEmpty == true;
    final ttOk = _urlTiktok?.trim().isNotEmpty == true;
    final webOk = _urlWebsite?.trim().isNotEmpty == true;
    final szSocial = isNarrow ? 24.0 : 28.0;
    final sepSocial = SizedBox(width: isNarrow ? 20 : 25);

    return Scaffold(
      backgroundColor: ColoresMiLocalPerfil.fondo,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: ColoresMiLocalPerfil.decoracionFondo,
            ),
          ),
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: bannerHeight,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.0, 0.55, 0.85, 1.0],
                            colors: [
                              Colors.white,
                              Colors.white.withValues(alpha: 0.65),
                              Colors.white.withValues(alpha: 0.15),
                              Colors.transparent,
                            ],
                          ).createShader(bounds),
                          blendMode: BlendMode.dstIn,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (_urlBanner != null && _urlBanner!.isNotEmpty)
                                Image.network(
                                  _urlConCacheBust(_urlBanner, _versionBanner),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _placeholderBanner(),
                                )
                              else if (_fotoPerfilUrl != null &&
                                  _fotoPerfilUrl!.isNotEmpty)
                                Image.network(
                                  _urlConCacheBust(
                                    _fotoPerfilUrl,
                                    _versionAvatar,
                                  ),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _placeholderBanner(),
                                )
                              else
                                _placeholderBanner(),
                              Container(
                                color: Colors.black.withValues(alpha: 0.45),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            padding.top + 14,
                            horizontalPadding,
                            8,
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: () => _elegirImagen(
                                    bucket: 'avatars_locales',
                                    pathSuffix: 'foto_perfil',
                                    campoDb: 'foto_perfil_url',
                                    minWidth: 900,
                                    onSuccess: () => setState(() {}),
                                  ),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Container(
                                        width: avatarSize,
                                        height: avatarSize,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: esPionero
                                                ? ProgramaPioneros.dorado
                                                : ColoresMiLocalPerfil
                                                      .principalMarca
                                                      .withValues(alpha: 0.8),
                                            width: 3,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.4,
                                              ),
                                              blurRadius: 12,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: ClipOval(
                                          child:
                                              _fotoPerfilUrl != null &&
                                                  _fotoPerfilUrl!.isNotEmpty
                                              ? Image.network(
                                                  _urlConCacheBust(
                                                    _fotoPerfilUrl,
                                                    _versionAvatar,
                                                  ),
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      _avatarPlaceholder(
                                                        avatarSize,
                                                      ),
                                                )
                                              : _avatarPlaceholder(avatarSize),
                                        ),
                                      ),
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: _BotonLapizMini(
                                          onTap: () => _elegirImagen(
                                            bucket: 'avatars_locales',
                                            pathSuffix: 'foto_perfil',
                                            campoDb: 'foto_perfil_url',
                                            minWidth: 900,
                                            onSuccess: () => setState(() {}),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 11),
                                _NombreLocalHero(
                                  nombre: nombre,
                                  maxWidth: screenWidth - horizontalPadding * 2,
                                  fontSize: isNarrow ? 21 : 26,
                                  lapizSize: isNarrow ? 12 : 14,
                                  onEditarNombre: () => _showEditSheet(
                                    titulo: 'Editar nombre del local',
                                    valorActual: _nombreLocal ?? '',
                                    hint: 'Nombre del local',
                                    campoDb: 'nombre_local',
                                    maxLength: LimitesMiLocalPerfil
                                        .maxCaracteresNombre,
                                  ),
                                  insignia: esPionero
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: ProgramaPioneros.dorado
                                                .withValues(alpha: 0.16),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                CupertinoIcons
                                                    .checkmark_seal_fill,
                                                size: isNarrow ? 14 : 16,
                                                color: ProgramaPioneros.dorado,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Pionero',
                                                style: GoogleFonts.baloo2(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w800,
                                                  color:
                                                      ProgramaPioneros.dorado,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : (_localVerificado &&
                                            tipoPlanBanner != 'Gratuita')
                                      ? Icon(
                                          CupertinoIcons.checkmark_seal_fill,
                                          size: isNarrow ? 20 : 24,
                                          color: ColoresMiLocalPerfil
                                              .principalMarca,
                                        )
                                      : null,
                                  espacioInsignia: isNarrow ? 4 : 6,
                                  esInsigniaPionero: esPionero,
                                ),
                                const SizedBox(height: 7),
                                _ResenasHeroEstiloUsuarios(
                                  calificacion: _calificacion,
                                  cantidad: _calificacionCantidad,
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const LocalesCalificaciones(),
                                      ),
                                    );
                                  },
                                ),
                                SizedBox(height: isNarrow ? 13 : 16),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isNarrow ? 4 : 8,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _IconoEnlaceEditable(
                                        icon: CupertinoIcons.location_solid,
                                        size: szSocial,
                                        activo: ubiOk,
                                        onTap: () => _showEditSheet(
                                          titulo: 'URL de Google Maps',
                                          valorActual: _urlMaps ?? '',
                                          hint:
                                              'Pegá la URL de Google Maps aquí',
                                          campoDb: 'url_maps',
                                        ),
                                      ),
                                      sepSocial,
                                      _IconoEnlaceEditable(
                                        icon: FontAwesomeIcons.instagram,
                                        useFontAwesome: true,
                                        size: szSocial,
                                        activo: igOk,
                                        onTap: () => _showEditSheet(
                                          titulo: 'URL de Instagram',
                                          valorActual: _urlInstagram ?? '',
                                          hint: 'Pegá tu URL de Instagram aquí',
                                          campoDb: 'url_instagram',
                                        ),
                                      ),
                                      sepSocial,
                                      _IconoEnlaceEditable(
                                        icon: FontAwesomeIcons.tiktok,
                                        useFontAwesome: true,
                                        size: szSocial,
                                        activo: ttOk,
                                        onTap: () => _showEditSheet(
                                          titulo: 'URL de TikTok',
                                          valorActual: _urlTiktok ?? '',
                                          hint: 'Pegá tu URL de TikTok aquí',
                                          campoDb: 'url_tiktok',
                                        ),
                                      ),
                                      sepSocial,
                                      _IconoEnlaceEditable(
                                        icon: CupertinoIcons.globe,
                                        size: szSocial,
                                        activo: webOk,
                                        onTap: () => _showEditSheet(
                                          titulo: 'Sitio web',
                                          valorActual: _urlWebsite ?? '',
                                          hint: 'Pegá la URL de tu web aquí',
                                          campoDb: 'url_website',
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
                      Positioned(
                        left: 14,
                        top: padding.top + 10,
                        child: _AccionEditarBanner(onTap: _editarBanner),
                      ),
                      Positioned(
                        top: padding.top + 10,
                        right: 14,
                        child: GestureDetector(
                          onTap: _irASuscripciones,
                          child: BadgePlanSuscripcion(
                            tipoPlan: tipoPlanBanner,
                            etiquetaLarga: tipoPlanBanner == 'Gratuita',
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: BadgeMegustaLocalLectura(
                            cantidad: _cantidadMegusta,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    6,
                    horizontalPadding,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () =>
                            setState(() => _infoExpandida = !_infoExpandida),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              'Info del lugar',
                              style: GoogleFonts.baloo2(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: ColoresMiLocalPerfil.principalMarca,
                              ),
                            ),
                            const SizedBox(width: 6),
                            AnimatedRotation(
                              turns: _infoExpandida ? 0.5 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(
                                CupertinoIcons.chevron_down,
                                size: 20,
                                color: ColoresMiLocalPerfil.principalMarca,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AnimatedCrossFade(
                        firstChild: const SizedBox.shrink(),
                        secondChild: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: _editarDescripcion,
                                      behavior: HitTestBehavior.opaque,
                                      child: Text(
                                        _descripcion?.trim().isNotEmpty == true
                                            ? _descripcion!
                                            : 'El local todavía no escribió una descripción.',
                                        style: GoogleFonts.baloo2(
                                          fontSize: 14,
                                          height: 1.4,
                                          fontStyle:
                                              _descripcion?.trim().isNotEmpty ==
                                                  true
                                              ? FontStyle.normal
                                              : FontStyle.italic,
                                          color:
                                              _descripcion?.trim().isNotEmpty ==
                                                  true
                                              ? ColoresMiLocalPerfil
                                                    .textoPrincipal
                                                    .withValues(alpha: 0.95)
                                              : ColoresMiLocalPerfil
                                                    .textoSecundario,
                                        ),
                                      ),
                                    ),
                                  ),
                                  _BotonLapizMini(
                                    onTap: _editarDescripcion,
                                    size: 13,
                                    sobreOscuro: false,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 9),
                              _BotonWhatsappEditableLocal(
                                tieneWhatsapp: (_telefonoWhatsapp ?? '')
                                    .trim()
                                    .isNotEmpty,
                                label: _labelWhatsappVisible(_whatsappLabel),
                                onTap: _editarWhatsapp,
                              ),
                              if (_ubicacionTextoComputed.isNotEmpty ||
                                  (_direccion ?? '').trim().isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      CupertinoIcons.location_solid,
                                      size: 14,
                                      color:
                                          ColoresMiLocalPerfil.principalMarca,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: _editarDireccion,
                                        behavior: HitTestBehavior.opaque,
                                        child: Text(
                                          [
                                            if ((_direccion ?? '')
                                                .trim()
                                                .isNotEmpty)
                                              _direccion!.trim(),
                                            if (_ubicacionTextoComputed
                                                .isNotEmpty)
                                              _ubicacionTextoComputed,
                                          ].join(' · '),
                                          style: GoogleFonts.baloo2(
                                            fontSize: 13,
                                            color: ColoresMiLocalPerfil
                                                .textoSecundario,
                                          ),
                                        ),
                                      ),
                                    ),
                                    _BotonLapizMini(
                                      onTap: _editarDireccion,
                                      size: 13,
                                      sobreOscuro: false,
                                    ),
                                  ],
                                ),
                              ] else ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: _editarDireccion,
                                        child: Text(
                                          'Agregar dirección',
                                          style: GoogleFonts.baloo2(
                                            fontSize: 13,
                                            fontStyle: FontStyle.italic,
                                            color: ColoresMiLocalPerfil
                                                .textoSecundario,
                                          ),
                                        ),
                                      ),
                                    ),
                                    _BotonLapizMini(
                                      onTap: _editarDireccion,
                                      size: 13,
                                      sobreOscuro: false,
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: _editarRubros,
                                      child: Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          if (_rubros.isEmpty)
                                            Text(
                                              'Agregá rubros para que te encuentren mejor',
                                              style: GoogleFonts.baloo2(
                                                fontSize: 12,
                                                fontStyle: FontStyle.italic,
                                                color: ColoresMiLocalPerfil
                                                    .textoSecundario,
                                              ),
                                            )
                                          else
                                            for (final r in _rubros)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 9,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: ColoresMiLocalPerfil
                                                      .principalMarca
                                                      .withValues(alpha: 0.12),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: ColoresMiLocalPerfil
                                                        .principalMarca
                                                        .withValues(
                                                          alpha: 0.35,
                                                        ),
                                                  ),
                                                ),
                                                child: Text(
                                                  r,
                                                  style: GoogleFonts.baloo2(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: ColoresMiLocalPerfil
                                                        .principalMarca,
                                                  ),
                                                ),
                                              ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  _BotonLapizMini(
                                    onTap: _editarRubros,
                                    size: 13,
                                    sobreOscuro: false,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _BotonEditarHorariosLocal(
                                estado: estadoHorarioLocal(_horarios),
                                onTap: _editarHorarios,
                              ),
                              const SizedBox(height: 9),
                              _BotonCartaEditableLocal(
                                cantidadItems: _cantidadItemsCarta,
                                onTap: _abrirAsistenteCarta,
                              ),
                              if (_cantidadItemsCarta > 0) ...[
                                const SizedBox(height: 7),
                                _BotonVerMiCartaLocal(
                                  cantidadItems: _cantidadItemsCarta,
                                  onTap: _verMiCarta,
                                ),
                              ],
                            ],
                          ),
                        ),
                        crossFadeState: _infoExpandida
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        duration: const Duration(milliseconds: 220),
                      ),
                    ],
                  ),
                ),
              ),
              // Fotos del lugar
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        16,
                        horizontalPadding,
                        10,
                      ),
                      child: Text(
                        'Fotos del lugar',
                        style: GoogleFonts.baloo2(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: ColoresMiLocalPerfil.textoPrincipal,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: carouselAlto,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                        ),
                        itemCount: _maxFotosLocales,
                        itemBuilder: (context, index) {
                          final url = _fotosLocal[index];
                          final urlBust = _urlConCacheBust(
                            url,
                            _versionFotosLocal,
                          );
                          return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: _FotoLocalCarouselItem(
                              urlBust: urlBust,
                              altoFijo: carouselAlto,
                              onVer: () => _showVisorFotos(index),
                              onEditar: () => _elegirImagen(
                                bucket: 'fotos_locales',
                                pathSuffix: 'foto_local_${index + 1}',
                                campoDb: 'foto_local_${index + 1}',
                                minWidth: 1400,
                                onSuccess: () => setState(() {}),
                              ),
                              placeholder: () => _fotoPlaceholder(130),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              // Resumen de suscripción
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    28,
                    horizontalPadding,
                    0,
                  ),
                  child: _ResumenSuscripcionPerfil(
                    estado: _estadoSuscripcion,
                    localVerificado: _localVerificado,
                    onAdministrar: _irASuscripciones,
                  ),
                ),
              ),
              // Ayuda y soporte
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    14,
                    horizontalPadding,
                    0,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.pushNamed(context, '/soporte');
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        decoration: ColoresLocales.decoracionCardOscuraMiLocal(
                          radius: 16,
                          sinBorde: true,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              CupertinoIcons.question_circle,
                              color: ColoresMiLocalPerfil.principalMarca,
                              size: 24,
                            ),
                            SizedBox(width: 14),
                            Text(
                              'Ayuda y soporte',
                              style: GoogleFonts.baloo2(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: ColoresMiLocalPerfil.textoPrincipal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Zona de peligro: contraseña → eliminar (pequeño) → cerrar sesión (principal)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    28,
                    horizontalPadding,
                    0,
                  ),
                  child: _ZonaPeligroPerfil(
                    onCambiarContrasena: () =>
                        Navigator.pushNamed(context, '/cambiar_contrasena'),
                    onEliminarCuenta: _eliminarCuenta,
                    onCerrarSesion: _salirCuentaActual,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.of(context).padding.bottom + 24,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _placeholderBanner() => Container(
    color: ColoresMiLocalPerfil.fondoSuperficie,
    child: Icon(
      CupertinoIcons.photo,
      size: 64,
      color: ColoresMiLocalPerfil.textoSecundario,
    ),
  );

  Widget _avatarPlaceholder(double size) =>
      IconoLocal(size: size * 0.5, color: ColoresMiLocalPerfil.textoSecundario);

  Widget _fotoPlaceholder(double w) => Container(
    width: w,
    color: ColoresMiLocalPerfil.fondoSuperficie,
    child: Icon(
      CupertinoIcons.camera_fill,
      size: 36,
      color: ColoresMiLocalPerfil.acentoVioleta.withValues(alpha: 0.55),
    ),
  );
}

/// Reseñas en el hero — mismo formato que app usuarios (número grande + estrellas).
class _ResenasHeroEstiloUsuarios extends StatelessWidget {
  final double? calificacion;
  final int cantidad;
  final VoidCallback onTap;

  const _ResenasHeroEstiloUsuarios({
    required this.calificacion,
    required this.cantidad,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: calificacion == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _EstrellasRatingPerfil(valor: null, size: 16),
                  const SizedBox(height: 5),
                  Text(
                    'Sin calificaciones aún',
                    style: GoogleFonts.baloo2(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: ColoresMiLocalPerfil.textoSecundario,
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    calificacion!.toStringAsFixed(1),
                    style: GoogleFonts.baloo2(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      height: 0.95,
                      letterSpacing: -0.5,
                      color: ColoresMiLocalPerfil.textoPrincipal,
                    ),
                  ),
                  _EstrellasRatingPerfil(valor: calificacion, size: 15),
                  const SizedBox(height: 4),
                  Text(
                    '$cantidad ${cantidad == 1 ? 'calificación' : 'calificaciones'}',
                    style: GoogleFonts.baloo2(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: ColoresMiLocalPerfil.textoSecundario,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _EstrellasRatingPerfil extends StatelessWidget {
  final double? valor;
  final double size;

  const _EstrellasRatingPerfil({required this.valor, this.size = 15});

  @override
  Widget build(BuildContext context) {
    const dorado = Color(0xFFFFC107);
    final apagado = ColoresMiLocalPerfil.textoSecundario.withValues(
      alpha: 0.45,
    );
    final v = valor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final pos = i + 1;
        late IconData icono;
        late Color color;
        if (v == null || v < pos - 0.5) {
          icono = CupertinoIcons.star;
          color = apagado;
        } else if (v >= pos) {
          icono = CupertinoIcons.star_fill;
          color = dorado;
        } else {
          icono = CupertinoIcons.star_lefthalf_fill;
          color = dorado;
        }
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: size * 0.07),
          child: Icon(icono, size: size, color: color),
        );
      }),
    );
  }
}

/// Pill «Editar banner» sobre la imagen de portada.
class _AccionEditarBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _AccionEditarBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.pencil,
                  size: 12,
                  color: Colors.white,
                ),
                const SizedBox(width: 5),
                Text(
                  'Editar banner',
                  style: GoogleFonts.baloo2(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
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

/// Lápiz sobre fotos del carrusel — contenedor blanco + sombra negra.
class _LapizEnFoto extends StatelessWidget {
  final VoidCallback onTap;

  const _LapizEnFoto({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.38),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          CupertinoIcons.pencil,
          size: 15,
          color: ColoresLocales.acentoVioletaMarca,
        ),
      ),
    );
  }
}

/// Nombre multilínea centrado; lápiz e insignia inline tras el último carácter.
class _NombreLocalHero extends StatelessWidget {
  const _NombreLocalHero({
    required this.nombre,
    required this.maxWidth,
    required this.fontSize,
    required this.lapizSize,
    required this.onEditarNombre,
    this.insignia,
    this.esInsigniaPionero = false,
    this.espacioInsignia = 5,
  });

  final String nombre;
  final double maxWidth;
  final double fontSize;
  final double lapizSize;
  final VoidCallback onEditarNombre;
  final Widget? insignia;
  final bool esInsigniaPionero;
  final double espacioInsignia;

  @override
  Widget build(BuildContext context) {
    final textStyle = GoogleFonts.baloo2(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      color: ColoresMiLocalPerfil.textoPrincipal,
      height: 1.2,
    );
    final textDirection = Directionality.of(context);
    final reservaTrailing = FormatoNombreLocalHero.reservaTrailing(
      tieneInsignia: insignia != null,
      esInsigniaPionero: esInsigniaPionero,
      fontSize: fontSize,
    );
    final nombreMostrado = FormatoNombreLocalHero.paraDisplay(
      nombre: nombre,
      maxWidth: maxWidth,
      textStyle: textStyle,
      textDirection: textDirection,
      reservaTrailing: reservaTrailing,
    );

    final trailing = <InlineSpan>[
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.only(left: 2),
          child: _BotonLapizMini(onTap: onEditarNombre, size: lapizSize),
        ),
      ),
      if (insignia != null)
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: EdgeInsets.only(left: espacioInsignia),
            child: insignia!,
          ),
        ),
    ];

    return SizedBox(
      width: maxWidth,
      child: GestureDetector(
        onTap: onEditarNombre,
        behavior: HitTestBehavior.deferToChild,
        child: Text.rich(
          TextSpan(
            style: textStyle,
            children: [
              TextSpan(text: nombreMostrado),
              ...trailing,
            ],
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Lápiz solo (sin contenedor) — legible sobre banner oscuro o fondo claro.
class _BotonLapizMini extends StatelessWidget {
  final VoidCallback onTap;
  final double size;
  final bool sobreOscuro;

  const _BotonLapizMini({
    required this.onTap,
    this.size = 14,
    this.sobreOscuro = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = sobreOscuro
        ? Colors.white
        : ColoresMiLocalPerfil.principalMarca;
    final shadows = sobreOscuro
        ? [
            Shadow(
              color: Colors.black.withValues(alpha: 0.9),
              blurRadius: 8,
              offset: const Offset(0, 1),
            ),
            Shadow(
              color: ColoresLocales.acentoVioleta.withValues(alpha: 0.65),
              blurRadius: 10,
            ),
          ]
        : [
            Shadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ];

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          CupertinoIcons.pencil,
          size: size,
          color: color,
          shadows: shadows,
        ),
      ),
    );
  }
}

/// Icono con glow (como app usuarios) + lápiz mini para editar enlace.
class _IconoEnlaceEditable extends StatefulWidget {
  final IconData icon;
  final bool useFontAwesome;
  final VoidCallback onTap;
  final double size;
  final bool activo;

  const _IconoEnlaceEditable({
    required this.icon,
    required this.onTap,
    this.useFontAwesome = false,
    this.size = 28,
    this.activo = true,
  });

  @override
  State<_IconoEnlaceEditable> createState() => _IconoEnlaceEditableState();
}

class _IconoEnlaceEditableState extends State<_IconoEnlaceEditable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final icono = widget.useFontAwesome
        ? FaIcon(widget.icon, size: widget.size, color: Colors.white)
        : Icon(widget.icon, size: widget.size, color: Colors.white);

    final contenido = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.activo ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: widget.activo
          ? () => setState(() => _pressed = false)
          : null,
      onTapUp: widget.activo ? (_) => setState(() => _pressed = false) : null,
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: widget.activo && _pressed ? 0.88 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: widget.activo
                ? [
                    BoxShadow(
                      color: ColoresMiLocalPerfil.principalMarca.withValues(
                        alpha: _pressed ? 0.65 : 0.45,
                      ),
                      blurRadius: _pressed ? 16 : 12,
                      spreadRadius: _pressed ? 1.5 : 0.8,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Opacity(opacity: widget.activo ? 1 : 0.25, child: icono),
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        contenido,
        Positioned(
          right: -2,
          bottom: -6,
          child: _BotonLapizMini(onTap: widget.onTap, size: 11),
        ),
      ],
    );
  }
}

/// Carrusel: alto fijo, ancho según aspect ratio de cada foto.
class _FotoLocalCarouselItem extends StatefulWidget {
  final String urlBust;
  final double altoFijo;
  final VoidCallback onVer;
  final VoidCallback onEditar;
  final Widget Function() placeholder;

  const _FotoLocalCarouselItem({
    required this.urlBust,
    required this.altoFijo,
    required this.onVer,
    required this.onEditar,
    required this.placeholder,
  });

  @override
  State<_FotoLocalCarouselItem> createState() => _FotoLocalCarouselItemState();
}

class _FotoLocalCarouselItemState extends State<_FotoLocalCarouselItem> {
  double _aspect = 1.0;

  @override
  void initState() {
    super.initState();
    _resolverAspecto();
  }

  @override
  void didUpdateWidget(covariant _FotoLocalCarouselItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urlBust != widget.urlBust) _resolverAspecto();
  }

  Future<void> _resolverAspecto() async {
    if (widget.urlBust.isEmpty) {
      if (mounted) setState(() => _aspect = 1.0);
      return;
    }
    try {
      final provider = NetworkImage(widget.urlBust);
      final stream = provider.resolve(const ImageConfiguration());
      final completer = Completer<void>();
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          final w = info.image.width.toDouble();
          final h = info.image.height.toDouble();
          if (mounted && h > 0) {
            setState(() => _aspect = (w / h).clamp(0.52, 1.25));
          }
          stream.removeListener(listener);
          if (!completer.isCompleted) completer.complete();
        },
        onError: (_, __) {
          stream.removeListener(listener);
          if (!completer.isCompleted) completer.complete();
        },
      );
      stream.addListener(listener);
      await completer.future.timeout(
        const Duration(seconds: 6),
        onTimeout: () {},
      );
    } catch (_) {}
  }

  double get _ancho => (widget.altoFijo * _aspect).clamp(108.0, 200.0);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _ancho,
      height: widget.altoFijo,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: widget.onVer,
            child: Container(
              width: _ancho,
              height: widget.altoFijo,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: widget.urlBust.isNotEmpty
                    ? Image.network(
                        widget.urlBust,
                        width: _ancho,
                        height: widget.altoFijo,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => widget.placeholder(),
                      )
                    : widget.placeholder(),
              ),
            ),
          ),
          Positioned(
            right: 6,
            bottom: 6,
            child: _LapizEnFoto(onTap: widget.onEditar),
          ),
        ],
      ),
    );
  }
}

class _ResumenSuscripcionPerfil extends StatelessWidget {
  final EstadoSuscripcionLocal? estado;
  final bool localVerificado;
  final Future<void> Function() onAdministrar;

  const _ResumenSuscripcionPerfil({
    required this.estado,
    required this.localVerificado,
    required this.onAdministrar,
  });

  Color _colorPlan(String plan) => colorPlanSuscripcionUi(plan);

  @override
  Widget build(BuildContext context) {
    final e = estado;
    final esPionero = e?.esPionero ?? false;
    final plan =
        e?.tipoPlan ??
        SuscripcionLocales.tipoPlanPago(
          rawDb: null,
          localVerificado: localVerificado || esPionero,
        );
    final colorPlan = _colorPlan(plan);
    final esGratis = !localVerificado && !esPionero;

    if (esPionero && e != null) {
      return _buildCardPionero(context, e, colorPlan, esGratis);
    }

    final planUi = e != null
        ? etiquetaSuscripcionCorta(e.tipoPlan)
        : SuscripcionLocales.etiquetaPlanUi(
            rawDb: null,
            localVerificado: localVerificado,
          );

    final lineas = <_LineaResumenPerfil>[];
    if (localVerificado) {
      lineas.add(
        const _LineaResumenPerfil(
          icono: CupertinoIcons.checkmark_seal_fill,
          color: Color(0xFF059669),
          texto: 'Perfil verificado',
        ),
      );
    } else {
      lineas.add(
        _LineaResumenPerfil(
          icono: CupertinoIcons.person_crop_circle,
          color: ColoresMiLocalPerfil.textoSecundario,
          texto: 'Sin verificación',
        ),
      );
    }

    if (e?.planActivo == true && e?.fechaVencimiento != null) {
      final dias = e!.diasHastaVencimiento;
      final vence = SuscripcionLocales.formatearFecha(e.fechaVencimiento!);
      lineas.add(
        _LineaResumenPerfil(
          icono: CupertinoIcons.calendar,
          color: (dias != null && dias <= 7)
              ? ColoresMiLocalPerfil.acentoVioleta
              : ColoresMiLocalPerfil.principalMarca,
          texto: dias != null && dias <= 1
              ? (dias == 0 ? 'Vence hoy · $vence' : 'Vence mañana · $vence')
              : 'Vence el $vence',
        ),
      );
    } else if (e?.fechaVencimiento != null && localVerificado) {
      lineas.add(
        _LineaResumenPerfil(
          icono: CupertinoIcons.exclamationmark_circle,
          color: const Color(0xFFDC2626),
          texto:
              'Plan vencido · ${SuscripcionLocales.formatearFecha(e!.fechaVencimiento!)}',
        ),
      );
    } else if (esGratis) {
      lineas.add(
        _LineaResumenPerfil(
          icono: CupertinoIcons.sparkles,
          color: ColoresMiLocalPerfil.acentoVioleta,
          texto: 'Sin créditos premium activos',
        ),
      );
    }

    if (e?.tienePagoPendiente == true) {
      final p = e!.pagoPendiente!;
      lineas.add(
        _LineaResumenPerfil(
          icono: CupertinoIcons.hourglass,
          color: const Color(0xFFD97706),
          texto:
              'Pago en revisión · ${p.planSolicitado ?? ''} (${SuscripcionLocales.etiquetaTipoSolicitud(p.tipoSolicitud)})',
        ),
      );
    } else if (e?.tienePagoAgendado == true) {
      final p = e!.pagoAgendado!;
      final fecha = p.aplicaDesde != null
          ? SuscripcionLocales.formatearFechaCorta(p.aplicaDesde!)
          : 'al vencer';
      lineas.add(
        _LineaResumenPerfil(
          icono: CupertinoIcons.clock_fill,
          color: const Color(0xFF059669),
          texto: 'Renovación agendada · ${p.planSolicitado ?? ''} · $fecha',
        ),
      );
    } else if (e != null && localVerificado && e.cupos.flyersIa > 0) {
      lineas.add(
        _LineaResumenPerfil(
          icono: CupertinoIcons.sparkles,
          color: ColoresFeaturesLocales.flyersIa,
          texto:
              '${e.cupos.flyersIa} flyers IA · ${e.cupos.recomendadosFernecito} recomendados',
        ),
      );
    }

    final pendiente = e?.tienePagoPendiente == true;
    final String boton;
    final bool botonPrimario;
    if (esGratis) {
      boton = pendiente ? 'Pago en revisión' : 'Administrar suscripción';
      botonPrimario = true;
    } else if (pendiente) {
      boton = 'Ver estado del pago';
      botonPrimario = false;
    } else if (e?.planActivo == true && e!.proximoAVencer) {
      boton = 'Renovar suscripción';
      botonPrimario = true;
    } else if (e?.planActivo != true && localVerificado) {
      boton = 'Renovar suscripción';
      botonPrimario = true;
    } else {
      boton = 'Administrar suscripción';
      botonPrimario = false;
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: ColoresMiLocalPerfil.superficie,
        border: Border.all(
          color: colorPlan.withValues(alpha: 0.28),
          width: 1.4,
        ),
        boxShadow: const [],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                child: Icon(
                  CupertinoIcons.creditcard_fill,
                  color: colorPlan,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mi suscripción',
                      style: GoogleFonts.baloo2(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: ColoresMiLocalPerfil.textoSecundario,
                      ),
                    ),
                    Text(
                      planUi,
                      style: GoogleFonts.baloo2(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                        color: ColoresMiLocalPerfil.textoPrincipal,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: colorPlan.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  SuscripcionLocales.precioMesEtiqueta(
                    esGratis ? 'Standard' : plan,
                  ).replaceAll(' / mes', '/mes'),
                  style: GoogleFonts.baloo2(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: colorPlan,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...lineas
              .take(3)
              .map(
                (l) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    children: [
                      Icon(l.icono, size: 16, color: l.color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l.texto,
                          style: GoogleFonts.baloo2(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: ColoresMiLocalPerfil.textoPrincipal
                                .withValues(alpha: 0.92),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 8),
          SizedBox(
            height: 46,
            child: botonPrimario
                ? ElevatedButton(
                    onPressed: pendiente && esGratis
                        ? null
                        : () => onAdministrar(),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: esGratis
                          ? ColoresMiLocalPerfil.principalMarca
                          : ColoresMiLocalPerfil.acentoVioleta,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                    child: Text(
                      boton,
                      style: GoogleFonts.baloo2(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: () => onAdministrar(),
                    style: TextButton.styleFrom(
                      foregroundColor: ColoresMiLocalPerfil.acentoVioleta,
                      backgroundColor: ColoresMiLocalPerfil.acentoVioleta
                          .withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                    child: Text(
                      boton,
                      style: GoogleFonts.baloo2(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardPionero(
    BuildContext context,
    EstadoSuscripcionLocal e,
    Color colorPlan,
    bool esGratis,
  ) {
    final pendiente = e.tienePagoPendiente;
    final reglas = e.reglasPionero;
    final bloquearRenov = e.pioneroBloqueaRenovacionManual;
    final String boton;
    final bool botonPrimario;

    if (pendiente) {
      boton = 'Ver estado del pago';
      botonPrimario = false;
    } else if (e.pioneroPremiumPagoActivo && e.planActivo && e.proximoAVencer) {
      boton = 'Renovar Premium';
      botonPrimario = true;
    } else if (e.pioneroPremiumPagoActivo) {
      boton = 'Administrar suscripción';
      botonPrimario = false;
    } else if (reglas.permiteUpgradePremium && !pendiente) {
      boton = 'Upgrade a Premium';
      botonPrimario = true;
    } else if (!bloquearRenov && e.planActivo && e.proximoAVencer) {
      boton = 'Renovar suscripción';
      botonPrimario = true;
    } else if (!bloquearRenov &&
        !e.planActivo &&
        (e.localVerificado || e.esPionero)) {
      boton = 'Renovar suscripción';
      botonPrimario = true;
    } else {
      boton = 'Administrar suscripción';
      botonPrimario = false;
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: ColoresMiLocalPerfil.superficie,
        border: Border.all(
          color: ProgramaPioneros.dorado.withValues(alpha: 0.35),
          width: 1.4,
        ),
        boxShadow: const [],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CabeceraResumenPionero(estado: e),
          if (e.pioneroBeneficiosActivo)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: BannerInfoPioneroSuscripcion(reglas: reglas),
            ),
          if (e.tienePagoPendiente) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  CupertinoIcons.hourglass,
                  size: 16,
                  color: Color(0xFFD97706),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pago en revisión · ${e.pagoPendiente!.planSolicitado ?? ''}',
                    style: GoogleFonts.baloo2(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ColoresLocales.textoOnFondoClaro.withValues(
                        alpha: 0.92,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 46,
            child: botonPrimario
                ? ElevatedButton(
                    onPressed: pendiente && esGratis
                        ? null
                        : () => onAdministrar(),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: ColoresMiLocalPerfil.principalMarca,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                    child: Text(
                      boton,
                      style: GoogleFonts.baloo2(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: () => onAdministrar(),
                    style: TextButton.styleFrom(
                      foregroundColor: ColoresLocales.acentoVioleta,
                      backgroundColor: ColoresLocales.acentoVioleta.withValues(
                        alpha: 0.1,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                    child: Text(
                      boton,
                      style: GoogleFonts.baloo2(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LineaResumenPerfil {
  final IconData icono;
  final Color color;
  final String texto;

  const _LineaResumenPerfil({
    required this.icono,
    required this.color,
    required this.texto,
  });
}

/// Zona de peligro al pie del perfil — misma jerarquía que app usuarios.
class _ZonaPeligroPerfil extends StatelessWidget {
  final VoidCallback onCambiarContrasena;
  final VoidCallback onEliminarCuenta;
  final VoidCallback onCerrarSesion;

  const _ZonaPeligroPerfil({
    required this.onCambiarContrasena,
    required this.onEliminarCuenta,
    required this.onCerrarSesion,
  });

  @override
  Widget build(BuildContext context) {
    final rojo = Colors.red.shade700;
    const fondoCerrarSesion = Color(0xFFE8E8E8);
    const textoCerrarSesion = Color(0xFF1A1A1A);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: rojo.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Zona de peligro',
            textAlign: TextAlign.center,
            style: GoogleFonts.baloo2(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: rojo,
            ),
          ),
          const SizedBox(height: 16),
          _BotonGrandeZonaPeligro(
            label: 'Cambiar contraseña',
            onTap: onCambiarContrasena,
            backgroundColor: ColoresMiLocalPerfil.superficieElevada,
            textColor: ColoresMiLocalPerfil.principalMarca,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onEliminarCuenta,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Eliminar cuenta',
              style: GoogleFonts.baloo2(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: rojo.withValues(alpha: 0.7),
                decoration: TextDecoration.underline,
                decorationColor: rojo.withValues(alpha: 0.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _BotonGrandeZonaPeligro(
            label: 'Cerrar sesión',
            onTap: onCerrarSesion,
            backgroundColor: fondoCerrarSesion,
            textColor: textoCerrarSesion,
          ),
        ],
      ),
    );
  }
}

class _BotonGrandeZonaPeligro extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color backgroundColor;
  final Color textColor;

  const _BotonGrandeZonaPeligro({
    required this.label,
    required this.onTap,
    required this.backgroundColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.baloo2(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pantalla completa: advertencias + escribir "eliminar" para confirmar.
class _PantallaConfirmarEliminarCuenta extends StatefulWidget {
  const _PantallaConfirmarEliminarCuenta();

  static const String palabraConfirmacion = 'eliminar';

  @override
  State<_PantallaConfirmarEliminarCuenta> createState() =>
      _PantallaConfirmarEliminarCuentaState();
}

class _PantallaConfirmarEliminarCuentaState
    extends State<_PantallaConfirmarEliminarCuenta> {
  final TextEditingController _confirmacion = TextEditingController();
  bool _puedeEliminar = false;

  @override
  void dispose() {
    _confirmacion.dispose();
    super.dispose();
  }

  void _revisarConfirmacion(String valor) {
    final ok =
        valor.trim().toLowerCase() ==
        _PantallaConfirmarEliminarCuenta.palabraConfirmacion;
    if (ok != _puedeEliminar) setState(() => _puedeEliminar = ok);
  }

  @override
  Widget build(BuildContext context) {
    final rojo = Colors.red.shade700;
    final padding = MediaQuery.paddingOf(context);

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: ColoresLocales.fondoPrincipal,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close),
            color: ColoresMiLocalPerfil.textoPrincipal,
            onPressed: () => Navigator.pop(context, false),
          ),
          title: Text(
            'Eliminar cuenta',
            style: GoogleFonts.baloo2(
              color: rojo,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: rojo,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Esta acción es permanente.\nNo vas a poder recuperar ningún dato.',
                              style: GoogleFonts.baloo2(
                                color: rojo,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Se borrará para siempre:',
                      style: GoogleFonts.baloo2(
                        color: ColoresMiLocalPerfil.textoPrincipal,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...[
                      'Tu perfil y datos del local',
                      'Fotos, banner y flyers generados',
                      'Eventos, promociones y listas',
                      'Staff vinculado y toda la configuración',
                      'Tu cuenta de acceso (email o Google)',
                    ].map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.close, size: 18, color: rojo),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item,
                                style: GoogleFonts.baloo2(
                                  color: ColoresMiLocalPerfil.textoPrincipal,
                                  fontSize: 14,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Fernecito no guarda copias de respaldo. Si eliminás la cuenta, perdés todo el historial de tu local.',
                      style: GoogleFonts.baloo2(
                        color: ColoresMiLocalPerfil.textoSecundario,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _puedeEliminar
                            ? Colors.red.withOpacity(0.08)
                            : ColoresLocales.superficie,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Para continuar, escribí la palabra:',
                            style: GoogleFonts.baloo2(
                              color: ColoresMiLocalPerfil.textoPrincipal,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _PantallaConfirmarEliminarCuenta
                                .palabraConfirmacion,
                            style: GoogleFonts.baloo2(
                              color: rojo,
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _confirmacion,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.done,
                            textCapitalization: TextCapitalization.none,
                            onChanged: _revisarConfirmacion,
                            onSubmitted: _puedeEliminar
                                ? (_) => Navigator.pop(context, true)
                                : null,
                            decoration: InputDecoration(
                              hintText: 'Escribí: eliminar',
                              hintStyle: GoogleFonts.baloo2(
                                color: ColoresMiLocalPerfil.textoSecundario,
                              ),
                              filled: true,
                              fillColor: ColoresLocales.rellenoInput,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            style: GoogleFonts.baloo2(
                              color: ColoresMiLocalPerfil.textoPrincipal,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (!_puedeEliminar &&
                              _confirmacion.text.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'La palabra no coincide. Tiene que ser exactamente "eliminar".',
                              style: GoogleFonts.baloo2(
                                color: rojo,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(20, 12, 20, padding.bottom + 16),
              color: ColoresMiLocalPerfil.superficie,
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _puedeEliminar
                          ? () => Navigator.pop(context, true)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: rojo,
                        disabledBackgroundColor: Colors.red.withOpacity(0.22),
                        disabledForegroundColor: Colors.white54,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _puedeEliminar
                            ? 'Eliminar definitivamente'
                            : 'Escribí "eliminar" para habilitar',
                        style: GoogleFonts.baloo2(
                          color: ColoresLocales.textoPrincipal,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(
                        'Cancelar y volver',
                        style: GoogleFonts.baloo2(
                          color: ColoresMiLocalPerfil.textoSecundario,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
