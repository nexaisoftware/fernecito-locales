library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants.dart';
import '../core/colores_staff.dart';
import '../core/modo_app_locales.dart';
import '../widgets/scaffold_staff.dart';
import '../widgets/tema_locales_scope.dart';
import '../core/servicio_edges_eventos.dart';
import '../core/supabase_client.dart';
import 'locales_qr_validar.dart';
import 'locales_qr_invitacion.dart';
import 'locales_perfil_clientes.dart';
import '../core/evento_activo.dart';
import '../core/permisos_staff_validar.dart';

// ─── Listas y Pases (pantalla unificada) ─────────────────────────────────────

class LocalesValidar extends StatefulWidget {
  /// Si se pasa, la pantalla puede pre-abrir acciones de ese evento al entrar.
  final String? idEventoInicial;
  /// 'ver' (default) | 'aceptar' — pre-abrir ver aceptados o pendientes.
  final String modoInicial;
  /// Staff: UUID del local donde opera (distinto de auth.uid).
  final String? idLocalOperando;
  /// Permisos del staff. null = es owner (acceso total).
  final PermisosStaffValidar? permisosStaff;

  const LocalesValidar({
    super.key,
    this.idEventoInicial,
    this.modoInicial = 'ver',
    this.idLocalOperando,
    this.permisosStaff,
  });

  @override
  State<LocalesValidar> createState() => _LocalesValidarState();
}

class _LocalesValidarState extends State<LocalesValidar> {
  bool _cargando = true;
  String? _error;

  List<_EventoLista> _eventos = [];

  /// Mapa idEvento → tokens del evento.
  Map<String, List<_TokenAsist>> _tokensPorEvento = {};

  /// Mapa uid → perfil mínimo del usuario (para resolver miembros de squads).
  Map<String, _PerfilMini> _perfilesMiembros = {};

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  // ── Carga de datos ──────────────────────────────────────────────────────────

