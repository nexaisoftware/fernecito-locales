library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants.dart';
import '../core/tema_app_locales.dart';
import '../widgets/boton_modo_oscuro_locales.dart';
import '../widgets/badge_etiqueta_locales.dart';
import '../widgets/tema_locales_scope.dart';
import '../core/navegacion_posicionamiento.dart';
import '../core/servicio_estado_cuenta_locales.dart';
import '../core/servicio_notificaciones_locales.dart';
import '../core/supabase_client.dart';
import '../core/suscripcion_locales.dart';
import 'locales_mis_eventos.dart';
import 'locales_perfil.dart';
import 'locales_notificaciones.dart';
import 'locales_posicionamiento.dart';

class LocalesHome extends StatefulWidget {
  const LocalesHome({super.key});

  @override
  State<LocalesHome> createState() => _LocalesHomeState();
}

class _LocalesHomeState extends State<LocalesHome> with WidgetsBindingObserver {
  final GlobalKey<LocalesPosicionamientoState> _keyPosicionamiento =
      GlobalKey<LocalesPosicionamientoState>();

  int _indiceNav = 0;
  String? _fotoPerfilUrl;
  String? _nombreLocal;
  String? _usernameLocal;
  bool _localVerificado = false;
  String? _tipoSuscripcionRaw;
  bool _cargandoPerfil = true;
  CuposSuscripcionMock _cuposDashboard =
      const CuposSuscripcionMock(
        flyersIa: 0,
        recomendadosFernecito: 0,
        topCartelera: 0,
        topUltra: 0,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargarPerfilLocal();
    _chequearSuspension();
    // Refresca contador de no-leídas al abrir la app (carga lazy en background).
    ServicioNotificacionesLocales().refrescarContador();
    NavegacionPosicionamiento.registrar((idEvento) {
      setState(() => _indiceNav = 2);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _keyPosicionamiento.currentState?.resaltarEventoPorId(idEvento);
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NavegacionPosicionamiento.registrar(null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Cuando la app vuelve de background a foreground → refrescar badge.
    // Cubre el caso: usuario abre la app, la deja minimizada, le llega una
    // notificación nueva y al volver ve el badge actualizado sin tocar nada.
    if (state == AppLifecycleState.resumed) {
      ServicioNotificacionesLocales().refrescarContador();
      _chequearSuspension();
    }
  }

  Future<void> _chequearSuspension() async {
    final suspendida = await ServicioEstadoCuentaLocales.instancia.refrescar();
    if (!mounted || !suspendida) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/cuenta_bloqueada', (_) => false);
  }

  Future<void> _cargarPerfilLocal() async {
    final uid = ServicioSupabase().usuarioActual?.id;
    if (uid == null) {
      setState(() => _cargandoPerfil = false);
      return;
    }
    try {
      final row = await ServicioSupabase().cliente
          .from('perfiles_locales')
          .select('foto_perfil_url, nombre_local, local_username, local_verificado')
          .eq('id', uid)
          .maybeSingle();
      final tipoRaw = await SuscripcionLocales.leerTipoRawDesdePerfil(uid);
      final localVerificado = row?['local_verificado'] as bool? ?? false;
      final tipoPlan = SuscripcionLocales.tipoPlanPago(
        rawDb: tipoRaw,
        localVerificado: localVerificado,
      );
      final cupos = await SuscripcionLocales.leerCuposDesdePerfil(
        uid: uid,
        tipoPlan: tipoPlan,
      );
      if (!mounted) return;
      setState(() {
        _fotoPerfilUrl = row?['foto_perfil_url'] as String?;
        _nombreLocal = row?['nombre_local'] as String?;
        _usernameLocal = row?['local_username'] as String?;
        _localVerificado = localVerificado;
        _tipoSuscripcionRaw = tipoRaw;
        _cuposDashboard = cupos;
        _cargandoPerfil = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargandoPerfil = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    TemaLocalesScope.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: TemaAppLocales.instancia.esOscuro
                  ? BoxDecoration(color: ColoresLocales.fondoClaro)
                  : BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: ColoresLocales.degradadoHome,
                        stops: const [0.0, 0.22, 0.55, 1.0],
                      ),
                    ),
            ),
          ),
          IndexedStack(
            index: _indiceNav,
            children: [
              _buildDashboard(),
              const LocalesMisEventos(),
              LocalesPosicionamiento(key: _keyPosicionamiento),
              LocalesNotificaciones(),
              LocalesPerfil(),
            ],
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_indiceNav == 0) _buildBarraPuntosDashboard(),
          _buildNavBar(),
        ],
      ),
    );
  }

  /// Chip de plan + iconos compactos de cupos (mock hasta Supabase). Solo con dashboard activo.
  Widget _buildBarraPuntosDashboard() {
    if (_cargandoPerfil) return SizedBox.shrink();

    final planChip = _etiquetaPlanBarra();
    final cupos = _cuposDashboard;

    return Material(
      color: ColoresLocales.barraDashboard,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: ColoresLocales.separador),
          ),
        ),
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: ColoresLocales.superficieElevada,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: ColoresLocales.bordeSuave),
              ),
              child: Text(
                planChip,
                style: GoogleFonts.baloo2(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: ColoresLocales.acentoVioleta,
                ),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _miniIconoNumero(
                      CupertinoIcons.sparkles,
                      cupos.flyersIa,
                      ColoresFeaturesLocales.flyersIa,
                    ),
                    _miniIconoNumero(
                      CupertinoIcons.hand_thumbsup_fill,
                      cupos.recomendadosFernecito,
                      ColoresFeaturesLocales.recomendadoFernecito,
                    ),
                    _miniIconoNumero(
                      CupertinoIcons.star_fill,
                      cupos.topCartelera,
                      ColoresFeaturesLocales.topCartelera,
                    ),
                    _miniIconoNumero(
                      CupertinoIcons.flame_fill,
                      cupos.topUltra,
                      ColoresFeaturesLocales.topUltra,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _etiquetaPlanBarra() {
    if (!_localVerificado) return 'Gratis';
    return SuscripcionLocales.tipoPlanPago(
      rawDb: _tipoSuscripcionRaw,
      localVerificado: true,
    );
  }

  Widget _miniIconoNumero(IconData icono, int valor, Color color) {
    return Padding(
      padding: EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 16, color: color),
          SizedBox(width: 3),
          Text(
            '$valor',
            style: GoogleFonts.baloo2(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: ColoresLocales.barraNav,
        border: Border(top: BorderSide(color: ColoresLocales.separador)),
        boxShadow: ColoresLocales.sombrasCard(),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            children: [
              Expanded(child: _navItem(0, CupertinoIcons.square_grid_2x2_fill, 'Dashboard')),
              Expanded(child: _navItem(1, CupertinoIcons.calendar, 'Mis eventos')),
              Expanded(child: _navItem(2, CupertinoIcons.arrow_up_circle_fill, 'Posición')),
              Expanded(child: _navItemNotis()),
              Expanded(child: _navItemAvatar(4, 'Mi local')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final selected = _indiceNav == index;
    return SizedBox(
      height: 60,
      child: InkWell(
        onTap: () {
          setState(() => _indiceNav = index);
          if (index == 0) {
            _cargarPerfilLocal();
            _chequearSuspension();
            ServicioNotificacionesLocales().refrescarContador();
          }
        },
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: selected ? ColoresLocales.acentoVioleta : ColoresLocales.textoSecundarioOnFondoClaro,
            ),
            SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.baloo2(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? ColoresLocales.acentoVioleta : ColoresLocales.textoSecundarioOnFondoClaro,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Nav item de Notificaciones con badge reactivo de "no leídas".
  /// Escucha el [ValueNotifier] del servicio para repintar el badge sin
  /// recargar el resto del nav.
  Widget _navItemNotis() {
    const index = 3;
    final selected = _indiceNav == index;
    final colorActivo = selected
        ? ColoresLocales.acentoVioleta
        : ColoresLocales.textoSecundarioOnFondoClaro;
    return SizedBox(
      height: 60,
      child: InkWell(
        onTap: () {
          setState(() => _indiceNav = index);
          // Al entrar al tab refrescamos contador (la pantalla lo refresca otra vez al cargar).
          ServicioNotificacionesLocales().refrescarContador();
        },
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ValueListenableBuilder<int>(
              valueListenable: ServicioNotificacionesLocales().contadorNoLeidas,
              builder: (context, sinLeer, _) {
                return SizedBox(
                  width: 30,
                  height: 26,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Icon(CupertinoIcons.bell_fill, size: 24, color: colorActivo),
                      if (sinLeer > 0)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            constraints: BoxConstraints(minWidth: 17, minHeight: 17),
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(50),
                              border: Border.all(color: ColoresLocales.superficie, width: 1.5),
                            ),
                            child: Center(
                              child: Text(
                                sinLeer > 99 ? '99+' : '$sinLeer',
                                style: GoogleFonts.baloo2(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: ColoresLocales.chipInactivo,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            Text(
              'Notis',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.baloo2(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: colorActivo,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItemAvatar(int index, String label) {
    final selected = _indiceNav == index;
    return SizedBox(
      height: 60,
      child: InkWell(
        onTap: () {
          setState(() => _indiceNav = index);
          _cargarPerfilLocal();
        },
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 30, // levemente mayor presencia visual que ícono plano
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? ColoresLocales.acentoVioleta : ColoresLocales.bordeSuave,
                  width: selected ? 2.2 : 1.4,
                ),
                boxShadow: selected && !TemaAppLocales.instancia.esOscuro
                    ? [
                        BoxShadow(
                          color: ColoresLocales.acentoVioleta.withOpacity(0.18),
                          blurRadius: 4,
                        ),
                      ]
                    : null,
              ),
              child: ClipOval(
                child: _cargandoPerfil
                    ? Center(child: CupertinoActivityIndicator())
                    : _fotoPerfilUrl != null && _fotoPerfilUrl!.isNotEmpty
                        ? Image.network(_fotoPerfilUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _avatarFallback())
                        : _avatarFallback(),
              ),
            ),
            SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.baloo2(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? ColoresLocales.acentoVioleta : ColoresLocales.textoSecundarioOnFondoClaro,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarFallback() {
    return Icon(CupertinoIcons.person_fill, color: ColoresLocales.acentoVioleta.withOpacity(0.7), size: 22);
  }

  Widget _badgeVerificado() {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/administrar_subscripciones'),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: ColoresLocales.mostazaBadge,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: ColoresLocales.acentoVioletaMarca.withOpacity(0.85),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.checkmark_seal_fill,
              size: 13,
              color: ColoresLocales.acentoVioletaMarca,
            ),
            SizedBox(width: 4),
            Text(
              'Perfil verificado',
              style: GoogleFonts.baloo2(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: ColoresLocales.acentoVioletaMarca,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboard() {
    final displayUser = (_usernameLocal?.trim().isNotEmpty == true)
        ? _usernameLocal!.trim()
        : ((_nombreLocal?.trim().isNotEmpty == true) ? _nombreLocal!.trim() : 'local');

    final atajos = [
      _Atajo(
        titulo: 'Nuevo evento',
        icon: CupertinoIcons.add_circled_solid,
        subtitulo:
            'Subí tus flyers, creá eventos creativos y llená tu local de clientes.',
      ),
      _Atajo(
        titulo: 'Flyer con IA',
        icon: CupertinoIcons.sparkles,
        subtitulo:
            'Creá flyers increíbles y súper llamativos con IA: en minutos, con tu estilo y listos para explotar la cartelera.',
        chipNuevo: true,
        estiloExclusivo: true,
      ),
      _Atajo(
        titulo: 'Listas y pases',
        icon: CupertinoIcons.list_bullet,
        subtitulo: 'Control de acceso, listas de invitados y pases para tus eventos.',
      ),
      _Atajo(
        titulo: 'Métricas',
        icon: CupertinoIcons.chart_bar_alt_fill,
        subtitulo: 'Ver tu rendimiento, historial de eventos y estadísticas.',
      ),
      _Atajo(
        titulo: 'Mi staff',
        icon: CupertinoIcons.person_2_fill,
        subtitulo: 'Gestioná tu equipo, permisos y quién hace qué en el local.',
      ),
    ];

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 32, 20, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hola, $displayUser!',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.baloo2(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: ColoresLocales.acentoVioleta,
                          ),
                        ),
                        SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '¿Qué querés hacer hoy?',
                                style: GoogleFonts.baloo2(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: ColoresLocales.textoSecundarioOnFondoClaro,
                                ),
                              ),
                            ),
                            const BotonModoOscuroLocales(),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_localVerificado) ...[
                    SizedBox(width: 8),
                    _badgeVerificado(),
                  ],
                ],
              ),
          ),
        ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final a = atajos[index];
                return Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: a.estiloExclusivo
                      ? _buildCardAtajoExclusivo(a)
                      : _buildCardAtajo(a),
                );
              },
              childCount: atajos.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCardAtajoExclusivo(_Atajo a) {
    final mostaza = ColoresLocales.mostazaDestacado;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onTapAtajo(a),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          decoration: ColoresLocales.decoracionCard(exclusivo: true),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: ColoresLocales.superficieElevada,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: mostaza.withOpacity(
                      TemaAppLocales.instancia.esOscuro ? 0.35 : 0.45,
                    ),
                  ),
                ),
                child: Icon(a.icon, size: 42, color: mostaza),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            a.titulo,
                            style: GoogleFonts.baloo2(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: ColoresLocales.tituloAcento,
                            ),
                          ),
                        ),
                        if (a.chipNuevo) const BadgeNuevoLocales(),
                      ],
                    ),
                    SizedBox(height: 6),
                    Text(
                      a.subtitulo,
                      style: GoogleFonts.baloo2(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: ColoresLocales.textoSecundarioOnFondoClaro,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardAtajo(_Atajo a) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onTapAtajo(a),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          decoration: ColoresLocales.decoracionCard(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: ColoresLocales.superficieElevada,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: ColoresLocales.bordeSuave),
                ),
                child: Icon(a.icon, size: 42, color: ColoresLocales.acentoVioleta),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      a.titulo,
                      style: GoogleFonts.baloo2(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: ColoresLocales.tituloAcento,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      a.subtitulo,
                      style: GoogleFonts.baloo2(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: ColoresLocales.textoSecundarioOnFondoClaro,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onTapAtajo(_Atajo a) {
    if (a.titulo == 'Flyer con IA') {
      Navigator.pushNamed(context, '/flyer_ia');
      return;
    }
    if (a.titulo == 'Nuevo evento') {
      Navigator.pushNamed(context, '/crear_evento');
      return;
    }
    if (a.titulo == 'Listas y pases') {
      Navigator.pushNamed(context, '/validar');
      return;
    }
    if (a.titulo == 'Métricas') {
      Navigator.pushNamed(context, '/metricas');
      return;
    }
    if (a.titulo == 'Mi staff') {
      Navigator.pushNamed(context, '/staff');
      return;
    }
  }

}

class _Atajo {
  final String titulo;
  final IconData icon;
  final String subtitulo;
  final bool chipNuevo;
  final bool estiloExclusivo;

  const _Atajo({
    required this.titulo,
    required this.icon,
    required this.subtitulo,
    this.chipNuevo = false,
    this.estiloExclusivo = false,
  });
}
