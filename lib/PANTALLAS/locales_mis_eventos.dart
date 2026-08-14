library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants.dart';
import '../widgets/tema_locales_scope.dart';
import '../widgets/estado_error_locales.dart';
import '../widgets/feedback_locales.dart';
import '../widgets/skeleton_lista_eventos.dart';
import '../core/formato_metricas.dart';
import '../core/navegacion_posicionamiento.dart';
import '../core/supabase_client.dart';
import '../core/servicio_edges_eventos.dart';
import 'locales_editar_evento.dart';
import 'locales_posicionamiento.dart';
import 'locales_vista_previa.dart';

class LocalesMisEventos extends StatefulWidget {
  const LocalesMisEventos({super.key});

  @override
  State<LocalesMisEventos> createState() => _LocalesMisEventosState();
}

class _LocalesMisEventosState extends State<LocalesMisEventos> {
  bool _cargando = true;
  bool _localVerificado = false;
  String? _error;
  final Set<String> _borrando = {};
  final Set<String> _cancelando = {};
  List<_EventoMini> _eventosActivos = [];
  List<_EventoMini> _eventosHistorial = [];
  String _filtro = 'activos';

  @override
  void initState() {
    super.initState();
    NavegacionPosicionamiento.registrarActualizacion(_onEventoActualizado);
    _cargarEventos();
  }

  @override
  void dispose() {
    NavegacionPosicionamiento.desregistrarActualizacion(_onEventoActualizado);
    super.dispose();
  }

  void _onEventoActualizado() {
    if (!mounted) return;
    _cargarEventos();
  }

  Future<void> _cargarEventos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final uid = ServicioSupabase().usuarioActual?.id;
      if (uid == null) {
        setState(() {
          _cargando = false;
          _error = 'No encontramos tu sesión.';
        });
        return;
      }

      final dataActivos = await ServicioSupabase().cliente
          .from('eventos')
          .select(
            'id_evento, id_local, titulo_evento, descripcion_evento, url_flyer, fecha_inicio, fecha_fin, fecha_fin_publicacion, fecha_fin_jerarquia, modo_lista, cupo_lista_max, cupo_lista_usados, edad_minima, jerarquia, tiene_promo, url_compra_entradas, estado_publicacion, metric_visitas, promociones(titulo_promocion), perfiles_locales!eventos_id_local_fkey(local_verificado)',
          )
          .eq('id_local', uid)
          .or(
            'estado_publicacion.eq.publicado,estado_publicacion.eq.finalizado,estado_publicacion.eq.cancelado',
          )
          .order('fecha_inicio', ascending: false);

      final listActivos = (dataActivos as List).cast<Map<String, dynamic>>();
      // Historial: finalizado + cancelado
      final listHistorial = listActivos
          .where((e) {
            final estado = e['estado_publicacion']?.toString();
            return estado == 'finalizado' || estado == 'cancelado';
          })
          .toList();
      // Activos: solo publicados
      final listPublicados = listActivos
          .where((e) => e['estado_publicacion']?.toString() == 'publicado')
          .toList();