  Future<void> _cargarDatos() async {
    if (!mounted) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final uid = widget.idLocalOperando ?? ServicioSupabase().usuarioActual?.id;
      if (uid == null) {
        setState(() {
          _cargando = false;
          _error = 'No encontramos tu sesión activa.';
        });
        return;
      }

      // Carga eventos publicados con lista activa.
      final evData = await ServicioSupabase().cliente
          .from('eventos')
          .select(
            'id_evento, titulo_evento, modo_lista, cupo_lista_max, cupo_lista_usados, fecha_inicio, fecha_fin',
          )
          .eq('id_local', uid)
          .eq('estado_publicacion', 'publicado')
          .inFilter('modo_lista', ['auto', 'manual'])
          .gte('fecha_fin', DateTime.now().toUtc().toIso8601String())
          .order('fecha_inicio', ascending: true);

      final eventos = (evData as List)
          .cast<Map<String, dynamic>>()
          .map(_EventoLista.fromMap)
          .toList();

      // Carga todos los tokens de esos eventos en una sola query.
      final Map<String, List<_TokenAsist>> mapaTokens = {};
      if (eventos.isNotEmpty) {
        final ids = eventos.map((e) => e.idEvento).toList();
        final tokData = await ServicioSupabase().cliente
            .from('tokens_asistencia')
            .select(
              'id_token, id_evento, id_usuario, id_reserva_grupal, codigo_puerta, '
              'estado_token, fecha_creacion, snapshot_squad, '
              'perfiles_usuarios:id_usuario(username, nombre, edad, foto_perfil_url)',
            )
            .inFilter('id_evento', ids)
            .order('fecha_creacion', ascending: false);

        for (final raw in (tokData as List).cast<Map<String, dynamic>>()) {
          final t = _TokenAsist.fromMap(raw);
          (mapaTokens[t.idEvento] ??= []).add(t);
        }
      }

      // Perfiles: solicitantes de cada token + miembros de squad (batch).
      // El JOIN embebido puede venir vacío por RLS; este fetch es el respaldo.
      final uidsPerfiles = <String>{};
      for (final lista in mapaTokens.values) {
        for (final t in lista) {
          if (t.idUsuario.isNotEmpty) uidsPerfiles.add(t.idUsuario);
          final miembros = t.snapshotSquad?['miembros'];
          if (miembros is List) {
            for (final m in miembros) {
              final s = m?.toString();
              if (s != null && s.isNotEmpty) uidsPerfiles.add(s);
            }
          }
        }
      }
      final Map<String, _PerfilMini> mapaPerfiles = {};
      if (uidsPerfiles.isNotEmpty) {
        try {
          final perfilesData = await ServicioSupabase().cliente
              .from('perfiles_usuarios')
              .select('id, username, nombre, edad, foto_perfil_url')
              .inFilter('id', uidsPerfiles.toList());
          for (final raw in (perfilesData as List).cast<Map<String, dynamic>>()) {
            final p = _PerfilMini.fromMap(raw);
            mapaPerfiles[p.id] = p;
          }
          if (mapaPerfiles.isEmpty) {
            debugPrint(
              '⚠️ Listas/Pases: 0 perfiles cargados para ${uidsPerfiles.length} uids. '
              'Revisá RLS de perfiles_usuarios (el local debe poder leer solicitantes).',
            );
          }
        } catch (e) {
          debugPrint('⚠️ No se pudieron cargar perfiles de usuarios: $e');
        }
      }

      // Completar tokens cuyo JOIN no trajo perfil (RLS o embed fallido).
      for (final idEv in mapaTokens.keys.toList()) {
        mapaTokens[idEv] = mapaTokens[idEv]!
            .map((t) {
              final p = mapaPerfiles[t.idUsuario];
              if (p == null) return t;
              return t.tieneDatosSolicitante ? t : t.conPerfil(p);
            })
            .toList();
      }

      if (!mounted) return;
      setState(() {
        _perfilesMiembros = mapaPerfiles;
        _eventos = eventos;
        _tokensPorEvento = mapaTokens;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar las listas: $e';
      });
    }
  }

  // ── Helpers de conteo ──────────────────────────────────────────────────────

  List<_TokenAsist> _tokens(String idEvento) =>
      _tokensPorEvento[idEvento] ?? const [];

  int _cuentaPendientes(String idEvento) =>
      _tokens(idEvento).where((t) => t.estado == 'pendiente').length;

  int _cuentaAceptados(String idEvento) =>
      _tokens(idEvento)
          .where((t) => t.estado == 'aceptada' || t.estado == 'canjeada')
          .length;

  int _cuentaCanjeados(String idEvento) =>
      _tokens(idEvento).where((t) => t.estado == 'canjeada').length;

  // ── Bottomsheets ──────────────────────────────────────────────────────────

  void _abrirVerAceptados(_EventoLista evento) {
    final tokens = _tokens(evento.idEvento)
        .where((t) => t.estado == 'aceptada' || t.estado == 'canjeada')
        .toList();
    final grupos = _agrupar(tokens);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SheetAceptados(
        titulo: evento.titulo,
        grupos: grupos,
        perfilesMiembros: _perfilesMiembros,
      ),
    );
  }

  void _abrirGestionarPendientes(_EventoLista evento, {required bool puedeGestionar}) {
    final tokens = _tokens(evento.idEvento)
        .where((t) => t.estado == 'pendiente')
        .toList();
    final grupos = _agrupar(tokens);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SheetPendientes(
        titulo: evento.titulo,
        grupos: grupos,
        perfilesMiembros: _perfilesMiembros,
        scaffoldContext: context,
        puedeGestionar: puedeGestionar,
        onListaActualizada: () {
          if (mounted) _cargarDatos();
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final esStaff = ModoAppLocales.instancia.esStaff;

    if (esStaff) {
      return ScaffoldStaff(
        appBar: appBarStaff(
          centerTitle: true,
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
            child: Icon(
              CupertinoIcons.chevron_back,
              color: ColoresLocales.acentoVioleta,
            ),
          ),
          title: Text(
            'Listas y Pases',
            style: GoogleFonts.baloo2(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: ColoresLocales.acentoVioleta,
            ),
          ),
        ),
        body: _buildBody(),
      );
    }

    return Scaffold(
      backgroundColor: ColoresStaff.fondo,
      appBar: AppBar(
        backgroundColor: ColoresStaff.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: Icon(
            CupertinoIcons.chevron_back,
            color: ColoresLocales.acentoVioleta,
          ),
        ),
        title: Text(
          'Listas y Pases',
          style: GoogleFonts.baloo2(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: ColoresLocales.acentoVioleta,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_cargando) {
      return Center(
        child: CircularProgressIndicator(color: ColoresLocales.acentoVioleta),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.exclamationmark_circle,
                size: 44,
                color: Colors.red.shade400,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.baloo2(color: Colors.red.shade700),
              ),
              SizedBox(height: 16),
              CupertinoButton(
                color: ColoresLocales.acentoVioleta,
                borderRadius: BorderRadius.circular(50),
                onPressed: _cargarDatos,
                child: Text(
                  'Reintentar',
                  style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_eventos.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.ticket,
                size: 56,
                color: ColoresLocales.acentoVioleta.withOpacity(0.35),
              ),
              SizedBox(height: 14),
              Text(
                'No hay eventos activos con lista',
                textAlign: TextAlign.center,
                style: GoogleFonts.baloo2(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: ColoresLocales.textoOnFondoClaro,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Publicá un evento para ver sus listas y validaciones aquí.',
                textAlign: TextAlign.center,
                style: GoogleFonts.baloo2(
                  fontSize: 13,
                  color: ColoresLocales.textoSecundarioOnFondoClaro,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final uid = widget.idLocalOperando ??
        ServicioSupabase().usuarioActual?.id ??
        '';
    return RefreshIndicator(
      color: ColoresLocales.acentoVioleta,
      onRefresh: _cargarDatos,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        itemCount: _eventos.length,
        itemBuilder: (context, i) {
          final ev = _eventos[i];
          // Permisos: si no hay perfil de staff, asumimos owner (todos true).
          final permisos = widget.permisosStaff;
          final puedeAceptar = permisos == null || permisos.aceptarListas;
          final puedeVerLista = permisos == null || permisos.verListaAceptados;
          final puedeQr = permisos == null || permisos.puedeValidarQr;
          // QR de invitación: el dueño (permisos == null) siempre; el staff solo
          // si tiene el permiso especial habilitado.
          final puedeQrInvitacion = permisos == null || permisos.qrInvitacion;
          final pendientes = _cuentaPendientes(ev.idEvento);
          return _EventoCard(
            evento: ev,
            pendientes: pendientes,
            aceptados: _cuentaAceptados(ev.idEvento),
            canjeados: _cuentaCanjeados(ev.idEvento),
            puedeVerLista: puedeVerLista,
            puedeValidarQr: puedeQr,
            puedeQrInvitacion: puedeQrInvitacion,
            onMostrarQrInvitacion: puedeQrInvitacion
                ? () => mostrarQrInvitacionRrpp(
                      context,
                      idEvento: ev.idEvento,
                      tituloEvento: ev.titulo,
                    )
                : null,
            onVerLista: () => _abrirVerAceptados(ev),
            onAceptarPases: ev.modoLista == 'manual' && pendientes > 0
                ? () => _abrirGestionarPendientes(ev, puedeGestionar: puedeAceptar)
                : null,
            onValidarQr: puedeQr
                ? () {
                    Navigator.of(context).push(
                      CupertinoPageRoute<void>(
                        builder: (_) => LocalesQrValidar(
                          evento: EventoActivo(
                            idEvento: ev.idEvento,
                            idLocal: uid,
                            nombre: ev.titulo,
                            fechaInicio: ev.fechaInicio,
                            fechaFin: ev.fechaFin,
                          ),
                          permisosStaff: permisos,
                        ),
                      ),
                    );
                  }
                : null,
          );
        },
      ),
    );
  }
}

// ─── Card de evento — acciones siempre visibles ───────────────────────────────

String _fmtNumeroCompacto(num valor) {
  final n = valor.abs().round();
  final sign = valor < 0 ? '-' : '';
  if (n < 1000) return '$sign$n';

  if (n < 1000000) {
    final k = n / 1000.0;
    String s;
    if (k >= 100) {
      s = '${k.round()}';
    } else if (k >= 10) {
      s = k.toStringAsFixed(1);
    } else {
      s = k.toStringAsFixed(1);
    }
    if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
    return '$sign${s}k';
  }

  final m = n / 1000000.0;
  var s = m >= 10 ? m.toStringAsFixed(0) : m.toStringAsFixed(1);
  if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
  return '$sign${s}M';
}

String _fmtCupoChip(int aceptados, int? cupoMax) {
  final n = _fmtNumeroCompacto(aceptados);
  if (cupoMax != null) {
    return 'Cupo: $n/${_fmtNumeroCompacto(cupoMax)}';
  }
  return 'Cupo: $n';
}

class _EventoCard extends StatelessWidget {
  final _EventoLista evento;
  final int pendientes;
  final int aceptados;
  final int canjeados;
  final bool puedeVerLista;
  final bool puedeValidarQr;
  final bool puedeQrInvitacion;
  final VoidCallback onVerLista;
  final VoidCallback? onAceptarPases;
  final VoidCallback? onValidarQr;
  final VoidCallback? onMostrarQrInvitacion;

  const _EventoCard({
    required this.evento,
    required this.pendientes,
    required this.aceptados,
    required this.canjeados,
    this.puedeVerLista = true,
    this.puedeValidarQr = true,
    this.puedeQrInvitacion = false,
    required this.onVerLista,
    required this.onAceptarPases,
    required this.onValidarQr,
    this.onMostrarQrInvitacion,
  });

  String? _fmtFecha(_EventoLista ev) {
    final ini = ev.fechaInicio?.toLocal();
    if (ini == null) return null;
    final d = ini.day.toString().padLeft(2, '0');
    final m = ini.month.toString().padLeft(2, '0');
    final h = ini.hour.toString().padLeft(2, '0');
    final min = ini.minute.toString().padLeft(2, '0');
    return '$d/$m · $h:$min hs';
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final ev = evento;
    final ahora = DateTime.now();
    final enCurso = ev.fechaInicio != null &&
        ev.fechaFin != null &&
        ahora.isAfter(ev.fechaInicio!) &&
        ahora.isBefore(ev.fechaFin!);
    final proximamente =
        ev.fechaInicio != null && ahora.isBefore(ev.fechaInicio!);
    final overflow =
        ev.cupoListaMax != null && aceptados > ev.cupoListaMax!;
    final modoAuto = ev.modoLista == 'auto';
    final fechaTxt = _fmtFecha(ev);
    final cupoChip = _fmtCupoChip(aceptados, ev.cupoListaMax);

    final accentColor = overflow
        ? Colors.red.shade500
        : enCurso
            ? const Color(0xFF16A34A)
            : ColoresLocales.acentoVioleta;

    final puedePendientes =
        !modoAuto && pendientes > 0 && onAceptarPases != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: ColoresLocales.decoracionCard(radius: 22, sinBorde: true)
          .copyWith(boxShadow: ColoresLocales.sombrasCard(acento: accentColor)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 52,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ev.titulo,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.baloo2(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: ColoresLocales.textoOnFondoClaro,
                          height: 1.15,
                        ),
                      ),
                      if (fechaTxt != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          fechaTxt,
                          style: GoogleFonts.baloo2(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: ColoresLocales.textoSecundarioOnFondoClaro,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (enCurso)
                            _PillEstado(
                              label: 'En curso',
                              color: const Color(0xFF16A34A),
                            ),
                          if (proximamente)
                            _PillEstado(
                              label: 'Próximo',
                              color: ColoresLocales.acentoVioleta,
                            ),
                          if (overflow)
                            _PillEstado(
                              label: 'Cupo superado',
                              color: Colors.red.shade600,
                            ),
                          _PillEstado(
                            label: modoAuto ? 'Lista auto' : 'Lista manual',
                            color: modoAuto
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFD97706),
                          ),
                          _PillEstado(
                            label: cupoChip,
                            color: overflow
                                ? Colors.red.shade600
                                : ColoresLocales.textoSecundarioOnFondoClaro,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _StatMini(
                    icon: CupertinoIcons.checkmark_circle_fill,
                    label: 'Aceptados',
                    value: _fmtNumeroCompacto(aceptados),
                    color: ColoresLocales.acentoVioleta,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatMini(
                    icon: CupertinoIcons.clock_fill,
                    label: 'Pendientes',
                    value: _fmtNumeroCompacto(pendientes),
                    color: pendientes > 0
                        ? const Color(0xFFD97706)
                        : ColoresLocales.textoSecundarioOnFondoClaro,
                    destacado: pendientes > 0,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatMini(
                    icon: CupertinoIcons.arrow_right_circle_fill,
                    label: 'Ya ingresaron',
                    value: _fmtNumeroCompacto(canjeados),
                    color: canjeados > 0
                        ? const Color(0xFF16A34A)
                        : ColoresLocales.textoSecundarioOnFondoClaro,
                    destacado: canjeados > 0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(height: 1, thickness: 1, color: ColoresLocales.separador),
            const SizedBox(height: 12),
            Row(
              children: [
                _AccionBtn(
                  icono: CupertinoIcons.list_bullet,
                  label: 'Lista',
                  color: ColoresLocales.botonVioletaFondo,
                  enabled: puedeVerLista && aceptados > 0,
                  onTap: onVerLista,
                ),
                const SizedBox(width: 8),
                _AccionBtn(
                  icono: CupertinoIcons.tray_arrow_down_fill,
                  label: 'Pendientes',
                  color: const Color(0xFFD97706),
                  enabled: puedePendientes,
                  badge: pendientes,
                  onTap: onAceptarPases ?? () {},
                ),
                const SizedBox(width: 8),
                _AccionBtn(
                  icono: CupertinoIcons.qrcode_viewfinder,
                  label: 'Lector QR',
                  color: const Color(0xFF16A34A),
                  enabled: puedeValidarQr && onValidarQr != null,
                  onTap: onValidarQr ?? () {},
                ),
                if (puedeQrInvitacion && onMostrarQrInvitacion != null) ...[
                  const SizedBox(width: 8),
                  _AccionBtn(
                    icono: CupertinoIcons.qrcode,
                    label: 'Invitar',
                    color: ColoresLocales.acentoVioleta,
                    enabled: true,
                    onTap: onMostrarQrInvitacion!,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatMini extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool destacado;

  static const _altura = 72.0;

  const _StatMini({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.destacado = false,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return Container(
      height: _altura,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: destacado
            ? color.withOpacity(0.1)
            : ColoresLocales.superficieElevada,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: GoogleFonts.baloo2(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: ColoresLocales.textoOnFondoClaro,
                height: 1,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.baloo2(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: ColoresLocales.textoSecundarioOnFondoClaro,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _PillEstado extends StatelessWidget {
  final String label;
  final Color color;
  const _PillEstado({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.baloo2(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _AccionBtn extends StatelessWidget {
  final IconData icono;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;
  final int badge;

  const _AccionBtn({
    required this.icono,
    required this.label,
    required this.color,
    required this.onTap,
    this.enabled = true,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    final oscuro = TemaLocalesScope.of(context);
    final bg = enabled ? color : ColoresLocales.grisClaroFondo;
    final fg = enabled
        ? ColoresLocales.textoEnBotonSobre(bg)
        : (oscuro ? const Color(0xFF737373) : const Color(0xFF9CA3AF));

    return Expanded(
      child: Material(
        color: Colors.transparent,
        elevation: enabled && !oscuro ? 2 : 0,
        shadowColor: enabled && !oscuro
            ? color.withOpacity(0.28)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: enabled
              ? () {
                  HapticFeedback.lightImpact();
                  onTap();
                }
              : null,
          borderRadius: BorderRadius.circular(16),
          splashColor: ColoresLocales.textoEnBoton.withOpacity(0.12),
          highlightColor: ColoresLocales.textoEnBoton.withOpacity(0.08),
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icono, size: 22, color: fg),
                    const SizedBox(height: 5),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.baloo2(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: fg,
                        height: 1,
                      ),
                    ),
                  ],
                ),
                if (badge > 0)
                  Positioned(
                    top: -4,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD43B),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        badge >= 1000
                            ? _fmtNumeroCompacto(badge)
                            : '$badge',
                        style: GoogleFonts.baloo2(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: Colors.black87,
                          height: 1,
                        ),
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

// ─── BottomSheet: Ver Aceptados ───────────────────────────────────────────────

class _SheetAceptados extends StatelessWidget {
  final String titulo;
  final List<_GrupoAsist> grupos;
  final Map<String, _PerfilMini> perfilesMiembros;

  const _SheetAceptados({
    required this.titulo,
    required this.grupos,
    required this.perfilesMiembros,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Material(
            color: ColoresLocales.chipInactivo,
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      SizedBox(height: 10),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      SizedBox(height: 14),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Lista aceptada',
                                    style: GoogleFonts.baloo2(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: ColoresLocales.textoOnFondoClaro,
                                    ),
                                  ),
                                  Text(
                                    titulo,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.baloo2(
                                      fontSize: 12,
                                      color: ColoresLocales
                                          .textoSecundarioOnFondoClaro,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${grupos.length} entrada${grupos.length != 1 ? "s" : ""}',
                                style: GoogleFonts.baloo2(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 20),
                    ],
                  ),
                ),
                if (grupos.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        'Todavía no hay nadie aceptado.',
                        style: GoogleFonts.baloo2(
                          color: ColoresLocales.textoSecundarioOnFondoClaro,
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          if (i.isOdd) return const SizedBox(height: 10);
                          final idx = i ~/ 2;
                          return _CardGrupoAceptado(
                            grupo: grupos[idx],
                            perfilesMiembros: perfilesMiembros,
                          );
                        },
                        childCount: grupos.length * 2 - 1,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── BottomSheet: Gestionar Pendientes ───────────────────────────────────────

enum _EstadoCardPendiente {
  idle,
  cargandoAceptar,
  cargandoRechazar,
  exitoAceptar,
  exitoRechazar,
  saliendo,
}

class _SheetPendientes extends StatefulWidget {
  final String titulo;
  final List<_GrupoAsist> grupos;
  final Map<String, _PerfilMini> perfilesMiembros;
  final BuildContext scaffoldContext;
  final bool puedeGestionar;
  final VoidCallback onListaActualizada;

  const _SheetPendientes({
    required this.titulo,
    required this.grupos,
    required this.perfilesMiembros,
    required this.scaffoldContext,
    this.puedeGestionar = true,
    required this.onListaActualizada,
  });

  @override
  State<_SheetPendientes> createState() => _SheetPendientesState();
}

class _SheetPendientesState extends State<_SheetPendientes> {
  late List<_GrupoAsist> _grupos;
  final Map<String, _EstadoCardPendiente> _estados = {};

  @override
  void initState() {
    super.initState();
    _grupos = List<_GrupoAsist>.from(widget.grupos);
    for (final g in _grupos) {
      _estados[_claveGrupo(g)] = _EstadoCardPendiente.idle;
    }
  }

  String _claveGrupo(_GrupoAsist g) => g.idReserva ?? g.tokenPrincipal.idToken;

  _EstadoCardPendiente _estadoDe(_GrupoAsist g) =>
      _estados[_claveGrupo(g)] ?? _EstadoCardPendiente.idle;

  bool _esOverflow(dynamic v) => v == true || v == 'true' || v == 1;

  void _refrescarListaEnBackground() {
    try {
      widget.onListaActualizada();
    } catch (e, st) {
      debugPrint('⚠️ refresh lista tras gestionar: $e\n$st');
    }
  }

  /// Si la edge falló pero el token ya quedó en el estado esperado, tratar como éxito.
  Future<bool> _operacionYaAplicadaEnDb(_GrupoAsist grupo, String accion) async {
    final estadoEsperado = accion == 'aceptar' ? 'aceptada' : 'rechazada';
    try {
      final sb = ServicioSupabase().cliente;
      if (grupo.esSquad) {
        final idReserva = grupo.idReserva;
        if (idReserva == null || idReserva.isEmpty) return false;
        final rows = await sb
            .from('tokens_asistencia')
            .select('estado_token')
            .eq('id_reserva_grupal', idReserva);
        final list = List<Map<String, dynamic>>.from(rows as List);
        if (list.isEmpty) return false;
        return list.every((r) => r['estado_token']?.toString() == estadoEsperado);
      }
      final row = await sb
          .from('tokens_asistencia')
          .select('estado_token')
          .eq('id_token', grupo.tokenPrincipal.idToken)
          .maybeSingle();
      return row?['estado_token']?.toString() == estadoEsperado;
    } catch (e) {
      debugPrint('⚠️ verificar estado token: $e');
      return false;
    }
  }

  Future<void> _marcarExito({
    required String key,
    required _EstadoCardPendiente estadoExito,
    required _GrupoAsist grupo,
    required String accion,
    Map<String, dynamic>? res,
  }) async {
    if (!mounted) return;
    if (accion == 'aceptar' && res != null && _esOverflow(res['overflow'])) {
      final cuposUsados = res['cupos_usados'] ?? '?';
      final cupoMax = res['cupo_max'] ?? '?';
      ScaffoldMessenger.maybeOf(widget.scaffoldContext)?.showSnackBar(
        SnackBar(
          content: Text(
            'Aceptado con cupo superado ($cuposUsados/$cupoMax).',
            style: GoogleFonts.baloo2(fontWeight: FontWeight.w700),
          ),
          backgroundColor: const Color(0xFFD97706),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
    HapticFeedback.lightImpact();
    setState(() => _estados[key] = estadoExito);
    _refrescarListaEnBackground();
  }

  Future<void> _gestionar(_GrupoAsist grupo, String accion) async {
    if (!widget.puedeGestionar) return;
    final key = _claveGrupo(grupo);

    // Anti doble-disparo: si la card ya está procesando, ignorar el click.
    final estadoActual = _estadoDe(grupo);
    if (estadoActual == _EstadoCardPendiente.cargandoAceptar ||
        estadoActual == _EstadoCardPendiente.cargandoRechazar ||
        estadoActual == _EstadoCardPendiente.exitoAceptar ||
        estadoActual == _EstadoCardPendiente.exitoRechazar) {
      return;
    }

    final estadoCarga = accion == 'aceptar'
        ? _EstadoCardPendiente.cargandoAceptar
        : _EstadoCardPendiente.cargandoRechazar;
    final estadoExito = accion == 'aceptar'
        ? _EstadoCardPendiente.exitoAceptar
        : _EstadoCardPendiente.exitoRechazar;

    setState(() => _estados[key] = estadoCarga);

    try {
      final Map<String, dynamic> res;
      if (grupo.esSquad) {
        final idReserva = grupo.idReserva;
        if (idReserva == null || idReserva.isEmpty) {
          throw Exception('Esta reserva de squad no tiene id_reserva_grupal.');
        }
        res = await ServicioEdgesEventos().gestionarAsistencia(
          idReservaGrupal: idReserva,
          accion: accion,
        );
      } else {
        res = await ServicioEdgesEventos().gestionarAsistencia(
          idToken: grupo.tokenPrincipal.idToken,
          accion: accion,
        );
      }

      await _marcarExito(
        key: key,
        estadoExito: estadoExito,
        grupo: grupo,
        accion: accion,
        res: res,
      );
    } on EdgeException catch (e) {
      if (!mounted) return;
      if (e.yaAplicada || await _operacionYaAplicadaEnDb(grupo, accion)) {
        await _marcarExito(
          key: key,
          estadoExito: estadoExito,
          grupo: grupo,
          accion: accion,
        );
        return;
      }
      debugPrint('❌ gestionar_asistencia ($accion) EdgeException: $e');
      setState(() => _estados[key] = _EstadoCardPendiente.idle);
      await showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: Text('No se pudo ${accion == 'aceptar' ? 'aceptar' : 'rechazar'}'),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(e.mensaje, style: const TextStyle(fontSize: 13)),
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e, st) {
      debugPrint('❌ gestionar_asistencia ($accion): $e\n$st');
      if (!mounted) return;
      if (await _operacionYaAplicadaEnDb(grupo, accion)) {
        await _marcarExito(
          key: key,
          estadoExito: estadoExito,
          grupo: grupo,
          accion: accion,
        );
        return;
      }
      setState(() => _estados[key] = _EstadoCardPendiente.idle);
      final msg = e.toString().replaceFirst('Exception: ', '');
      await showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: Text(
            'No se pudo ${accion == 'aceptar' ? 'aceptar' : 'rechazar'}',
          ),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(msg, style: const TextStyle(fontSize: 13)),
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Material(
            color: ColoresLocales.chipInactivo,
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      SizedBox(height: 10),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      SizedBox(height: 14),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          'Solicitudes pendientes',
                          style: GoogleFonts.baloo2(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: ColoresLocales.textoOnFondoClaro,
                          ),
                        ),
                      ),
                      SizedBox(height: 2),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          '"${widget.titulo}"',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.baloo2(
                            fontSize: 13,
                            color: ColoresLocales.textoSecundarioOnFondoClaro,
                          ),
                        ),
                      ),
                      if (!widget.puedeGestionar) ...[
                        SizedBox(height: 12),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF6E5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  CupertinoIcons.eye,
                                  size: 16,
                                  color: Color(0xFFD97706),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Solo lectura: el local no te habilitó a aceptar o rechazar solicitudes.',
                                    style: GoogleFonts.baloo2(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF92400E),
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      Divider(height: 20),
                    ],
                  ),
                ),
                if (_grupos.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          CupertinoIcons.checkmark_circle,
                          color: ColoresLocales.acentoVioleta,
                          size: 42,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'No hay solicitudes pendientes.',
                          style: GoogleFonts.baloo2(
                            color: ColoresLocales.textoSecundarioOnFondoClaro,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Podés cerrar y ver la lista aceptada.',
                          style: GoogleFonts.baloo2(
                            fontSize: 12,
                            color: ColoresLocales.textoSecundarioOnFondoClaro,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          if (i.isOdd) return const SizedBox(height: 10);
                          final grupo = _grupos[i ~/ 2];
                          final estado = _estadoDe(grupo);
                          return _CardGrupoPendiente(
                            grupo: grupo,
                            perfilesMiembros: widget.perfilesMiembros,
                            estado: estado,
                            puedeGestionar: widget.puedeGestionar,
                            onAceptar: () => _gestionar(grupo, 'aceptar'),
                            onRechazar: () => _gestionar(grupo, 'rechazar'),
                          );
                        },
                        childCount: _grupos.length * 2 - 1,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Card grupo aceptado ─────────────────────────────────────────────────────

class _CardGrupoAceptado extends StatelessWidget {
  final _GrupoAsist grupo;
  final Map<String, _PerfilMini> perfilesMiembros;

  const _CardGrupoAceptado({
    required this.grupo,
    required this.perfilesMiembros,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final tok = grupo.tokenPrincipal;
    final esSquad = grupo.esSquad;
    final personas = grupo.cantidadPersonas;
    final canjeada = tok.estado == 'canjeada';
    final estadoChipColor =
        canjeada ? const Color(0xFF16A34A) : const Color(0xFFD97706);
    final estadoChipLabel = canjeada ? 'Canjeada' : 'Aceptada';

    return Container(
      padding: EdgeInsets.all(14),
      decoration: ColoresLocales.decoracionCard(
        radius: 16,
        sinBorde: true,
        color: ColoresLocales.cardLavanda,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _abrirPerfilDesdeToken(context, tok),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (esSquad)
                    _SquadAvatarStack(
                      tok: tok,
                      perfilesMiembros: perfilesMiembros,
                    )
                  else
                    _AvatarUsuario(
                        avatarUrl: tok.avatarUrlSolicitante, size: 48),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          esSquad ? _squadDisplayName(tok) : tok.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.baloo2(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: ColoresLocales.textoOnFondoClaro,
                            height: 1.1,
                          ),
                        ),
                        SizedBox(height: 2),
                        _SubLineaSolicitante(
                          tok: tok,
                          esSquad: esSquad,
                          personas: personas,
                          perfilesMiembros: perfilesMiembros,
                        ),
                        if (tok.codigoPuerta != null &&
                            tok.codigoPuerta!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Código: ${tok.codigoPuerta}',
                            style: GoogleFonts.baloo2(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color:
                                  ColoresLocales.acentoVioleta.withOpacity(0.7),
                              letterSpacing: 1.5,
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
          const SizedBox(width: 10),
          _PillEstado(
            label: estadoChipLabel,
            color: estadoChipColor,
          ),
        ],
      ),
    );
  }
}

/// Abre el visor de perfil de cliente para el líder de un token, pasando los
/// UIDs de los miembros del squad (desde el snapshot) para poder navegarlos.
void _abrirPerfilDesdeToken(BuildContext context, _TokenAsist tok) {
  final uids = <String>[];
  final miembros = tok.snapshotSquad?['miembros'];
  if (miembros is List) {
    for (final m in miembros) {
      final s = m?.toString().trim() ?? '';
      if (s.isNotEmpty) uids.add(s);
    }
  }
  LocalesPerfilClientes.abrir(
    context,
    idUsuario: tok.idUsuario,
    nombreInicial: tok.nombreSolicitante,
    usernameInicial: tok.username,
    edadInicial: tok.edadSolicitante,
    fotoInicial: tok.avatarUrlSolicitante,
    miembrosSquadUids: uids,
    nombreSquad: tok.snapshotSquad?['nombre']?.toString(),
  );
}

String _squadDisplayName(_TokenAsist tok) {
  final snap = tok.snapshotSquad;
  if (snap == null) return 'Squad';
  final n = snap['nombre']?.toString().trim() ?? '';
  if (n.isNotEmpty) return n;
  // fallback al líder
  return tok.displayName.isNotEmpty
      ? 'Squad de ${tok.displayName}'
      : 'Squad';
}

/// Calcula promedio de edad del squad usando los perfiles de los miembros.
double? _promedioEdadSquad(
  _TokenAsist tok,
  Map<String, _PerfilMini> perfiles,
) {
  final snap = tok.snapshotSquad;
  if (snap == null) return null;
  final miembros = snap['miembros'];
  if (miembros is! List) return null;
  final edades = <int>[];
  for (final m in miembros) {
    final p = perfiles[m?.toString() ?? ''];
    if (p?.edad != null) edades.add(p!.edad!);
  }
  // Incluir también la edad del solicitante (líder) si está
  if (tok.edadSolicitante != null) edades.add(tok.edadSolicitante!);
  if (edades.isEmpty) return null;
  final sum = edades.reduce((a, b) => a + b);
  return sum / edades.length;
}

/// Sublinea: para individual @username · edad. Para squad: N personas · prom edad.
class _SubLineaSolicitante extends StatelessWidget {
  final _TokenAsist tok;
  final bool esSquad;
  final int personas;
  final Map<String, _PerfilMini> perfilesMiembros;

  const _SubLineaSolicitante({
    required this.tok,
    required this.esSquad,
    required this.personas,
    required this.perfilesMiembros,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    if (esSquad) {
      final rowChildren = <Widget>[
        _subTexto('Squad · $personas personas'),
      ];
      final prom = _promedioEdadSquad(tok, perfilesMiembros);
      if (prom != null) {
        rowChildren.add(SizedBox(width: 6));
        rowChildren.add(_BadgeMini(text: '~${prom.round()} años prom.'));
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: rowChildren,
      );
    }

    final handle = tok.displayHandle;
    final edad = tok.edadSolicitante;
    if (handle.isEmpty && edad == null) {
      return _subTexto('Individual');
    }

    return Row(
      children: [
        if (handle.isNotEmpty)
          Expanded(
            child: Text(
              handle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.baloo2(
                fontSize: 12.5,
                color: ColoresLocales.textoSecundarioOnFondoClaro,
              ),
            ),
          ),
        if (edad != null) ...[
          if (handle.isNotEmpty) SizedBox(width: 6),
          _BadgeMini(text: '$edad años'),
        ],
      ],
    );
  }

  Widget _subTexto(String s) => Text(
        s,
        style: GoogleFonts.baloo2(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: ColoresLocales.textoSecundarioOnFondoClaro,
        ),
      );
}

class _BadgeMini extends StatelessWidget {
  final String text;
  const _BadgeMini({required this.text});
  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: ColoresLocales.acentoVioleta.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: GoogleFonts.baloo2(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: ColoresLocales.acentoVioleta,
        ),
      ),
    );
  }
}

// ─── Card grupo pendiente ─────────────────────────────────────────────────────

class _CardGrupoPendiente extends StatelessWidget {
  final _GrupoAsist grupo;
  final Map<String, _PerfilMini> perfilesMiembros;
  final _EstadoCardPendiente estado;
  final bool puedeGestionar;
  final VoidCallback onAceptar;
  final VoidCallback onRechazar;

  const _CardGrupoPendiente({
    required this.grupo,
    required this.perfilesMiembros,
    required this.estado,
    this.puedeGestionar = true,
    required this.onAceptar,
    required this.onRechazar,
  });

  bool get _cargandoAceptar =>
      estado == _EstadoCardPendiente.cargandoAceptar;
  bool get _cargandoRechazar =>
      estado == _EstadoCardPendiente.cargandoRechazar;
  bool get _exitoAceptar => estado == _EstadoCardPendiente.exitoAceptar;
  bool get _exitoRechazar => estado == _EstadoCardPendiente.exitoRechazar;

  bool get _bloqueado =>
      !puedeGestionar ||
      _cargandoAceptar ||
      _cargandoRechazar ||
      _exitoAceptar ||
      _exitoRechazar ||
      estado == _EstadoCardPendiente.saliendo;

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final tok = grupo.tokenPrincipal;
    final esSquad = grupo.esSquad;
    final personas = grupo.cantidadPersonas;
    final saliendo = estado == _EstadoCardPendiente.saliendo;

    return ClipRect(
      child: AnimatedAlign(
        alignment: Alignment.topCenter,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOut,
        heightFactor: saliendo ? 0 : 1,
        child: AnimatedOpacity(
          duration: Duration(milliseconds: 280),
          opacity: saliendo ? 0 : 1,
          child: AnimatedSlide(
            duration: Duration(milliseconds: 380),
            curve: Curves.easeInOut,
            offset: saliendo ? const Offset(0.08, 0) : Offset.zero,
            child: _cuerpoCard(
              context: context,
              tok: tok,
              esSquad: esSquad,
              personas: personas,
            ),
          ),
        ),
      ),
    );
  }

  Widget _cuerpoCard({
    required BuildContext context,
    required _TokenAsist tok,
    required bool esSquad,
    required int personas,
  }) {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: ColoresLocales.decoracionCard(radius: 16, sinBorde: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _abrirPerfilDesdeToken(context, tok),
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (esSquad)
                _SquadAvatarStack(
                  tok: tok,
                  perfilesMiembros: perfilesMiembros,
                )
              else
                _AvatarUsuario(
                  avatarUrl: tok.avatarUrlSolicitante,
                  size: 52,
                ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      esSquad ? _squadDisplayName(tok) : tok.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.baloo2(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: ColoresLocales.textoOnFondoClaro,
                        height: 1.1,
                      ),
                    ),
                    SizedBox(height: 2),
                    _SubLineaSolicitante(
                      tok: tok,
                      esSquad: esSquad,
                      personas: personas,
                      perfilesMiembros: perfilesMiembros,
                    ),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          esSquad
                              ? CupertinoIcons.group_solid
                              : CupertinoIcons.person_fill,
                          size: 12,
                          color: ColoresLocales.textoSecundarioOnFondoClaro,
                        ),
                        SizedBox(width: 4),
                        Text(
                          esSquad
                              ? 'Squad · $personas personas'
                              : 'Individual',
                          style: GoogleFonts.baloo2(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: ColoresLocales.textoSecundarioOnFondoClaro,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          ),
          if (esSquad) ...[
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF6E5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.exclamationmark_triangle_fill,
                    size: 14,
                    color: Color(0xFFD97706),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Esta acción afecta a $personas personas del squad',
                      style: GoogleFonts.baloo2(
                        fontSize: 11.5,
                        color: Color(0xFF92400E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: 12),
          Opacity(
            opacity: puedeGestionar ? 1 : 0.38,
            child: IgnorePointer(
              ignoring: !puedeGestionar,
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _bloqueado ? null : onAceptar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _exitoAceptar
                        ? Color(0xFF16A34A)
                        : ColoresLocales.acentoVioleta,
                    disabledBackgroundColor: _exitoAceptar
                        ? Color(0xFF16A34A)
                        : ColoresLocales.acentoVioleta,
                    foregroundColor: ColoresLocales.textoEnBoton,
                    disabledForegroundColor: ColoresLocales.chipInactivo,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50),
                    ),
                    minimumSize: Size.fromHeight(46),
                  ),
                  child: _contenidoBoton(
                    cargando: _cargandoAceptar,
                    exito: _exitoAceptar,
                    label: 'Aceptar',
                    labelExito: 'Aceptado',
                    colorLoader: ColoresLocales.chipInactivo,
                    colorExito: ColoresLocales.chipInactivo,
                  ),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _bloqueado ? null : onRechazar,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _exitoRechazar
                        ? Color(0xFFDC2626)
                        : ColoresLocales.acentoVioleta.withValues(alpha: 0.08),
                    disabledBackgroundColor: _exitoRechazar
                        ? Color(0xFFDC2626)
                        : ColoresLocales.chipInactivo,
                    foregroundColor: _exitoRechazar
                        ? ColoresLocales.chipInactivo
                        : ColoresLocales.acentoVioleta,
                    disabledForegroundColor: _exitoRechazar
                        ? ColoresLocales.chipInactivo
                        : ColoresLocales.acentoVioleta,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50),
                    ),
                    minimumSize: Size.fromHeight(46),
                  ),
                  child: _contenidoBoton(
                    cargando: _cargandoRechazar,
                    exito: _exitoRechazar,
                    label: 'Rechazar',
                    labelExito: 'Rechazado',
                    colorLoader: ColoresLocales.acentoVioleta,
                    colorExito: ColoresLocales.chipInactivo,
                  ),
                ),
              ),
            ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contenidoBoton({
    required bool cargando,
    required bool exito,
    required String label,
    required String labelExito,
    required Color colorLoader,
    required Color colorExito,
  }) {
    if (cargando) {
      return SizedBox(
        height: 22,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: colorLoader,
            ),
          ),
        ),
      );
    }
    if (exito) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            labelExito == 'Aceptado'
                ? CupertinoIcons.checkmark
                : CupertinoIcons.xmark,
            size: 18,
            color: colorExito,
          ),
          const SizedBox(width: 6),
          Text(
            labelExito,
            style: GoogleFonts.baloo2(
              fontWeight: FontWeight.w800,
              color: colorExito,
            ),
          ),
        ],
      );
    }
    return Text(
      label,
      style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
    );
  }
}

// ─── Squad avatar stack ──────────────────────────────────────────────────────

/// Stack de hasta 3 avatares de miembros del squad + indicador +N.
/// Usa `tok.snapshotSquad.miembros` (lista de uids) y los resuelve via [perfilesMiembros].
class _SquadAvatarStack extends StatelessWidget {
  final _TokenAsist tok;
  final Map<String, _PerfilMini> perfilesMiembros;
  final double avatarSize = 48;
  final double overlap = 14;

  const _SquadAvatarStack({
    required this.tok,
    required this.perfilesMiembros,
  });

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    // Construir lista de uids del squad. Líder primero si está disponible.
    final uids = <String>[];
    final leaderUid = tok.idUsuario;
    if (leaderUid.isNotEmpty) uids.add(leaderUid);
    final miembros = tok.snapshotSquad?['miembros'];
    if (miembros is List) {
      for (final m in miembros) {
        final s = m?.toString();
        if (s != null && s.isNotEmpty && !uids.contains(s)) uids.add(s);
      }
    }

    final total = uids.isNotEmpty ? uids.length : tok.cantidadPersonas;
    final mostrar = uids.take(3).toList();
    final extra = total > 3 ? total - 3 : 0;

    final step = avatarSize - overlap;
    final extraSlot = extra > 0 ? step : 0;
    final width = mostrar.isEmpty
        ? avatarSize
        : (mostrar.length - 1) * step + avatarSize + extraSlot;

    // Avatar URL del líder: usar el del tok directamente si está
    String? avatarLider = tok.avatarUrlSolicitante;
    if (avatarLider == null) {
      final p = perfilesMiembros[leaderUid];
      avatarLider = p?.avatarUrl;
    }

    return SizedBox(
      width: width,
      height: avatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < mostrar.length; i++)
            Positioned(
              left: i * step,
              child: _AvatarChip(
                avatarUrl: i == 0
                    ? avatarLider
                    : perfilesMiembros[mostrar[i]]?.avatarUrl,
                size: avatarSize,
              ),
            ),
          if (extra > 0)
            Positioned(
              left: mostrar.length * step,
              child: Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ColoresLocales.acentoVioleta,
                  boxShadow: [
                    BoxShadow(
                      color: ColoresLocales.acentoVioleta.withOpacity(0.25),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '+$extra',
                    style: GoogleFonts.baloo2(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: ColoresLocales.chipInactivo,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Chip de avatar circular (interior del stack — con borde blanco para separarse).
class _AvatarChip extends StatelessWidget {
  final String? avatarUrl;
  final double size;
  const _AvatarChip({required this.avatarUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final hasUrl = avatarUrl != null && avatarUrl!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ColoresLocales.cardLavanda,
        boxShadow: [
          BoxShadow(
            color: ColoresLocales.acentoVioleta.withOpacity(0.18),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: hasUrl
          ? Image.network(
              avatarUrl!,
              fit: BoxFit.cover,
              loadingBuilder: (ctx, child, progress) => progress == null
                  ? child
                  : ColoredBox(color: ColoresLocales.cardLavanda),
              errorBuilder: (_, __, ___) => _ph(),
            )
          : _ph(),
    );
  }

  Widget _ph() => Center(
        child: Icon(
          CupertinoIcons.person_fill,
          size: size * 0.5,
          color: ColoresLocales.acentoVioleta.withOpacity(0.6),
        ),
      );
}

// ─── Modelos de datos ─────────────────────────────────────────────────────────

class _EventoLista {
  final String idEvento;
  final String titulo;
  final String modoLista;
  final int? cupoListaMax;     // null = sin límite
  final int cupoListaUsados;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;

  const _EventoLista({
    required this.idEvento,
    required this.titulo,
    required this.modoLista,
    required this.cupoListaMax,
    required this.cupoListaUsados,
    required this.fechaInicio,
    required this.fechaFin,
  });

  /// true si cupo definido y ya superado (overflow en modo manual)
  bool get enOverflow => cupoListaMax != null && cupoListaUsados > cupoListaMax!;

  /// Lugares libres restantes; null si sin límite
  int? get libres => cupoListaMax == null ? null : (cupoListaMax! - cupoListaUsados);

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String && v.trim().isNotEmpty) return DateTime.tryParse(v);
    return DateTime.tryParse(v.toString());
  }

  factory _EventoLista.fromMap(Map<String, dynamic> m) {
    return _EventoLista(
      idEvento: m['id_evento'].toString(),
      titulo: ((m['titulo_evento'] as String?) ?? '').trim().isEmpty
          ? 'Evento sin título'
          : (m['titulo_evento'] as String).trim(),
      modoLista: (m['modo_lista'] as String?) ?? 'auto',
      cupoListaMax: (m['cupo_lista_max'] as num?)?.toInt(), // null = sin límite
      cupoListaUsados: (m['cupo_lista_usados'] as num?)?.toInt() ?? 0,
      fechaInicio: _parseDate(m['fecha_inicio']),
      fechaFin: _parseDate(m['fecha_fin']),
    );
  }
}

class _TokenAsist {
  final String idToken;
  final String idEvento;
  final String idUsuario;
  final String? idReservaGrupal;
  final String? codigoPuerta;  // null mientras pendiente en modo manual
  final String estado;
  final DateTime? fechaCreacion;
  final Map<String, dynamic>? snapshotSquad;
  // Info del solicitante (JOIN perfiles_usuarios)
  final String? username;
  final String? nombreSolicitante;
  final int? edadSolicitante;
  final String? avatarUrlSolicitante; // URL pública resuelta

  const _TokenAsist({
    required this.idToken,
    required this.idEvento,
    required this.idUsuario,
    required this.idReservaGrupal,
    required this.codigoPuerta,
    required this.estado,
    required this.fechaCreacion,
    required this.snapshotSquad,
    this.username,
    this.nombreSolicitante,
    this.edadSolicitante,
    this.avatarUrlSolicitante,
  });

  /// Display name: prefiere `nombre`, fallback a `@username`, fallback a `Usuario`.
  String get displayName {
    final n = nombreSolicitante?.trim() ?? '';
    if (n.isNotEmpty) return n;
    final u = username?.trim() ?? '';
    if (u.isNotEmpty) return '@$u';
    return 'Usuario';
  }

  /// Username con @ si hay, vacío si no.
  String get displayHandle {
    final u = username?.trim() ?? '';
    return u.isEmpty ? '' : '@$u';
  }

  /// Cantidad de personas que abarca este token (1 si individual, n si squad).
  int get cantidadPersonas {
    if (snapshotSquad == null) return 1;
    final cant = snapshotSquad!['cantidad'];
    if (cant is int) return cant;
    if (cant is num) return cant.toInt();
    return 1;
  }

  bool get esSquad => idReservaGrupal != null;

  bool get tieneDatosSolicitante =>
      (nombreSolicitante?.trim().isNotEmpty ?? false) ||
      (username?.trim().isNotEmpty ?? false) ||
      (avatarUrlSolicitante?.isNotEmpty ?? false) ||
      edadSolicitante != null;

  _TokenAsist conPerfil(_PerfilMini p) => _TokenAsist(
        idToken: idToken,
        idEvento: idEvento,
        idUsuario: idUsuario,
        idReservaGrupal: idReservaGrupal,
        codigoPuerta: codigoPuerta,
        estado: estado,
        fechaCreacion: fechaCreacion,
        snapshotSquad: snapshotSquad,
        username: username ?? p.username,
        nombreSolicitante: nombreSolicitante ?? p.nombre,
        edadSolicitante: edadSolicitante ?? p.edad,
        avatarUrlSolicitante: avatarUrlSolicitante ?? p.avatarUrl,
      );

  static Map<String, dynamic>? _perfilEmbedDesdeMap(Map<String, dynamic> m) {
    final perfilRaw = m['perfiles_usuarios'];
    if (perfilRaw is Map) return Map<String, dynamic>.from(perfilRaw);
    if (perfilRaw is List && perfilRaw.isNotEmpty) {
      final first = perfilRaw.first;
      if (first is Map) return Map<String, dynamic>.from(first);
    }
    return null;
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String && v.trim().isNotEmpty) return DateTime.tryParse(v);
    return DateTime.tryParse(v.toString());
  }

  factory _TokenAsist.fromMap(Map<String, dynamic> m) {
    Map<String, dynamic>? snap;
    final rawSnap = m['snapshot_squad'];
    if (rawSnap is Map<String, dynamic>) {
      snap = rawSnap;
    } else if (rawSnap is Map) {
      snap = rawSnap.cast<String, dynamic>();
    }

    // Parsear el perfil del solicitante (JOIN embebido)
    String? username;
    String? nombre;
    int? edad;
    String? avatarUrl;
    final perfilMap = _perfilEmbedDesdeMap(m);
    if (perfilMap != null) {
      username = perfilMap['username']?.toString();
      nombre = perfilMap['nombre']?.toString();
      final edadRaw = perfilMap['edad'];
      edad = edadRaw is int
          ? edadRaw
          : (edadRaw != null ? int.tryParse(edadRaw.toString()) : null);
      final fotoPath = perfilMap['foto_perfil_url']?.toString();
      if (fotoPath != null && fotoPath.isNotEmpty) {
        avatarUrl = fotoPath.startsWith('http')
            ? fotoPath
            : ServicioSupabase()
                .cliente
                .storage
                .from('avatars')
                .getPublicUrl(fotoPath);
      }
    }

    return _TokenAsist(
      idToken: m['id_token'].toString(),
      idEvento: m['id_evento'].toString(),
      idUsuario: m['id_usuario'].toString(),
      idReservaGrupal: m['id_reserva_grupal']?.toString(),
      codigoPuerta: m['codigo_puerta']?.toString(),
      estado: (m['estado_token'] as String?) ?? 'pendiente',
      fechaCreacion: _parseDate(m['fecha_creacion']),
      snapshotSquad: snap,
      username: username,
      nombreSolicitante: nombre,
      edadSolicitante: edad,
      avatarUrlSolicitante: avatarUrl,
    );
  }
}

/// Un grupo representa una unidad de reserva:
/// - Squad: 1 token con id_reserva_grupal + snapshot_squad
/// - Individual: 1 token sin id_reserva_grupal
class _GrupoAsist {
  final String? idReserva;
  final List<_TokenAsist> tokens;

  const _GrupoAsist({required this.idReserva, required this.tokens});

  bool get esSquad => tokens.isNotEmpty && tokens.first.esSquad;

  /// Total de personas que entran con esta reserva.
  int get cantidadPersonas {
    if (tokens.isEmpty) return 0;
    return tokens.first.cantidadPersonas;
  }

  _TokenAsist get tokenPrincipal => tokens.first;
}

/// Agrupa una lista de tokens por su id_reserva_grupal.
List<_GrupoAsist> _agrupar(List<_TokenAsist> tokens) {
  final mapa = <String?, List<_TokenAsist>>{};
  for (final t in tokens) {
    (mapa[t.idReservaGrupal] ??= []).add(t);
  }
  // Individuales primero, luego squads.
  final individuales = mapa.entries.where((e) => e.key == null).map((e) => _GrupoAsist(idReserva: null, tokens: e.value));
  final squads = mapa.entries.where((e) => e.key != null).map((e) => _GrupoAsist(idReserva: e.key, tokens: e.value));
  return [...individuales, ...squads];
}

/// Perfil mínimo de un usuario para mostrar en cards (avatar + nombre + edad).
class _PerfilMini {
  final String id;
  final String? username;
  final String? nombre;
  final int? edad;
  final String? avatarUrl;

  const _PerfilMini({
    required this.id,
    this.username,
    this.nombre,
    this.edad,
    this.avatarUrl,
  });

  String get displayName {
    final n = nombre?.trim() ?? '';
    if (n.isNotEmpty) return n;
    final u = username?.trim() ?? '';
    if (u.isNotEmpty) return '@$u';
    return 'Usuario';
  }

  factory _PerfilMini.fromMap(Map<String, dynamic> m) {
    final fotoPath = m['foto_perfil_url']?.toString();
    String? avatarUrl;
    if (fotoPath != null && fotoPath.isNotEmpty) {
      avatarUrl = fotoPath.startsWith('http')
          ? fotoPath
          : ServicioSupabase()
              .cliente
              .storage
              .from('avatars')
              .getPublicUrl(fotoPath);
    }
    final edadRaw = m['edad'];
    return _PerfilMini(
      id: m['id'].toString(),
      username: m['username']?.toString(),
      nombre: m['nombre']?.toString(),
      edad: edadRaw is int
          ? edadRaw
          : (edadRaw != null ? int.tryParse(edadRaw.toString()) : null),
      avatarUrl: avatarUrl,
    );
  }
}

/// Avatar circular del solicitante. Si no hay foto, muestra icono placeholder.
class _AvatarUsuario extends StatelessWidget {
  final String? avatarUrl;
  final double size;

  const _AvatarUsuario({required this.avatarUrl, this.size = 52});

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final hasUrl = avatarUrl != null && avatarUrl!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ColoresLocales.cardLavanda,
        boxShadow: [
          BoxShadow(
            color: ColoresLocales.acentoVioleta.withOpacity(0.12),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: hasUrl
          ? Image.network(
              avatarUrl!,
              fit: BoxFit.cover,
              loadingBuilder: (ctx, child, progress) => progress == null
                  ? child
                  : ColoredBox(color: ColoresLocales.cardLavanda),
              errorBuilder: (_, __, ___) => _placeholder(),
            )
          : _placeholder(),
    );
  }

  Widget _placeholder() => Center(
        child: Icon(
          CupertinoIcons.person_fill,
          size: size * 0.5,
          color: ColoresLocales.acentoVioleta.withOpacity(0.6),
        ),
      );
}
