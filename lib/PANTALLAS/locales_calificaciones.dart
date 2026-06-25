/// Calificaciones del local (app locales).
///
/// Muestra:
///  - Header con promedio grande + estrellas visuales + cantidad
///  - Chips de filtro: Todas (default, orden fecha desc) + 5★ / 4★ / 3★ / 2★ / 1★
///  - Lista de reseñas con avatar/username/fecha/estrellas/comentario
///
/// Lectura directa desde Supabase (RLS SELECT abierta a authenticated):
///   reviews_locales JOIN perfiles_usuarios filtrando id_local = mi id.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants.dart';
import '../widgets/tema_locales_scope.dart';
import '../core/supabase_client.dart';

const Color _doradoEstrellaCalificaciones = Color(0xFFFFC107);

class LocalesCalificaciones extends StatefulWidget {
  const LocalesCalificaciones({super.key});

  @override
  State<LocalesCalificaciones> createState() => _LocalesCalificacionesState();
}

class _LocalesCalificacionesState extends State<LocalesCalificaciones> {
  bool _cargando = true;
  String? _errorMsg;
  int _filtroEstrellas = 0; // 0 = todas
  double? _promedio;
  int _cantidad = 0;
  List<Map<String, dynamic>> _resenas = [];
  bool _mostrarCalificaciones = true; // switch: visible en perfil público
  bool _guardandoSwitch = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    setState(() {
      _cargando = true;
      _errorMsg = null;
    });
    try {
      final sb = ServicioSupabase().cliente;
      final localId = sb.auth.currentUser?.id;
      if (localId == null) {
        if (mounted) {
          setState(() {
            _cargando = false;
            _errorMsg = 'No hay sesión activa.';
          });
        }
        return;
      }

      // 1. Promedio + cantidad desde perfiles_locales (lo recalcula el RPC al publicar)
      try {
        final perfil = await sb
            .from('perfiles_locales')
            .select(
                'calificacion_promedio, calificacion_cantidad, mostrar_calificaciones')
            .eq('id', localId)
            .maybeSingle();
        if (perfil != null) {
          final p = perfil['calificacion_promedio'];
          _promedio = p is num
              ? p.toDouble()
              : double.tryParse(p?.toString() ?? '');
          final c = perfil['calificacion_cantidad'];
          _cantidad = c is int
              ? c
              : (c != null ? int.tryParse(c.toString()) ?? 0 : 0);
          _mostrarCalificaciones = perfil['mostrar_calificaciones'] != false;
        }
      } catch (e) {
        debugPrint('⚠️ Calificaciones header: $e');
      }

      // 2. Reseñas + perfil del usuario que reseñó (JOIN embebido)
      final res = await sb
          .from('reviews_locales')
          .select(
              'id_review, id_usuario, estrellas, comentario, fecha_creacion, '
              'perfiles_usuarios:id_usuario(username, nombre, foto_perfil_url)')
          .eq('id_local', localId)
          .order('fecha_creacion', ascending: false);
      final lista = List<Map<String, dynamic>>.from(res as List);

      if (!mounted) return;
      setState(() {
        _resenas = lista;
        _cargando = false;
      });
    } catch (e, st) {
      debugPrint('⚠️ Calificaciones cargar: $e\n$st');
      if (!mounted) return;
      setState(() {
        _errorMsg = e.toString();
        _cargando = false;
      });
    }
  }

  /// Activa/desactiva la visibilidad pública de la calificación.
  Future<void> _toggleMostrar(bool valor) async {
    final sb = ServicioSupabase().cliente;
    final localId = sb.auth.currentUser?.id;
    if (localId == null || _guardandoSwitch) return;
    final anterior = _mostrarCalificaciones;
    setState(() {
      _mostrarCalificaciones = valor;
      _guardandoSwitch = true;
    });
    try {
      await sb
          .from('perfiles_locales')
          .update({'mostrar_calificaciones': valor}).eq('id', localId);
    } catch (e) {
      debugPrint('⚠️ toggle mostrar_calificaciones: $e');
      if (mounted) setState(() => _mostrarCalificaciones = anterior); // revertir
    } finally {
      if (mounted) setState(() => _guardandoSwitch = false);
    }
  }

  /// Filtro por estrellas en cliente.
  List<Map<String, dynamic>> get _resenasFiltradas {
    if (_filtroEstrellas == 0) return _resenas;
    return _resenas.where((r) {
      final e = r['estrellas'];
      final n = e is int ? e : int.tryParse(e?.toString() ?? '') ?? 0;
      return n == _filtroEstrellas;
    }).toList();
  }

  Map<int, int> get _conteoPorEstrella {
    final m = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final r in _resenas) {
      final e = r['estrellas'];
      final n = e is int ? e : int.tryParse(e?.toString() ?? '') ?? 0;
      if (n >= 1 && n <= 5) m[n] = (m[n] ?? 0) + 1;
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return Scaffold(
      backgroundColor: ColoresLocales.fondoClaro,
      appBar: _buildAppBar(),
      body: _cargando
          ? Center(
              child: CupertinoActivityIndicator(
                radius: 14,
                color: ColoresLocales.acentoVioleta,
              ),
            )
          : _errorMsg != null
              ? _buildError()
              : RefreshIndicator(
                  color: ColoresLocales.acentoVioleta,
                  backgroundColor: ColoresLocales.superficie,
                  onRefresh: _cargar,
                  child: ListView(
                    physics: AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    children: [
                      _buildHeaderPromedio(),
                      _buildSwitchMostrar(),
                      _buildFiltrosEstrellas(),
                      SizedBox(height: 6),
                      ..._buildListaResenas(),
                      SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: ColoresLocales.superficie,
      elevation: 0,
      surfaceTintColor: ColoresLocales.chipInactivo,
      leading: IconButton(
        icon: Icon(CupertinoIcons.chevron_back,
            color: ColoresLocales.acentoVioleta),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(
        'Calificaciones',
        style: GoogleFonts.baloo2(
          color: ColoresLocales.acentoVioleta,
          fontWeight: FontWeight.w900,
          fontSize: 19,
        ),
      ),
      centerTitle: true,
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.exclamationmark_triangle,
                size: 48, color: ColoresLocales.acentoVioleta),
            SizedBox(height: 14),
            Text(
              'No pudimos cargar las calificaciones',
              textAlign: TextAlign.center,
              style: GoogleFonts.baloo2(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: ColoresLocales.textoOnFondoClaro,
              ),
            ),
            SizedBox(height: 6),
            Text(
              _errorMsg ?? '',
              textAlign: TextAlign.center,
              style: GoogleFonts.baloo2(
                fontSize: 12,
                color: ColoresLocales.textoSecundarioOnFondoClaro,
              ),
            ),
            SizedBox(height: 16),
            CupertinoButton(
              color: ColoresLocales.acentoVioleta,
              onPressed: _cargar,
              child: Text(
                'Reintentar',
                style: GoogleFonts.baloo2(
                  color: ColoresLocales.chipInactivo,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderPromedio() {
    final hayDatos = _promedio != null && _cantidad > 0;
    return Container(
      margin: EdgeInsets.fromLTRB(20, 12, 20, 16),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ColoresLocales.cardLavanda, ColoresLocales.cardAlt],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: ColoresLocales.acentoVioleta.withOpacity(0.28),
        ),
        boxShadow: [
          BoxShadow(
            color: ColoresLocales.acentoVioleta.withOpacity(0.14),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: hayDatos
          ? Column(
              children: [
                Text(
                  'Calificación de tu local:',
                  style: GoogleFonts.baloo2(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: ColoresLocales.textoOnFondoClaro,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  _promedio!.toStringAsFixed(1),
                  style: GoogleFonts.baloo2(
                    fontSize: 56,
                    fontWeight: FontWeight.w900,
                    color: ColoresLocales.acentoVioleta,
                    letterSpacing: -1.5,
                    height: 1.0,
                  ),
                ),
                SizedBox(height: 6),
                _EstrellasVisuales(valor: _promedio!, size: 22),
                SizedBox(height: 8),
                Text(
                  '$_cantidad reseña${_cantidad == 1 ? '' : 's'}',
                  style: GoogleFonts.baloo2(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ColoresLocales.textoSecundarioOnFondoClaro,
                  ),
                ),
              ],
            )
          : Column(
              children: [
                Icon(CupertinoIcons.star,
                    size: 48,
                    color: _doradoEstrellaCalificaciones.withOpacity(0.55)),
                SizedBox(height: 10),
                Text(
                  'Sin calificaciones aún',
                  style: GoogleFonts.baloo2(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: ColoresLocales.textoOnFondoClaro,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Cuando tus clientes asistan y dejen reseñas las vas a ver acá.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.baloo2(
                    fontSize: 12.5,
                    color: ColoresLocales.textoSecundarioOnFondoClaro,
                    height: 1.4,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSwitchMostrar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      decoration: BoxDecoration(
        color: ColoresLocales.superficie,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ColoresLocales.acentoVioleta.withOpacity(0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _mostrarCalificaciones
                ? CupertinoIcons.eye_fill
                : CupertinoIcons.eye_slash_fill,
            size: 20,
            color: ColoresLocales.acentoVioleta,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mostrar mi calificación',
                  style: GoogleFonts.baloo2(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: ColoresLocales.textoOnFondoClaro,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _mostrarCalificaciones
                      ? 'Visible en tu perfil público.'
                      : 'Oculta: los usuarios no la verán.',
                  style: GoogleFonts.baloo2(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: ColoresLocales.textoSecundarioOnFondoClaro,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          CupertinoSwitch(
            value: _mostrarCalificaciones,
            activeTrackColor: ColoresLocales.acentoVioleta,
            onChanged: _guardandoSwitch ? null : _toggleMostrar,
          ),
        ],
      ),
    );
  }

  Widget _buildFiltrosEstrellas() {
    final conteo = _conteoPorEstrella;
    final chips = <Widget>[
      _ChipFiltro(
        seleccionado: _filtroEstrellas == 0,
        onTap: () => setState(() => _filtroEstrellas = 0),
        child: Text(
          'Todas (${_resenas.length})',
          style: GoogleFonts.baloo2(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: _filtroEstrellas == 0
                ? ColoresLocales.chipInactivo
                : ColoresLocales.textoOnFondoClaro,
          ),
        ),
      ),
      for (final estrella in [5, 4, 3, 2, 1])
        _ChipFiltro(
          seleccionado: _filtroEstrellas == estrella,
          onTap: () => setState(() => _filtroEstrellas = estrella),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$estrella',
                style: GoogleFonts.baloo2(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: _filtroEstrellas == estrella
                      ? ColoresLocales.chipInactivo
                      : ColoresLocales.textoOnFondoClaro,
                ),
              ),
              SizedBox(width: 3),
              Icon(
                CupertinoIcons.star_fill,
                size: 11,
                color: _filtroEstrellas == estrella
                    ? ColoresLocales.chipInactivo
                    : _doradoEstrellaCalificaciones,
              ),
              SizedBox(width: 4),
              Text(
                '(${conteo[estrella] ?? 0})',
                style: GoogleFonts.baloo2(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _filtroEstrellas == estrella
                      ? Colors.white.withOpacity(0.85)
                      : ColoresLocales.textoSecundarioOnFondoClaro,
                ),
              ),
            ],
          ),
        ),
    ];

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 20),
        itemCount: chips.length,
        separatorBuilder: (_, __) => SizedBox(width: 8),
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }

  List<Widget> _buildListaResenas() {
    final lista = _resenasFiltradas;
    if (lista.isEmpty) {
      return [
        Padding(
          padding: EdgeInsets.fromLTRB(20, 32, 20, 32),
          child: Column(
            children: [
              Icon(CupertinoIcons.bubble_left,
                  size: 44,
                  color: ColoresLocales.acentoVioleta.withOpacity(0.35)),
              SizedBox(height: 10),
              Text(
                _filtroEstrellas == 0
                    ? 'Todavía no hay reseñas'
                    : 'Sin reseñas de $_filtroEstrellas estrella${_filtroEstrellas == 1 ? '' : 's'}',
                style: GoogleFonts.baloo2(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: ColoresLocales.textoOnFondoClaro,
                ),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      for (final r in lista)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
          child: _CardResena(resena: r),
        ),
    ];
  }
}

// ============================================================================
// Sub-widgets
// ============================================================================

class _ChipFiltro extends StatelessWidget {
  final bool seleccionado;
  final VoidCallback onTap;
  final Widget child;
  const _ChipFiltro({
    required this.seleccionado,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: seleccionado
              ? ColoresLocales.acentoVioleta
              : ColoresLocales.chipInactivo,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: seleccionado
                ? ColoresLocales.acentoVioleta
                : ColoresLocales.acentoVioleta.withOpacity(0.22),
          ),
          boxShadow: seleccionado
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: child,
      ),
    );
  }
}

class _EstrellasVisuales extends StatelessWidget {
  final double valor;
  final double size;
  const _EstrellasVisuales({required this.valor, this.size = 16});

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final pos = i + 1;
        IconData icon;
        if (valor >= pos) {
          icon = CupertinoIcons.star_fill;
        } else if (valor >= pos - 0.5) {
          icon = CupertinoIcons.star_lefthalf_fill;
        } else {
          icon = CupertinoIcons.star;
        }
        return Padding(
          padding: EdgeInsets.only(right: i == 4 ? 0 : 3),
          child: Icon(
            icon,
            size: size,
            color: _doradoEstrellaCalificaciones,
          ),
        );
      }),
    );
  }
}

class _CardResena extends StatelessWidget {
  final Map<String, dynamic> resena;
  const _CardResena({required this.resena});

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final perfil = resena['perfiles_usuarios'];
    final perfilMap = perfil is Map ? Map<String, dynamic>.from(perfil) : null;
    final username = perfilMap?['username']?.toString() ?? 'usuario';
    final fotoPath = perfilMap?['foto_perfil_url']?.toString();
    final fotoUrl = (fotoPath == null || fotoPath.isEmpty)
        ? ''
        : (fotoPath.startsWith('http')
            ? fotoPath
            : ServicioSupabase()
                .cliente
                .storage
                .from('avatars')
                .getPublicUrl(fotoPath));
    final estrellas = (resena['estrellas'] as int?) ??
        int.tryParse(resena['estrellas']?.toString() ?? '') ??
        0;
    final comentario = resena['comentario']?.toString() ?? '';
    final fecha = _formatearFecha(resena['fecha_creacion']?.toString());

    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ColoresLocales.superficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ColoresLocales.acentoVioleta.withOpacity(0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ColoresLocales.cardLavanda,
                  border: Border.all(
                    color: ColoresLocales.acentoVioleta.withOpacity(0.2),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: fotoUrl.isEmpty
                    ? Icon(CupertinoIcons.person_fill,
                        size: 20,
                        color: ColoresLocales.acentoVioleta.withOpacity(0.55))
                    : Image.network(
                        fotoUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (ctx, child, progress) =>
                            progress == null
                                ? child
                                : ColoredBox(
                                    color: ColoresLocales.cardLavanda,
                                  ),
                        errorBuilder: (_, __, ___) => Icon(
                          CupertinoIcons.person_fill,
                          size: 20,
                          color: ColoresLocales.acentoVioleta.withOpacity(0.55),
                        ),
                      ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '@$username',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.baloo2(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: ColoresLocales.textoOnFondoClaro,
                      ),
                    ),
                    if (fecha.isNotEmpty)
                      Text(
                        fecha,
                        style: GoogleFonts.baloo2(
                          fontSize: 11,
                          color: ColoresLocales.textoSecundarioOnFondoClaro,
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) {
                  return Padding(
                    padding: EdgeInsets.only(left: 1.5),
                    child: Icon(
                      i < estrellas
                          ? CupertinoIcons.star_fill
                          : CupertinoIcons.star,
                      size: 12,
                      color: i < estrellas
                          ? _doradoEstrellaCalificaciones
                          : ColoresLocales.textoSecundarioOnFondoClaro
                              .withOpacity(0.35),
                    ),
                  );
                }),
              ),
            ],
          ),
          if (comentario.trim().isNotEmpty) ...[
            SizedBox(height: 10),
            Text(
              comentario,
              style: GoogleFonts.baloo2(
                fontSize: 13.5,
                color: ColoresLocales.textoOnFondoClaro,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatearFecha(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final ahora = DateTime.now();
      final diff = ahora.difference(dt);
      if (diff.inDays >= 30) {
        const meses = [
          'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
          'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
        ];
        return '${dt.day} ${meses[dt.month - 1]} ${dt.year}';
      }
      if (diff.inDays >= 1) return 'hace ${diff.inDays}d';
      if (diff.inHours >= 1) return 'hace ${diff.inHours}h';
      if (diff.inMinutes >= 1) return 'hace ${diff.inMinutes}m';
      return 'recién';
    } catch (_) {
      return '';
    }
  }
}