      bool localVerificado = false;
      if (listActivos.isNotEmpty) {
        final perfilMap = listActivos.first['perfiles_locales'];
        if (perfilMap is Map<String, dynamic>) {
          localVerificado = perfilMap['local_verificado'] as bool? ?? false;
        }
      }
      setState(() {
        _eventosActivos = listPublicados.map(_EventoMini.fromMap).toList();
        _eventosHistorial = listHistorial.map(_EventoMini.fromMap).toList();
        _localVerificado = localVerificado;
        _cargando = false;
      });
    } catch (e) {
      setState(() {
        _error = 'No se pudo cargar tus eventos: $e';
        _cargando = false;
      });
    }
  }

  Future<void> _confirmarBorrado(_EventoMini ev) async {
    if (_borrando.contains(ev.idEvento)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Borrar evento',
          style: GoogleFonts.baloo2(fontWeight: FontWeight.w900),
        ),
        content: Text(
          '¿Seguro que querés borrar "${ev.titulo}"?',
          style: GoogleFonts.baloo2(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Borrar', style: TextStyle(color: Colors.red.shade700)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _borrando.add(ev.idEvento));
    try {
      await ServicioEdgesEventos().borrarEvento(idEvento: ev.idEvento);
      if (!mounted) return;
      setState(() {
        _borrando.remove(ev.idEvento);
        _eventosActivos = _eventosActivos
            .where((e) => e.idEvento != ev.idEvento)
            .toList();
        _eventosHistorial = _eventosHistorial
            .where((e) => e.idEvento != ev.idEvento)
            .toList();
      });
      FeedbackLocales.mostrarExito(context, 'Evento eliminado');
    } catch (e) {
      if (!mounted) return;
      setState(() => _borrando.remove(ev.idEvento));
      _mostrarError('No se pudo borrar: $e');
    }
  }

  Future<void> _confirmarCancelado(_EventoMini ev) async {
    if (_cancelando.contains(ev.idEvento)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Despublicar evento',
          style: GoogleFonts.baloo2(fontWeight: FontWeight.w900),
        ),
        content: Text(
          '¿Querés quitar "${ev.titulo}" de la cartelera?\n\nEl evento pasará al historial como cancelado.',
          style: GoogleFonts.baloo2(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.baloo2(fontWeight: FontWeight.w700),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Sí, quitar de cartelera',
              style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _cancelando.add(ev.idEvento));
    try {
      await ServicioEdgesEventos().cancelarEvento(idEvento: ev.idEvento);
      if (!mounted) return;
      setState(() {
        _cancelando.remove(ev.idEvento);
        final cancelado = _EventoMini(
          idEvento: ev.idEvento,
          idLocal: ev.idLocal,
          titulo: ev.titulo,
          descripcion: ev.descripcion,
          urlFlyer: ev.urlFlyer,
          fechaInicio: ev.fechaInicio,
          fechaFin: ev.fechaFin,
          fechaFinPublicacion: ev.fechaFinPublicacion,
          fechaFinJerarquia: ev.fechaFinJerarquia,
          modoLista: ev.modoLista,
          cupoListaMax: ev.cupoListaMax,
          cupoListaUsados: ev.cupoListaUsados,
          edadMinima: ev.edadMinima,
          jerarquia: ev.jerarquia,
          tienePromo: ev.tienePromo,
          urlCompraEntradas: ev.urlCompraEntradas,
          promos: ev.promos,
          estadoPublicacion: 'cancelado',
        );
        _eventosActivos = _eventosActivos
            .where((e) => e.idEvento != ev.idEvento)
            .toList();
        // Agregar al historial con estado cancelado
        _eventosHistorial = [cancelado, ..._eventosHistorial];
      });
      FeedbackLocales.mostrarExito(context, 'Evento quitado de la cartelera');
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancelando.remove(ev.idEvento));
      _mostrarError('No se pudo despublicar: $e');
    }
  }

  Future<void> _mostrarModalEditarBorrar(_EventoMini ev) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Editar o borrar',
          style: GoogleFonts.baloo2(fontWeight: FontWeight.w900),
        ),
        content: Text(
          '¿Qué querés hacer con "${ev.titulo}"?',
          style: GoogleFonts.baloo2(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'borrar'),
            child: Text('Borrar', style: TextStyle(color: Colors.red.shade700)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'editar'),
            child: const Text('Editar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'editar') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LocalesEditarEvento(idEvento: ev.idEvento),
        ),
      );
      return;
    }
    if (action == 'borrar') {
      await _confirmarBorrado(ev);
    }
  }

  Future<void> _mostrarLayerVerificacion() async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => Scaffold(
          backgroundColor: ColoresLocales.acentoVioleta,
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        CupertinoIcons.xmark_circle_fill,
                        color: ColoresLocales.chipInactivo,
                      ),
                    ),
                  ),
                  Text(
                    'Debés ser local verificado para acceder a posicionamiento en cartelera',
                    style: GoogleFonts.baloo2(
                      color: ColoresLocales.chipInactivo,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Verificar tu cuenta te da más alcance, más confianza y mejores resultados.',
                    style: GoogleFonts.baloo2(
                      color: Colors.white.withOpacity(0.92),
                      fontSize: 15,
                    ),
                  ),
                  Spacer(),
                  Center(
                    child: Text(
                      'Local Verificado: 15usd/mes',
                      style: GoogleFonts.baloo2(
                        color: const Color(0xFFFFD775),
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(
                          context,
                          '/administrar_subscripciones',
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFFD9B44A),
                        foregroundColor: ColoresLocales.acentoVioleta,
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50),
                        ),
                      ),
                      child: Text(
                        'Verificar mi cuenta ahora!',
                        style: GoogleFonts.baloo2(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
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

  void _mostrarError(String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Atención'),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _fmtFecha(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/'
        '${d.year}';
  }

  String _fmtFechaHora(DateTime? d) {
    if (d == null) return '—';
    const dias = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dias[d.weekday % 7]} ${two(d.day)}/${two(d.month)} · ${two(d.hour)}:${two(d.minute)} hs';
  }

  String _etiquetaDiasRestantes(int dias, {required bool pasado}) {
    if (pasado) return 'Finalizado';
    if (dias == 0) return 'Último día';
    if (dias == 1) return '1 día restante';
    return '$dias días restantes';
  }

  Color _colorUrgencia(int dias, {required bool pasado, Color? base}) {
    if (pasado) return const Color(0xFF6B7280);
    final b = base ?? ColoresLocales.acentoVioleta;
    // En posicionamiento usamos el color de jerarquía (evita confundir Top Ultra con alerta roja).
    if (base != null) return b;
    if (dias <= 1) return const Color(0xFFDC2626);
    if (dias <= 3) return ColoresLocales.jerarquiaTop;
    return b;
  }

  ({String label, Color color, IconData icon}) _jerarquiaMeta(
    String? jerarquia,
  ) =>
      IconosFeaturesLocales.metaJerarquia(jerarquia);

  Widget _chipJerarquia({
    required String text,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.baloo2(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipInfo({
    required String text,
    required IconData icon,
    Color? color,
  }) {
    final c = color ?? ColoresLocales.textoSecundarioOnFondoClaro;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: ColoresLocales.superficieElevada,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: c),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.baloo2(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: c,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaInfo({required IconData icono, required String texto}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(icono, size: 11, color: ColoresLocales.textoSecundarioOnFondoClaro),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              texto,
              style: GoogleFonts.baloo2(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: ColoresLocales.textoSecundarioOnFondoClaro,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineaPieClara({
    required String etiqueta,
    required String valor,
    Color? valorColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              '$etiqueta:',
              style: GoogleFonts.baloo2(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: ColoresLocales.textoSecundarioOnFondoClaro,
                height: 1.3,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: GoogleFonts.baloo2(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: valorColor ?? ColoresLocales.textoOnFondoClaro,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pieCardActiva(_EventoMini ev) {
    final jerarquia = _jerarquiaMeta(ev.jerarquia);
    final finPub = ev.finCartelera;
    final diasPub = ev.diasRestantesCartelera;
    final pubPasada = finPub != null && finPub.isBefore(DateTime.now());
    final finPosicion = ev.finPosicionamiento;
    final diasPosicion = ev.diasRestantesPosicionamiento;

    final valorFinPub = finPub == null
        ? 'Sin fecha definida'
        : '${_fmtFecha(finPub)} · ${_etiquetaDiasRestantes(diasPub, pasado: pubPasada)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
      decoration: BoxDecoration(
        color: ColoresLocales.fondoSuperficie.withValues(alpha: 0.9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _lineaPieClara(
            etiqueta: 'Jerarquía',
            valor: jerarquia.label,
            valorColor: jerarquia.color,
          ),
          if (ev.esPosicionado)
            _lineaPieClara(
              etiqueta: 'Hasta el',
              valor: ev.posicionamientoVencido
                  ? 'Finalizó el ${_fmtFecha(finPosicion)}'
                  : '${_fmtFecha(finPosicion)} · ${_etiquetaDiasRestantes(diasPosicion, pasado: false)}',
              valorColor: _colorUrgencia(
                diasPosicion,
                pasado: ev.posicionamientoVencido,
                base: jerarquia.color,
              ),
            ),
          _lineaPieClara(
            etiqueta: 'Fin de publicación',
            valor: valorFinPub,
            valorColor: _colorUrgencia(diasPub, pasado: pubPasada),
          ),
        ],
      ),
    );
  }

  Widget _pieCard({
    required String texto,
    required Color color,
    required IconData icono,
    String? encabezado,
    String? subtitulo,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Icon(icono, size: 15, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (encabezado != null)
                      Text(
                        encabezado,
                        style: GoogleFonts.baloo2(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: color,
                          height: 1.2,
                        ),
                      ),
                    if (encabezado != null) const SizedBox(height: 2),
                    Text(
                      texto,
                      style: GoogleFonts.baloo2(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: color,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (subtitulo != null) ...[
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Text(
                subtitulo,
                style: GoogleFonts.baloo2(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: color.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _flyerMini(_EventoMini ev) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 76,
            height: 76,
            child: ev.urlFlyer.isNotEmpty
                ? Image.network(
                    ev.urlFlyer,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: ColoresLocales.cardLavanda,
                      child: Icon(
                        CupertinoIcons.photo,
                        color: ColoresLocales.acentoVioleta,
                      ),
                    ),
                  )
                : Container(
                    color: ColoresLocales.cardLavanda,
                    child: Icon(
                      CupertinoIcons.photo,
                      color: ColoresLocales.acentoVioleta,
                    ),
                  ),
          ),
        ),
        Positioned(
          top: 5,
          right: 5,
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LocalesVistaPrevia(evento: ev.toMap()),
              ),
            ),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.38),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                CupertinoIcons.eye_fill,
                color: Colors.white,
                size: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _accionSecundaria({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool loading = false,
    Color? color,
  }) {
    final c = color ?? ColoresLocales.acentoVioleta;
    return Expanded(
      child: Material(
        color: ColoresLocales.superficieElevada,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 42,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                loading
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: c,
                        ),
                      )
                    : Icon(icon, color: c, size: 17),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: GoogleFonts.baloo2(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: c,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badgeVistas(int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ColoresLocales.superficieElevada,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.eye_fill,
            size: 12,
            color: ColoresLocales.acentoVioleta,
          ),
          const SizedBox(width: 4),
          Text(
            formatoMetricaCompacto(total),
            style: GoogleFonts.baloo2(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: ColoresLocales.acentoVioleta,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardActiva(_EventoMini ev, bool borrando) {
    final jerarquia = _jerarquiaMeta(ev.jerarquia);
    final modo = (ev.modoLista ?? '').toLowerCase();
    final tieneLista = modo == 'auto' || modo == 'manual';
    final esBasico = !ev.esPosicionado;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: ColoresLocales.decoracionCard(radius: 16, sinBorde: true),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _flyerMini(ev),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ev.titulo.isEmpty ? 'Evento sin título' : ev.titulo,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.baloo2(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w900,
                              color: ColoresLocales.textoOnFondoClaro,
                              height: 1.2,
                            ),
                          ),
                          if (ev.metricVisitas > 0) ...[
                            const SizedBox(height: 6),
                            _badgeVistas(ev.metricVisitas),
                          ],
                          const SizedBox(height: 8),
                          if (ev.fechaInicio != null)
                            _filaInfo(
                              icono: CupertinoIcons.calendar,
                              texto: 'Inicia el ${_fmtFechaHora(ev.fechaInicio)}',
                            ),
                          if (ev.fechaFin != null)
                            _filaInfo(
                              icono: CupertinoIcons.clock_fill,
                              texto: 'Termina el ${_fmtFechaHora(ev.fechaFin)}',
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (tieneLista || ev.promos.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (tieneLista)
                        _chipInfo(
                          text: modo == 'auto' ? 'Lista automática' : 'Lista manual',
                          icon: modo == 'auto'
                              ? CupertinoIcons.bolt_fill
                              : CupertinoIcons.hand_raised_fill,
                          color: modo == 'auto'
                              ? const Color(0xFF059669)
                              : const Color(0xFFD97706),
                        ),
                      if (tieneLista)
                        _chipInfo(
                          text: ev.cupoListaMax != null
                              ? '${ev.cupoListaUsados}/${ev.cupoListaMax} en lista'
                              : '${ev.cupoListaUsados} en lista',
                          icon: CupertinoIcons.person_3_fill,
                          color: ev.cupoListaMax != null &&
                                  ev.cupoListaUsados >= (ev.cupoListaMax ?? 0)
                              ? const Color(0xFFDC2626)
                              : ColoresLocales.acentoVioleta,
                        ),
                      if (ev.promos.isNotEmpty)
                        _chipInfo(
                          text: '${ev.promos.length} promo${ev.promos.length == 1 ? '' : 's'}',
                          icon: CupertinoIcons.tag_fill,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: FilledButton.icon(
                        onPressed: () => _abrirPosicionamiento(ev),
                        icon: Icon(
                          esBasico ? CupertinoIcons.rocket_fill : jerarquia.icon,
                          size: 15,
                        ),
                        label: Text(
                          esBasico ? 'Posicionar' : jerarquia.label,
                          style: GoogleFonts.baloo2(
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          elevation: 0,
                          backgroundColor: esBasico
                              ? const Color(0xFFD9B44A)
                              : jerarquia.color,
                          // Violeta marca fuerte: en dark mode `acentoVioleta` es
                          // claro (#C4B5FD) y no se lee sobre el fondo mostaza.
                          foregroundColor: esBasico
                              ? ColoresLocales.acentoVioletaMarca
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11),
                          ),
                          minimumSize: const Size.fromHeight(42),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _accionSecundaria(
                      icon: CupertinoIcons.list_bullet,
                      label: 'Lista',
                      onTap: () => Navigator.pushNamed(context, '/validar'),
                    ),
                    const SizedBox(width: 8),
                    _accionSecundaria(
                      icon: CupertinoIcons.eye_slash_fill,
                      label: 'Quitar',
                      color: const Color(0xFFDC2626),
                      loading: _cancelando.contains(ev.idEvento),
                      onTap: _cancelando.contains(ev.idEvento)
                          ? null
                          : () => _confirmarCancelado(ev),
                    ),
                    const SizedBox(width: 8),
                    _accionSecundaria(
                      icon: CupertinoIcons.pencil,
                      label: 'Editar',
                      loading: borrando,
                      onTap: borrando ? null : () => _mostrarModalEditarBorrar(ev),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _pieCardActiva(ev),
        ],
      ),
    );
  }

  Widget _buildCardHistorial(_EventoMini ev) {
    final jerarquia = _jerarquiaMeta(ev.jerarquia);
    final modo = (ev.modoLista ?? '').toLowerCase();
    final tieneLista = modo == 'auto' || modo == 'manual';
    final cancelado = ev.estadoPublicacion == 'cancelado';
    final colorPie = cancelado
        ? const Color(0xFFDC2626)
        : const Color(0xFF6B7280);

    final textoPie = cancelado
        ? 'Despublicado · Finalizó el ${_fmtFecha(ev.fechaFin)}'
        : 'Finalizó el ${_fmtFecha(ev.fechaFin)}';

    final subtituloPie = ev.esPosicionado
        ? 'Posicionamiento (${jerarquia.label}) finalizó el ${_fmtFecha(ev.finPosicionamiento)}'
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: ColoresLocales.decoracionCard(radius: 18, sinBorde: true),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 76,
                    height: 76,
                    child: ev.urlFlyer.isNotEmpty
                        ? Image.network(
                            ev.urlFlyer,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: ColoresLocales.cardLavanda,
                              child: Icon(
                                CupertinoIcons.photo,
                                color: ColoresLocales.acentoVioleta,
                              ),
                            ),
                          )
                        : Container(
                            color: ColoresLocales.cardLavanda,
                            child: Icon(
                              CupertinoIcons.photo,
                              color: ColoresLocales.acentoVioleta,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ev.titulo.isEmpty ? 'Evento sin título' : ev.titulo,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.baloo2(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: ColoresLocales.textoOnFondoClaro,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _chipJerarquia(
                            text: jerarquia.label,
                            icon: jerarquia.icon,
                            color: jerarquia.color,
                          ),
                          _chipInfo(
                            text: cancelado ? 'Despublicado' : 'Finalizado',
                            icon: cancelado
                                ? CupertinoIcons.eye_slash_fill
                                : CupertinoIcons.checkmark_circle_fill,
                            color: colorPie,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (ev.fechaInicio != null)
                        _filaInfo(
                          icono: CupertinoIcons.calendar,
                          texto: 'Inició el ${_fmtFechaHora(ev.fechaInicio)}',
                        ),
                      if (ev.fechaFin != null)
                        _filaInfo(
                          icono: CupertinoIcons.clock_fill,
                          texto: 'Terminó el ${_fmtFechaHora(ev.fechaFin)}',
                        ),
                      if (tieneLista || ev.promos.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (tieneLista)
                              _chipInfo(
                                text: modo == 'auto' ? 'Lista automática' : 'Lista manual',
                                icon: modo == 'auto'
                                    ? CupertinoIcons.bolt_fill
                                    : CupertinoIcons.hand_raised_fill,
                              ),
                            if (ev.promos.isNotEmpty)
                              _chipInfo(
                                text: '${ev.promos.length} promo${ev.promos.length == 1 ? '' : 's'}',
                                icon: CupertinoIcons.tag_fill,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          _pieCard(
            icono: cancelado
                ? CupertinoIcons.eye_slash_fill
                : CupertinoIcons.checkmark_circle_fill,
            color: colorPie,
            texto: textoPie,
            subtitulo: subtituloPie,
          ),
        ],
      ),
    );
  }

  Future<void> _abrirPosicionamiento(_EventoMini ev) async {
    // Los créditos de posicionamiento no dependen de verificación:
    // si tiene cupos disponibles, puede posicionar igual.
    if (NavegacionPosicionamiento.estaRegistrado) {
      NavegacionPosicionamiento.irAEvento(ev.idEvento);
      if (mounted) {
        Navigator.of(context).maybePop();
      }
      return;
    }

    final esBasico =
        (ev.jerarquia == null ||
            ev.jerarquia == 'gratis' ||
            ev.jerarquia == 'normal');
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocalesPosicionamiento(tabInicial: esBasico ? 1 : 0),
      ),
    );
    if (!mounted) return;
    _cargarEventos();
  }

  Widget _emptyEventos(bool mostrandoActivos) {
    return ListView(
      physics: AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 30, 16, 24),
      children: [
        Icon(
          CupertinoIcons.calendar_badge_plus,
          size: 64,
          color: ColoresLocales.acentoVioleta.withOpacity(0.4),
        ),
        SizedBox(height: 14),
        Text(
          mostrandoActivos
              ? 'Todavía no publicaste eventos'
              : 'No hay eventos finalizados',
          textAlign: TextAlign.center,
          style: GoogleFonts.baloo2(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: ColoresLocales.textoOnFondoClaro,
          ),
        ),
        if (mostrandoActivos) ...[
          SizedBox(height: 16),
          Center(
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/crear_evento'),
              icon: Icon(CupertinoIcons.add_circled_solid, size: 18),
              label: Text(
                'Crear primer evento',
                style: GoogleFonts.baloo2(fontWeight: FontWeight.w900),
              ),
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
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final mostrandoActivos = _filtro == 'activos';
    final eventos = mostrandoActivos ? _eventosActivos : _eventosHistorial;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: ColoresLocales.decoracionFondoPantalla,
            ),
          ),
          SafeArea(
            bottom: false,
            child: _cargando
                ? const SkeletonListaEventos()
                : _error != null
                ? EstadoErrorLocales(
                    mensaje: _error!,
                    onReintentar: _cargarEventos,
                  )
                : Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
                        child: Row(
                          children: [
                            if (Navigator.of(context).canPop())
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: () => Navigator.of(context).pop(),
                                child: Icon(
                                  CupertinoIcons.chevron_back,
                                  color: ColoresLocales.acentoVioleta,
                                ),
                              ),
                            Expanded(
                              child: Text(
                                'Mis eventos',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.baloo2(
                                  fontWeight: FontWeight.w900,
                                  color: ColoresLocales.acentoVioleta,
                                  fontSize: 24,
                                ),
                              ),
                            ),
                            SizedBox(width: 40),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: ColoresLocales.cardLavanda,
                            borderRadius: BorderRadius.circular(50),
                          ),
                          padding: const EdgeInsets.all(3),
                          child: Row(
                            children: [
                              _tabFiltro(
                                'activos',
                                'Activos',
                                _eventosActivos.length,
                              ),
                              _tabFiltro(
                                'historial',
                                'Historial',
                                _eventosHistorial.length,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (eventos.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              mostrandoActivos
                                  ? '${eventos.length} evento${eventos.length == 1 ? '' : 's'} publicado${eventos.length == 1 ? '' : 's'}'
                                  : '${eventos.length} en historial',
                              style: GoogleFonts.baloo2(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: ColoresLocales.textoSecundarioOnFondoClaro,
                              ),
                            ),
                          ),
                        ),
                      Expanded(
                        child: RefreshIndicator(
                          color: ColoresLocales.acentoVioleta,
                          onRefresh: _cargarEventos,
                          child: eventos.isEmpty
                              ? _emptyEventos(mostrandoActivos)
                              : ListView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    24,
                                  ),
                                  itemCount: eventos.length,
                                  itemBuilder: (context, i) {
                                    final ev = eventos[i];
                                    final borrando = _borrando.contains(
                                      ev.idEvento,
                                    );
                                    if (!mostrandoActivos) {
                                      return _buildCardHistorial(ev);
                                    }
                                    return _buildCardActiva(ev, borrando);
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tabFiltro(String value, String label, int count) {
    final activo = _filtro == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filtro = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: activo ? ColoresLocales.acentoVioleta : Colors.transparent,
            borderRadius: BorderRadius.circular(50),
          ),
          alignment: Alignment.center,
          child: Text(
            count > 0 ? '$label ($count)' : label,
            style: GoogleFonts.baloo2(
              fontWeight: FontWeight.w900,
              fontSize: 13,
              color: activo
                  ? ColoresLocales.superficie
                  : ColoresLocales.textoSecundarioOnFondoClaro,
            ),
          ),
        ),
      ),
    );
  }
}

class _EventoMini {
  final String idEvento;
  final String idLocal;
  final String titulo;
  final String descripcion;
  final String urlFlyer;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;
  final DateTime? fechaFinPublicacion;
  final DateTime? fechaFinJerarquia;
  final String? modoLista;
  final int? cupoListaMax;
  final int cupoListaUsados;
  final int? edadMinima;
  final String? jerarquia;
  final bool tienePromo;
  final String? urlCompraEntradas;
  final List<_PromoResumen> promos;
  final String estadoPublicacion;
  final int metricVisitas;

  _EventoMini({
    required this.idEvento,
    required this.idLocal,
    required this.titulo,
    required this.descripcion,
    required this.urlFlyer,
    required this.fechaInicio,
    required this.fechaFin,
    required this.fechaFinPublicacion,
    required this.fechaFinJerarquia,
    required this.modoLista,
    required this.cupoListaMax,
    required this.cupoListaUsados,
    this.edadMinima,
    this.jerarquia,
    required this.tienePromo,
    required this.urlCompraEntradas,
    required this.promos,
    this.estadoPublicacion = 'publicado',
    this.metricVisitas = 0,
  });

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();
    if (v is String && v.trim().isNotEmpty) {
      return DateTime.tryParse(v)?.toLocal();
    }
    return DateTime.tryParse(v.toString())?.toLocal();
  }

  bool get esPosicionado {
    const niveles = {'recomendado_fernecito', 'top', 'top_ultra'};
    return niveles.contains((jerarquia ?? '').toLowerCase());
  }

  DateTime? get finCartelera => fechaFinPublicacion ?? fechaFin;

  bool get eventoFinalizado {
    final fin = fechaFin;
    if (fin == null) return false;
    return fin.isBefore(DateTime.now());
  }

  int get diasRestantesEvento {
    if (fechaFin == null) return 0;
    return fechaFin!.difference(DateTime.now()).inDays.clamp(0, 999);
  }

  int get diasRestantesCartelera {
    final fin = finCartelera;
    if (fin == null) return 0;
    return fin.difference(DateTime.now()).inDays.clamp(0, 999);
  }

  DateTime? get finPosicionamiento => fechaFinJerarquia ?? fechaFin;

  bool get posicionamientoVencido {
    final fin = finPosicionamiento;
    if (fin == null) return false;
    return fin.isBefore(DateTime.now());
  }

  bool get posicionLimitadaPorEvento {
    if (fechaFinJerarquia == null || fechaFin == null) return false;
    return !fechaFinJerarquia!.isAfter(
      fechaFin!.add(const Duration(minutes: 1)),
    );
  }

  int? get diasBoostRegla => switch ((jerarquia ?? '').toLowerCase()) {
    'recomendado_fernecito' => 15,
    'top' => 10,
    'top_ultra' => 10,
    _ => null,
  };

  int get diasRestantesPosicionamiento {
    final fin = finPosicionamiento;
    if (fin == null) return 0;
    return fin.difference(DateTime.now()).inDays.clamp(0, 999);
  }

  factory _EventoMini.fromMap(Map<String, dynamic> m) {
    final promosRaw = (m['promociones'] as List?) ?? const [];
    final promos = promosRaw
        .whereType<Map>()
        .map(
          (p) => _PromoResumen(
            titulo: (p['titulo_promocion'] as String?)?.trim() ?? '',
          ),
        )
        .where((p) => p.titulo.isNotEmpty)
        .toList();

    return _EventoMini(
      idEvento: m['id_evento'].toString(),
      idLocal: m['id_local'].toString(),
      titulo: (m['titulo_evento'] as String?) ?? '',
      descripcion: (m['descripcion_evento'] as String?) ?? '',
      urlFlyer: (m['url_flyer'] as String?) ?? '',
      fechaInicio: _parseDate(m['fecha_inicio']),
      fechaFin: _parseDate(m['fecha_fin']),
      fechaFinPublicacion: _parseDate(
        m['fecha_fin_publicacion'] ?? m['fecha_fin'],
      ),
      fechaFinJerarquia: _parseDate(m['fecha_fin_jerarquia']),
      modoLista: (m['modo_lista'] as String?),
      cupoListaMax: (m['cupo_lista_max'] as num?)?.toInt(),
      cupoListaUsados: (m['cupo_lista_usados'] as num?)?.toInt() ?? 0,
      edadMinima: (m['edad_minima'] as num?)?.toInt(),
      jerarquia: (m['jerarquia'] as String?),
      tienePromo: (m['tiene_promo'] as bool?) ?? false,
      urlCompraEntradas: (m['url_compra_entradas'] as String?),
      promos: promos,
      estadoPublicacion: (m['estado_publicacion'] as String?) ?? 'publicado',
      metricVisitas: (m['metric_visitas'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'id_evento': idEvento,
    'id_local': idLocal,
    'titulo_evento': titulo,
    'descripcion_evento': descripcion,
    'url_flyer': urlFlyer,
    'fecha_inicio': fechaInicio?.toIso8601String(),
    'fecha_fin': fechaFin?.toIso8601String(),
    'fecha_fin_publicacion': fechaFinPublicacion?.toIso8601String(),
    'fecha_fin_jerarquia': fechaFinJerarquia?.toIso8601String(),
    'modo_lista': modoLista,
    'cupo_lista_max': cupoListaMax,
    'cupo_lista_usados': cupoListaUsados,
    'edad_minima': edadMinima,
    'jerarquia': jerarquia ?? 'gratis',
    'tiene_promo': tienePromo,
    'url_compra_entradas': urlCompraEntradas,
    'promociones': promos.map((p) => {'titulo_promocion': p.titulo}).toList(),
  };
}

class _PromoResumen {
  final String titulo;
  const _PromoResumen({required this.titulo});
}
