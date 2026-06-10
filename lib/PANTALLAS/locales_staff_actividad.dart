/// Actividad reciente del staff (canjes + listas aceptadas/rechazadas).
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/colores_staff.dart';
import '../core/servicio_staff_locales.dart';
import '../models/actividad_staff.dart';
import '../widgets/scaffold_staff.dart';
import '../widgets/tema_locales_scope.dart';

class LocalesStaffActividad extends StatefulWidget {
  const LocalesStaffActividad({super.key});

  @override
  State<LocalesStaffActividad> createState() => _LocalesStaffActividadState();
}

class _LocalesStaffActividadState extends State<LocalesStaffActividad> {
  List<ActividadStaffItem> _items = const [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final lista = await ServicioStaffLocales().listarActividadReciente();
      if (!mounted) return;
      setState(() {
        _items = lista;
        _cargando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _fmtFecha(DateTime d) {
    final ahora = DateTime.now();
    final dif = ahora.difference(d);
    if (dif.inMinutes < 1) return 'Ahora';
    if (dif.inMinutes < 60) return 'Hace ${dif.inMinutes} min';
    if (dif.inHours < 24 && d.day == ahora.day) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    if (dif.inDays == 1) return 'Ayer';
    if (dif.inDays < 7) return 'Hace ${dif.inDays} d';
    return '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  /// Agrupa items por "hoy", "ayer", "esta semana", "anterior"
  Map<String, List<ActividadStaffItem>> _agrupar() {
    final hoy = DateTime.now();
    final inicioHoy = DateTime(hoy.year, hoy.month, hoy.day);
    final ayer = inicioHoy.subtract(const Duration(days: 1));
    final semana = inicioHoy.subtract(const Duration(days: 7));

    final grupos = <String, List<ActividadStaffItem>>{
      'Hoy': [],
      'Ayer': [],
      'Esta semana': [],
      'Anterior': [],
    };
    for (final it in _items) {
      if (!it.fecha.isBefore(inicioHoy)) {
        grupos['Hoy']!.add(it);
      } else if (!it.fecha.isBefore(ayer)) {
        grupos['Ayer']!.add(it);
      } else if (!it.fecha.isBefore(semana)) {
        grupos['Esta semana']!.add(it);
      } else {
        grupos['Anterior']!.add(it);
      }
    }
    grupos.removeWhere((_, v) => v.isEmpty);
    return grupos;
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final grupos = _agrupar();
    final totalHoy = grupos['Hoy']?.length ?? 0;

    return ScaffoldStaff(
      appBar: appBarStaff(
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: Icon(CupertinoIcons.chevron_back, color: ColoresStaff.acento),
        ),
        title: Text(
          'Mi actividad',
          style: GoogleFonts.baloo2(fontWeight: FontWeight.w900, color: ColoresStaff.acento),
        ),
      ),
      body: RefreshIndicator(
        color: ColoresStaff.acento,
        onRefresh: _cargar,
        child: _cargando
            ? ListView(children: [
                const SizedBox(height: 120),
                Center(child: CircularProgressIndicator(color: ColoresStaff.acento)),
              ])
            : _items.isEmpty
                ? ListView(children: [
                    const SizedBox(height: 100),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(
                              CupertinoIcons.clock,
                              size: 56,
                              color: ColoresStaff.acento.withOpacity(0.35),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Sin actividad todavía',
                              style: GoogleFonts.baloo2(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: ColoresStaff.textoPrincipal,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Acá vas a ver canjes, listas e invitaciones QR que registres.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.baloo2(
                                fontSize: 13,
                                color: ColoresStaff.textoSecundario,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ])
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      // Stats chip de hoy
                      if (totalHoy > 0)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                ColoresStaff.acento.withOpacity(0.10),
                                ColoresStaff.acento.withOpacity(0.04),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Icon(CupertinoIcons.bolt_fill, color: ColoresStaff.acento),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  totalHoy == 1
                                      ? 'Llevás 1 acción hoy'
                                      : 'Llevás $totalHoy acciones hoy',
                                  style: GoogleFonts.baloo2(
                                    fontWeight: FontWeight.w900,
                                    color: ColoresStaff.textoPrincipal,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ...grupos.entries.expand((entry) => [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 4, 0, 10),
                              child: Text(
                                entry.key,
                                style: GoogleFonts.baloo2(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: ColoresStaff.textoSecundario,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            ...entry.value.map((a) => _tileActividad(a)),
                            const SizedBox(height: 10),
                          ]),
                    ],
                  ),
      ),
    );
  }

  Widget _tileActividad(ActividadStaffItem a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ColoresStaff.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: a.colorEstado.withOpacity(0.20)),
        boxShadow: [
          BoxShadow(
            color: ColoresStaff.sombraCard,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: a.colorEstado.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(a.icono, color: a.colorEstado, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  a.titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.baloo2(
                    fontWeight: FontWeight.w900,
                    color: ColoresStaff.textoPrincipal,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  a.subtitulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.baloo2(
                    fontSize: 12,
                    color: ColoresStaff.textoSecundario,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Chip de estado
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: a.colorEstado.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  a.estadoLabel,
                  style: GoogleFonts.baloo2(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: a.colorEstado,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _fmtFecha(a.fecha),
                style: GoogleFonts.baloo2(
                  fontSize: 11,
                  color: ColoresStaff.textoSecundario,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
