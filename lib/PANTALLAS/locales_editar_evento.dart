library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants.dart';
import '../widgets/tema_locales_scope.dart';
import '../core/supabase_client.dart';
import '../core/servicio_edges_eventos.dart';

class LocalesEditarEvento extends StatefulWidget {
  final String idEvento;
  const LocalesEditarEvento({super.key, required this.idEvento});

  @override
  State<LocalesEditarEvento> createState() => _LocalesEditarEventoState();
}

class _LocalesEditarEventoState extends State<LocalesEditarEvento> {
  bool _cargando = true;
  bool _guardando = false;
  int _paso = 1;

  String? _idLocal;
  String _urlFlyer = '';
  DateTime? _fechaInicio;
  DateTime? _fechaFin;
  String _modoLista = 'auto';
  int _cupoListaUsados = 0;

  final _tituloCtrl = TextEditingController();
  final _descripcionCtrl = TextEditingController();
  final _urlCompraCtrl = TextEditingController();
  final _cupoListaMaxCtrl = TextEditingController();
  final List<_PromoEdit> _promos = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _descripcionCtrl.dispose();
    _urlCompraCtrl.dispose();
    _cupoListaMaxCtrl.dispose();
    for (final p in _promos) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final evento = await ServicioSupabase().cliente
          .from('eventos')
          .select(
            'id_local, titulo_evento, descripcion_evento, url_flyer, url_compra_entradas, fecha_inicio, fecha_fin, modo_lista, cupo_lista_max, cupo_lista_usados',
          )
          .eq('id_evento', widget.idEvento)
          .maybeSingle();
      if (evento == null) throw Exception('Evento no encontrado');

      final promos = await ServicioSupabase().cliente
          .from('promociones')
          .select(
            'titulo_promocion, descripcion_promocion, fecha_inicio, fecha_fin, cupos_totales, cupos_usados, modo_uso, min_miembros_squad, max_miembros_squad, estado_promocion, fecha_creacion',
          )
          .eq('id_evento', widget.idEvento);

      if (!mounted) return;
      setState(() {
        _idLocal = evento['id_local']?.toString();
        _tituloCtrl.text = (evento['titulo_evento'] as String?) ?? '';
        _descripcionCtrl.text = (evento['descripcion_evento'] as String?) ?? '';
        _urlFlyer = (evento['url_flyer'] as String?)?.trim() ?? '';
        _urlCompraCtrl.text = (evento['url_compra_entradas'] as String?) ?? '';
        _fechaInicio = _parseDate(evento['fecha_inicio']);
        _fechaFin = _parseDate(evento['fecha_fin']);
        _modoLista = (evento['modo_lista'] as String?) ?? 'auto';
        _cupoListaUsados = (evento['cupo_lista_usados'] as num?)?.toInt() ?? 0;
        _cupoListaMaxCtrl.text =
            ((evento['cupo_lista_max'] as num?)?.toInt())?.toString() ?? '';
        _promos.clear();
        for (final m in (promos as List).cast<Map<String, dynamic>>()) {
          _promos.add(_PromoEdit.fromMap(m));
        }
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
      _mostrarMsg('No se pudo cargar el evento.');
    }
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String && v.trim().isNotEmpty) return DateTime.tryParse(v);
    return DateTime.tryParse(v.toString());
  }

  String _fmt(DateTime? d) {
    if (d == null) return 'Seleccionar fecha y hora';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _pickDate({
    required DateTime? current,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final ahora = DateTime.now();
    final DateTime base = current ?? ahora;
    final DateTime minDate = DateTime(ahora.year - 1);
    final DateTime maxDate = DateTime(ahora.year + 5, 12, 31, 23, 59);
    DateTime temporal = base.isBefore(minDate)
        ? minDate
        : (base.isAfter(maxDate) ? maxDate : base);

    final seleccion = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: ColoresLocales.superficie,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SizedBox(
              height: 320,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Localizations.override(
                        context: ctx,
                        locale: const Locale('es', 'AR'),
                        delegates: const [
                          GlobalCupertinoLocalizations.delegate,
                          GlobalWidgetsLocalizations.delegate,
                          GlobalMaterialLocalizations.delegate,
                        ],
                        child: CupertinoTheme(
                          data: CupertinoThemeData(
                            brightness: Brightness.light,
                          ),
                          child: CupertinoDatePicker(
                            mode: CupertinoDatePickerMode.dateAndTime,
                            use24hFormat: true,
                            initialDateTime: temporal,
                            minimumDate: minDate,
                            maximumDate: maxDate,
                            onDateTimeChanged: (value) {
                              setSheetState(() => temporal = value);
                            },
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: ColoresLocales.cardLavanda,
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(
                            color: ColoresLocales.acentoVioleta.withOpacity(
                              0.2,
                            ),
                          ),
                        ),
                        child: Text(
                          'Año: ${temporal.year}',
                          style: GoogleFonts.baloo2(
                            color: ColoresLocales.acentoVioleta,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text(
                            'Cancelar',
                            style: GoogleFonts.baloo2(
                              color: ColoresLocales.acentoVioleta,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: () => Navigator.of(ctx).pop(temporal),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ColoresLocales.acentoVioleta,
                            foregroundColor: ColoresLocales.textoEnBoton,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(50),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'Listo',
                            style: GoogleFonts.baloo2(
                              fontWeight: FontWeight.w800,
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

    if (seleccion != null) {
      onPicked(seleccion);
    }
  }

  bool _validarPaso1() {
    if (_tituloCtrl.text.trim().isEmpty) {
      _mostrarMsg('Completá el título.');
      return false;
    }
    if (_fechaInicio == null || _fechaFin == null) {
      _mostrarMsg('Elegí fecha de inicio y fin.');
      return false;
    }
    if (!_fechaFin!.isAfter(_fechaInicio!)) {
      _mostrarMsg('La fecha fin debe ser mayor a inicio.');
      return false;
    }
    // cupo_lista_max es opcional (null = sin límite); si ingresaron algo, debe ser >= 1
    final cupoTxt = _cupoListaMaxCtrl.text.trim();
    if (cupoTxt.isNotEmpty) {
      final cupo = int.tryParse(cupoTxt);
      if (cupo == null || cupo < 1) {
        _mostrarMsg(
          'El cupo máximo de lista debe ser >= 1, o dejalo vacío para sin límite.',
        );
        return false;
      }
    }
    return true;
  }

  bool _validarPromos() {
    for (final p in _promos) {
      if (p.tituloCtrl.text.trim().isEmpty) {
        _mostrarMsg('Completá el título de todas las promos.');
        return false;
      }
      if (p.fechaInicio == null || p.fechaFin == null) {
        _mostrarMsg('Completá fechas de todas las promos.');
        return false;
      }
      if (!p.fechaFin!.isAfter(p.fechaInicio!)) {
        _mostrarMsg('Cada promo debe tener fecha fin mayor a inicio.');
        return false;
      }
      if (p.limitarCantidad) {
        final cupos = int.tryParse(p.cuposCtrl.text.trim());
        if (cupos == null || cupos < 1) {
          _mostrarMsg('Si limitás cantidad, ingresá un cupo válido (>= 1).');
          return false;
        }
      }
      if (p.modoUso == 'squad') {
        final minM = int.tryParse(p.minMiembrosCtrl.text.trim());
        final maxM = int.tryParse(p.maxMiembrosCtrl.text.trim());
        if (minM != null && minM < 1) {
          _mostrarMsg('Mínimo de miembros debe ser >= 1.');
          return false;
        }
        if (maxM != null && maxM < 1) {
          _mostrarMsg('Máximo de miembros debe ser >= 1.');
          return false;
        }
        if (minM != null && maxM != null && minM > maxM) {
          _mostrarMsg('En promos squad, mínimo no puede ser mayor al máximo.');
          return false;
        }
      }
    }
    return true;
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    if (!_validarPaso1() || !_validarPromos()) return;
    if (_idLocal == null) {
      _mostrarMsg('No se encontró el local del evento.');
      return;
    }

    setState(() => _guardando = true);
    try {
      // Campos del evento — nombres de columnas reales en la tabla eventos
      final campos = <String, dynamic>{
        'titulo_evento': _tituloCtrl.text.trim(),
        'descripcion_evento': _descripcionCtrl.text.trim().isEmpty
            ? null
            : _descripcionCtrl.text.trim(),
        'fecha_inicio': _fechaInicio!.toUtc().toIso8601String(),
        'fecha_fin': _fechaFin!.toUtc().toIso8601String(),
        'modo_lista': _modoLista,
        'cupo_lista_max': int.tryParse(_cupoListaMaxCtrl.text.trim()),
        // url_compra_entradas no está en CAMPOS_EDITABLES de la edge — se guarda directo
      };

      await ServicioEdgesEventos().editarEvento(
        idEvento: widget.idEvento,
        campos: campos,
      );

      // url_compra_entradas: actualizar directamente (no es campo sensible de seguridad)
      final urlCompra = _urlCompraCtrl.text.trim();
      await ServicioSupabase().cliente
          .from('eventos')
          .update({'url_compra_entradas': urlCompra.isEmpty ? null : urlCompra})
          .eq('id_evento', widget.idEvento);

      // Promociones: upsert directo (el owner tiene RLS para escribir sus promos)
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final payloadPromos = _promos
          .map(
            (p) => {
              'id_evento': widget.idEvento,
              'titulo_promocion': p.tituloCtrl.text.trim(),
              'descripcion_promocion': p.descripcionCtrl.text.trim(),
              'fecha_inicio': p.fechaInicio!.toUtc().toIso8601String(),
              'fecha_fin': p.fechaFin!.toUtc().toIso8601String(),
              'cupos_totales': p.limitarCantidad
                  ? int.tryParse(p.cuposCtrl.text.trim())
                  : null,
              'cupos_usados': p.cuposUsados,
              'modo_uso': p.modoUso,
              'min_miembros_squad': p.modoUso == 'squad'
                  ? int.tryParse(p.minMiembrosCtrl.text.trim())
                  : null,
              'max_miembros_squad': p.modoUso == 'squad'
                  ? int.tryParse(p.maxMiembrosCtrl.text.trim())
                  : null,
              'estado_promocion': p.estadoPromocion,
              'fecha_creacion': p.fechaCreacion ?? nowIso,
              'fecha_actualizacion': nowIso,
            },
          )
          .toList();

      if (payloadPromos.isNotEmpty) {
        // Primero borramos las existentes y reinsertamos (upsert simple por id_evento)
        await ServicioSupabase().cliente
            .from('promociones')
            .delete()
            .eq('id_evento', widget.idEvento);
        await ServicioSupabase().cliente
            .from('promociones')
            .insert(payloadPromos);
      }

      if (!mounted) return;
      setState(() => _paso = 3);
    } catch (e) {
      _mostrarMsg('No se pudo guardar cambios: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _mostrarMsg(String txt) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Atención'),
        content: Text(txt),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK'),
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
        backgroundColor: ColoresLocales.fondoClaro,
        body: Center(
          child: CircularProgressIndicator(color: ColoresLocales.acentoVioleta),
        ),
      );
    }

    if (_paso == 3) return _buildExito(context);

    return Scaffold(
      backgroundColor: ColoresLocales.superficie,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: ColoresLocales.superficie,
        centerTitle: true,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {
            if (_paso == 2) {
              setState(() => _paso = 1);
            } else {
              Navigator.of(context).pop();
            }
          },
          child: Icon(
            CupertinoIcons.chevron_back,
            color: ColoresLocales.acentoVioleta,
          ),
        ),
        title: Text(
          _paso == 1 ? 'Editar evento' : 'Editar promos',
          style: GoogleFonts.baloo2(
            color: ColoresLocales.acentoVioleta,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        child: Column(
          children: [
            if (_paso == 1) _buildPaso1(),
            if (_paso == 2) _buildPaso2(),
          ],
        ),
      ),
      bottomNavigationBar: _buildFooter(),
    );
  }

  Widget _buildPaso1() {
    return Column(
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Datos principales',
                style: GoogleFonts.baloo2(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 10),
              _field(_tituloCtrl, 'Título del evento'),
              const SizedBox(height: 10),
              _field(_descripcionCtrl, 'Descripción', maxLines: 4),
              const SizedBox(height: 10),
              _field(_urlCompraCtrl, 'Link compra entradas (opcional)'),
              const SizedBox(height: 10),
              _fechaTile(
                'Inicio',
                _fmt(_fechaInicio),
                () => _pickDate(
                  current: _fechaInicio,
                  onPicked: (d) => setState(() => _fechaInicio = d),
                ),
              ),
              const SizedBox(height: 8),
              _fechaTile(
                'Fin',
                _fmt(_fechaFin),
                () => _pickDate(
                  current: _fechaFin,
                  onPicked: (d) => setState(() => _fechaFin = d),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Lista del evento',
                style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              _infoFila('Modo lista', _modoLista),
              const SizedBox(height: 8),
              _field(
                _cupoListaMaxCtrl,
                'Cupo máximo de lista (vacío = sin límite)',
              ),
              const SizedBox(height: 8),
              _infoFila('Cupos usados', '$_cupoListaUsados'),
            ],
          ),
        ),
        if (_urlFlyer.isNotEmpty)
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Flyer actual',
                  style: GoogleFonts.baloo2(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    height: 220,
                    child: Image.network(
                      _urlFlyer,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(CupertinoIcons.photo),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPaso2() {
    return Column(
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Promos del evento',
                style: GoogleFonts.baloo2(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
              SizedBox(height: 8),
              ..._promos.asMap().entries.map((e) {
                final i = e.key;
                final p = e.value;
                return Container(
                  margin: EdgeInsets.only(bottom: 10),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ColoresLocales.superficie,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: ColoresLocales.acentoVioleta.withOpacity(0.18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Promo ${i + 1}',
                            style: GoogleFonts.baloo2(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => setState(() {
                              final removed = _promos.removeAt(i);
                              removed.dispose();
                            }),
                            icon: const Icon(CupertinoIcons.trash, size: 20),
                          ),
                        ],
                      ),
                      _field(p.tituloCtrl, 'Título promo'),
                      const SizedBox(height: 8),
                      _field(
                        p.descripcionCtrl,
                        'Descripción promo',
                        maxLines: 3,
                      ),
                      SizedBox(height: 8),
                      _fechaTile(
                        'Inicio promo',
                        _fmt(p.fechaInicio),
                        () => _pickDate(
                          current: p.fechaInicio,
                          onPicked: (d) => setState(() => p.fechaInicio = d),
                        ),
                      ),
                      SizedBox(height: 8),
                      _fechaTile(
                        'Fin promo',
                        _fmt(p.fechaFin),
                        () => _pickDate(
                          current: p.fechaFin,
                          onPicked: (d) => setState(() => p.fechaFin = d),
                        ),
                      ),
                      SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        value: p.limitarCantidad,
                        onChanged: (v) => setState(() => p.limitarCantidad = v),
                        contentPadding: EdgeInsets.zero,
                        activeColor: ColoresLocales.acentoVioleta,
                        title: Text(
                          '¿Limitar cantidad?',
                          style: GoogleFonts.baloo2(
                            color: ColoresLocales.textoOnFondoClaro,
                          ),
                        ),
                      ),
                      if (p.limitarCantidad) ...[
                        const SizedBox(height: 8),
                        _field(p.cuposCtrl, 'Cantidad máxima'),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _chipSeleccion(
                              label: 'Individual',
                              selected: p.modoUso == 'individual',
                              onTap: () =>
                                  setState(() => p.modoUso = 'individual'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _chipSeleccion(
                              label: 'Squad',
                              selected: p.modoUso == 'squad',
                              onTap: () => setState(() => p.modoUso = 'squad'),
                            ),
                          ),
                        ],
                      ),
                      if (p.modoUso == 'squad') ...[
                        const SizedBox(height: 8),
                        _field(p.minMiembrosCtrl, 'Mínimo de miembros'),
                        const SizedBox(height: 8),
                        _field(p.maxMiembrosCtrl, 'Máximo de miembros'),
                      ],
                    ],
                  ),
                );
              }),
              OutlinedButton.icon(
                onPressed: () => setState(() => _promos.add(_PromoEdit())),
                icon: const Icon(CupertinoIcons.add),
                label: Text(
                  'Agregar promo',
                  style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
                ),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chipSeleccion({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 150),
        height: 42,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? ColoresLocales.acentoVioleta
              : ColoresLocales.cardLavanda,
          borderRadius: BorderRadius.circular(50),
          border: selected
              ? null
              : Border.all(
                  color: ColoresLocales.acentoVioleta.withOpacity(0.25),
                ),
        ),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.baloo2(
              color: selected ? Colors.white : ColoresLocales.textoOnFondoClaro,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: ColoresLocales.fondoClaro,
        border: Border(
          top: BorderSide(
            color: ColoresLocales.acentoVioleta.withOpacity(0.12),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_paso == 2)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _guardando
                      ? null
                      : () => setState(() => _paso = 1),
                  icon: const Icon(CupertinoIcons.chevron_left),
                  label: Text(
                    'Volver',
                    style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50),
                    ),
                  ),
                ),
              ),
            if (_paso == 2) SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _guardando
                    ? null
                    : () {
                        if (_paso == 1) {
                          if (_validarPaso1()) setState(() => _paso = 2);
                        } else {
                          _guardar();
                        }
                      },
                icon: Icon(
                  _paso == 1
                      ? CupertinoIcons.arrow_right_circle_fill
                      : CupertinoIcons.checkmark_seal_fill,
                ),
                label: _guardando
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ColoresLocales.chipInactivo,
                        ),
                      )
                    : Text(
                        _paso == 1 ? 'Continuar' : 'Guardar cambios',
                        style: GoogleFonts.baloo2(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                style: ElevatedButton.styleFrom(
                  minimumSize: Size.fromHeight(52),
                  backgroundColor: ColoresLocales.acentoVioleta,
                  foregroundColor: ColoresLocales.textoEnBoton,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExito(BuildContext context) {
    return Scaffold(
      backgroundColor: ColoresLocales.acentoVioleta,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  CupertinoIcons.checkmark_seal_fill,
                  color: ColoresLocales.chipInactivo,
                  size: 88,
                ),
                const SizedBox(height: 10),
                Text(
                  'Cambios guardados con éxito',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.baloo2(
                    color: ColoresLocales.chipInactivo,
                    fontWeight: FontWeight.w900,
                    fontSize: 32,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Tu evento fue actualizado correctamente.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.baloo2(
                    color: Colors.white.withOpacity(0.92),
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/home',
                    (route) => false,
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size.fromHeight(52),
                    backgroundColor: ColoresLocales.superficie,
                    foregroundColor: ColoresLocales.acentoVioleta,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50),
                    ),
                  ),
                  child: Text(
                    'Volver al dashboard',
                    style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
                  ),
                ),
                SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/home',
                      (route) => false,
                    );
                    Future.delayed(const Duration(milliseconds: 60), () {
                      if (context.mounted) {
                        Navigator.pushNamed(context, '/mis_eventos');
                      }
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    side: BorderSide(color: Colors.white.withOpacity(0.8)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50),
                    ),
                  ),
                  child: Text(
                    'Ir a mis eventos',
                    style: GoogleFonts.baloo2(
                      color: ColoresLocales.chipInactivo,
                      fontWeight: FontWeight.w700,
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

  Widget _card({required Widget child}) {
    return Container(
      margin: EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ColoresLocales.superficie.withOpacity(0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: ColoresLocales.acentoVioleta.withOpacity(0.18),
        ),
      ),
      child: child,
    );
  }

  Widget _field(TextEditingController c, String hint, {int maxLines = 1}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      style: GoogleFonts.baloo2(color: ColoresLocales.textoOnFondoClaro),
      inputFormatters: maxLines == 1 ? [] : null,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.baloo2(
          color: ColoresLocales.textoSecundarioOnFondoClaro,
        ),
        filled: true,
        fillColor: ColoresLocales.rellenoInput,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(maxLines == 1 ? 50 : 16),
          borderSide: BorderSide(
            color: ColoresLocales.acentoVioleta.withOpacity(0.22),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(maxLines == 1 ? 50 : 16),
          borderSide: BorderSide(
            color: ColoresLocales.acentoVioleta.withOpacity(0.22),
          ),
        ),
      ),
    );
  }

  Widget _infoFila(String label, String valor) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: ColoresLocales.acentoVioleta.withOpacity(0.08),
        border: Border.all(
          color: ColoresLocales.acentoVioleta.withOpacity(0.22),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$label: $valor',
              style: GoogleFonts.baloo2(
                fontWeight: FontWeight.w700,
                color: ColoresLocales.textoOnFondoClaro,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fechaTile(String label, String value, VoidCallback onTap) {
    final sinFecha = value == 'Seleccionar fecha y hora';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: ColoresLocales.cardLavanda,
          border: Border.all(
            color: ColoresLocales.acentoVioleta.withOpacity(0.35),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$label: $value',
                style: GoogleFonts.baloo2(
                  fontWeight: FontWeight.w700,
                  color: sinFecha
                      ? ColoresLocales.textoSecundarioOnFondoClaro
                      : ColoresLocales.textoOnFondoClaro,
                ),
              ),
            ),
            Icon(
              CupertinoIcons.calendar,
              size: 20,
              color: ColoresLocales.acentoVioleta,
            ),
          ],
        ),
      ),
    );
  }
}

class _PromoEdit {
  final tituloCtrl = TextEditingController();
  final descripcionCtrl = TextEditingController();
  final cuposCtrl = TextEditingController();
  final minMiembrosCtrl = TextEditingController();
  final maxMiembrosCtrl = TextEditingController();
  DateTime? fechaInicio;
  DateTime? fechaFin;
  bool limitarCantidad = false;
  String modoUso = 'individual';
  int cuposUsados = 0;
  String estadoPromocion = 'activa';
  String? fechaCreacion;

  _PromoEdit();

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String && v.trim().isNotEmpty) return DateTime.tryParse(v);
    return DateTime.tryParse(v.toString());
  }

  factory _PromoEdit.fromMap(Map<String, dynamic> m) {
    final p = _PromoEdit();
    p.tituloCtrl.text = (m['titulo_promocion'] as String?) ?? '';
    p.descripcionCtrl.text = (m['descripcion_promocion'] as String?) ?? '';
    p.fechaInicio = _parseDate(m['fecha_inicio']);
    p.fechaFin = _parseDate(m['fecha_fin']);
    final cuposTotales = (m['cupos_totales'] as num?)?.toInt();
    if (cuposTotales != null && cuposTotales > 0) {
      p.limitarCantidad = true;
      p.cuposCtrl.text = cuposTotales.toString();
    }
    p.cuposUsados = (m['cupos_usados'] as num?)?.toInt() ?? 0;
    p.modoUso =
        ((m['modo_uso'] as String?) ?? 'individual').toLowerCase() == 'squad'
        ? 'squad'
        : 'individual';
    p.minMiembrosCtrl.text =
        ((m['min_miembros_squad'] as num?)?.toInt())?.toString() ?? '';
    p.maxMiembrosCtrl.text =
        ((m['max_miembros_squad'] as num?)?.toInt())?.toString() ?? '';
    p.estadoPromocion = (m['estado_promocion'] as String?) ?? 'activa';
    p.fechaCreacion = (m['fecha_creacion'] as String?);
    return p;
  }

  void dispose() {
    tituloCtrl.dispose();
    descripcionCtrl.dispose();
    cuposCtrl.dispose();
    minMiembrosCtrl.dispose();
    maxMiembrosCtrl.dispose();
  }
}
