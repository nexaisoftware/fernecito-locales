library;

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/bootstrap_locales.dart';
import '../core/vault_sesiones_locales.dart';
import '../widgets/switcher_cuentas_locales.dart';
import '../core/constants.dart';
import '../core/horarios_local.dart';
import '../core/tema_app_locales.dart';
import '../widgets/splash_carga_locales.dart';
import '../widgets/boton_modo_oscuro_locales.dart';
import '../widgets/badge_etiqueta_locales.dart';
import '../widgets/badge_plan_suscripcion.dart';
import '../widgets/dialog_permiso_push_locales.dart';
import '../widgets/tema_locales_scope.dart';
import '../core/navegacion_posicionamiento.dart';
import '../core/servicio_estado_cuenta_locales.dart';
import '../core/servicio_notificaciones_locales.dart';
import '../core/supabase_client.dart';
import '../core/suscripcion_locales.dart';
import '../core/programa_pioneros.dart';
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
  String? _descripcionLocal;
  String? _bannerLocalUrl;
  int _cantidadFotosLocal = 0;
  int _cantidadItemsCarta = 0;
  HorariosLocal _horariosLocal = {};
  int _eventosPublicados = 0;
  bool _avisoPerfilOcultoSesion = false;
  bool _avisoEventosOcultoSesion = false;
  bool _avisoCartaOcultoSesion = false;
  bool _localVerificado = false;
  bool _esPionero = false;
  int? _pioneroMesBeneficio;
  DateTime? _pioneroBeneficiosFin;
  String? _tipoSuscripcionRaw;
  DateTime? _fechaVencimientoSuscripcion;
  DateTime? _ultimaActualizacionCarta;
  bool _cargandoPerfil = true;
  CuposSuscripcionMock _cuposDashboard = const CuposSuscripcionMock(
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      DialogPermisoPushLocales.mostrarSiCorresponde(context);
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
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil('/cuenta_bloqueada', (_) => false);
  }

  Future<void> _cargarPerfilLocal() async {
    final uid = ServicioSupabase().usuarioActual?.id;
    if (uid == null) {
      setState(() => _cargandoPerfil = false);
      BootstrapLocales.marcarLista();
      return;
    }
    try {
      final row = await ServicioSupabase().cliente
          .from('perfiles_locales')
          .select(
            'foto_perfil_url, nombre_local, local_username, local_verificado, '
            'descripcion_local, url_foto_banner, horarios_json, '
            'foto_local_1, foto_local_2, foto_local_3, foto_local_4, foto_local_5, '
            'ultima_actualizacion_carta, '
            'plan_suscripcion, fecha_vencimiento_suscripcion, '
            'es_pionero, pionero_mes_beneficio, pionero_beneficios_fin',
          )
          .eq('id', uid)
          .maybeSingle();
      final ahoraIso = DateTime.now().toUtc().toIso8601String();
      final eventosRows = await ServicioSupabase().cliente
          .from('eventos')
          .select('id_evento')
          .eq('id_local', uid)
          .eq('estado_publicacion', 'publicado')
          .or(
            'fecha_fin_publicacion.gt.$ahoraIso,fecha_fin_publicacion.is.null',
          )
          .limit(2);
      final cartaRows = await ServicioSupabase().cliente
          .from('locales_carta_items')
          .select('id')
          .eq('id_local', uid)
          .eq('activo', true)
          .limit(2);
      final tipoRaw = await SuscripcionLocales.leerTipoRawDesdePerfil(uid);
      final planRawPerfil = row?['plan_suscripcion']?.toString().trim();
      final tipoRawEfectivo = (tipoRaw != null && tipoRaw.isNotEmpty)
          ? tipoRaw
          : planRawPerfil;
      final vencRaw = row?['fecha_vencimiento_suscripcion'];
      final vencimiento = vencRaw != null
          ? DateTime.tryParse(vencRaw.toString())?.toLocal()
          : null;
      final localVerificado = row?['local_verificado'] as bool? ?? false;
      final esPionero = row?['es_pionero'] == true;
      final pioneroMes = (row?['pionero_mes_beneficio'] as num?)?.toInt();
      final pioneroFinRaw = row?['pionero_beneficios_fin'];
      final pioneroFin = pioneroFinRaw != null
          ? DateTime.tryParse(pioneroFinRaw.toString())?.toLocal()
          : null;
      final ultimaCartaRaw = row?['ultima_actualizacion_carta'];
      final ultimaCarta = ultimaCartaRaw != null
          ? DateTime.tryParse(ultimaCartaRaw.toString())?.toLocal()
          : null;
      final pioneroBeneficiosActivo =
          esPionero && pioneroFin != null && pioneroFin.isAfter(DateTime.now());
      final tipoPlan = SuscripcionLocales.tipoPlanEfectivo(
        rawDb: tipoRawEfectivo,
        localVerificado: localVerificado,
        esPionero: esPionero,
        pioneroBeneficiosActivo: pioneroBeneficiosActivo,
        pioneroMesBeneficio: pioneroMes,
        fechaVencimiento: vencimiento,
      );
      final cupos = await SuscripcionLocales.leerCuposDesdePerfil(
        uid: uid,
        tipoPlan: tipoPlan,
      );
      // Multi-cuenta: asegurar/crear esta cuenta en el vault y refrescar su
      // cache visual (foto/nombre/@user). guardarActual hace upsert.
      unawaited(VaultSesionesLocales().guardarActual(
        nombreLocal: (row?['nombre_local'] as String?)?.trim(),
        localUsername: (row?['local_username'] as String?)?.trim(),
        fotoPerfilUrl: (row?['foto_perfil_url'] as String?)?.trim(),
      ));
      if (!mounted) return;
      final fotos = [
        row?['foto_local_1'],
        row?['foto_local_2'],
        row?['foto_local_3'],
        row?['foto_local_4'],
        row?['foto_local_5'],
      ].where((v) => v?.toString().trim().isNotEmpty == true).length;
      setState(() {
        _fotoPerfilUrl = row?['foto_perfil_url'] as String?;
        _nombreLocal = row?['nombre_local'] as String?;
        _usernameLocal = row?['local_username'] as String?;
        _descripcionLocal = row?['descripcion_local'] as String?;
        _bannerLocalUrl = row?['url_foto_banner'] as String?;
        _cantidadFotosLocal = fotos;
        _cantidadItemsCarta = (cartaRows as List).length;
        _horariosLocal = parseHorariosLocal(row?['horarios_json']);
        _eventosPublicados = (eventosRows as List).length;
        _localVerificado = localVerificado;
        _esPionero = esPionero;
        _pioneroMesBeneficio = pioneroMes;
        _pioneroBeneficiosFin = pioneroFin;
        _tipoSuscripcionRaw = tipoRawEfectivo;
        _fechaVencimientoSuscripcion = vencimiento;
        _ultimaActualizacionCarta = ultimaCarta;
        _cuposDashboard = cupos;
        _cargandoPerfil = false;
      });
      BootstrapLocales.marcarLista();
    } catch (_) {
      if (mounted) {
        setState(() => _cargandoPerfil = false);
        BootstrapLocales.marcarLista();
      }
    }
  }

  Future<void> _refrescarDashboard() async {
    await Future.wait([
      _cargarPerfilLocal(),
      ServicioNotificacionesLocales().refrescarContador(),
      _chequearSuspension(),
    ]);
  }

  List<_FaltantePerfil> _faltantesPerfilBasicos() {
    final faltantes = <_FaltantePerfil>[];
    if ((_fotoPerfilUrl ?? '').trim().isEmpty) {
      faltantes.add(const _FaltantePerfil('logo', 'logo'));
    }
    if ((_bannerLocalUrl ?? '').trim().isEmpty) {
      faltantes.add(const _FaltantePerfil('banner', 'banner'));
    }
    if ((_descripcionLocal ?? '').trim().length < 30) {
      faltantes.add(const _FaltantePerfil('descripcion', 'descripción'));
    }
    if (_horariosLocal.isEmpty) {
      faltantes.add(const _FaltantePerfil('horarios', 'horarios'));
    }
    if (_cantidadFotosLocal < 4) {
      faltantes.add(const _FaltantePerfil('fotos', 'fotos'));
    }
    return faltantes;
  }

  @override
  Widget build(BuildContext context) {
    if (_cargandoPerfil) {
      return const ColoredBox(color: kVioletaSplashLocales);
    }
    TemaLocalesScope.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: ColoresLocales.decoracionFondoPantalla,
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

  /// Cupos + chip verificado al inicio. Solo con dashboard activo.
  Widget _buildBarraPuntosDashboard() {
    if (_cargandoPerfil) return SizedBox.shrink();

    final cupos = _cuposDashboard;
    final tipoPlan = _tipoPlanDashboard();
    final mostrarVerificado =
        _esPionero || (_localVerificado && tipoPlan != 'Gratuita');
    final colorVerificado = _esPionero
        ? ProgramaPioneros.dorado
        : ColoresLocales.acentoVioleta;

    return Material(
      color: ColoresLocales.barraDashboard,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          children: [
            if (mostrarVerificado) ...[
              Container(
                padding: EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: ColoresLocales.superficieElevada,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      IconosLocales.verificado,
                      size: 12,
                      color: colorVerificado,
                    ),
                    SizedBox(width: 4),
                    Text(
                      _esPionero ? 'Pionero' : 'Verificado',
                      style: GoogleFonts.baloo2(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: colorVerificado,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
            ],
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _miniIconoNumero(
                      IconosFeaturesLocales.flyersIa,
                      cupos.flyersIa,
                      ColoresFeaturesLocales.flyersIa,
                    ),
                    _miniIconoNumero(
                      IconosFeaturesLocales.recomendadoFernecito,
                      cupos.recomendadosFernecito,
                      ColoresFeaturesLocales.recomendadoFernecito,
                    ),
                    _miniIconoNumero(
                      IconosFeaturesLocales.topCartelera,
                      cupos.topCartelera,
                      ColoresFeaturesLocales.topCartelera,
                    ),
                    _miniIconoNumero(
                      IconosFeaturesLocales.topUltra,
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

  String _tipoPlanDashboard() {
    if (!_localVerificado && !_esPionero) return 'Gratuita';
    final activo =
        _esPionero &&
        _pioneroBeneficiosFin != null &&
        _pioneroBeneficiosFin!.isAfter(DateTime.now());
    return SuscripcionLocales.tipoPlanEfectivo(
      rawDb: _tipoSuscripcionRaw,
      localVerificado: _localVerificado,
      esPionero: _esPionero,
      pioneroBeneficiosActivo: activo,
      pioneroMesBeneficio: _pioneroMesBeneficio,
      fechaVencimiento: _fechaVencimientoSuscripcion,
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
    return ColoredBox(
      color: ColoresLocales.barraNav,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: _navItem(
                  0,
                  CupertinoIcons.square_grid_2x2_fill,
                  'Dashboard',
                ),
              ),
              Expanded(
                child: _navItem(1, CupertinoIcons.calendar, 'Mis eventos'),
              ),
              Expanded(
                child: _navItem(
                  2,
                  CupertinoIcons.arrow_up_circle_fill,
                  'Posición',
                ),
              ),
              Expanded(child: _navItemNotis()),
              Expanded(child: _navItemAvatar(4, 'Mi local')),
            ],
          ),
        ),
      ),
    );
  }

  void _seleccionarTab(int index) {
    if (_indiceNav == index) return;
    HapticFeedback.selectionClick();
    setState(() => _indiceNav = index);
    if (index == 0) {
      _cargarPerfilLocal();
      _chequearSuspension();
      ServicioNotificacionesLocales().refrescarContador();
    } else if (index == 3) {
      ServicioNotificacionesLocales().refrescarContador();
    } else if (index == 4) {
      _cargarPerfilLocal();
    }
  }

  static const _navAnimDur = Duration(milliseconds: 280);
  static const _navAnimCurve = Curves.easeOutCubic;
  static const _navIconoTam = 24.0;
  static const _navZonaIconoTam = 32.0;
  static const _navEscalaActivo = 1.28;

  Widget _navIconoAnimado({required bool selected, required Widget child}) {
    return AnimatedScale(
      scale: selected ? _navEscalaActivo : 1,
      duration: _navAnimDur,
      curve: _navAnimCurve,
      alignment: Alignment.center,
      filterQuality: FilterQuality.medium,
      child: child,
    );
  }

  /// Área fija para todos los ítems: misma caja, misma escala activa.
  Widget _navZonaIcono({required bool selected, required Widget icon}) {
    return SizedBox(
      width: _navZonaIconoTam,
      height: _navZonaIconoTam,
      child: Center(
        child: _navIconoAnimado(selected: selected, child: icon),
      ),
    );
  }

  List<Shadow>? _sombrasIconoNavActivo(bool selected) {
    if (!selected) return null;
    if (TemaAppLocales.instancia.esOscuro) {
      return [
        Shadow(color: Colors.white.withValues(alpha: 0.55), blurRadius: 12),
        Shadow(color: Colors.white.withValues(alpha: 0.22), blurRadius: 22),
      ];
    }
    return [
      Shadow(
        color: ColoresLocales.acentoVioleta.withValues(alpha: 0.42),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
      Shadow(
        color: ColoresLocales.acentoVioleta.withValues(alpha: 0.18),
        blurRadius: 14,
        offset: const Offset(0, 1),
      ),
    ];
  }

  List<BoxShadow>? _glowAvatarNavActivo(bool selected) {
    if (!selected) return null;
    if (TemaAppLocales.instancia.esOscuro) {
      return [
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.38),
          blurRadius: 10,
          spreadRadius: 0.5,
        ),
        BoxShadow(color: Colors.white.withValues(alpha: 0.14), blurRadius: 18),
      ];
    }
    return [
      BoxShadow(
        color: ColoresLocales.acentoVioleta.withValues(alpha: 0.32),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ];
  }

  Widget _navShell({
    required int index,
    required String label,
    required Widget icon,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    final selected = _indiceNav == index;
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: SizedBox(
        height: 62,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _navZonaIcono(selected: selected, icon: icon),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: _navAnimDur,
                curve: _navAnimCurve,
                style: GoogleFonts.baloo2(
                  fontSize: selected
                      ? (label.length > 8 ? 10 : 11.5)
                      : (label.length > 8 ? 9.5 : 11),
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  color: selected
                      ? ColoresLocales.acentoVioleta
                      : ColoresLocales.textoSecundarioOnFondoClaro,
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final selected = _indiceNav == index;
    return _navShell(
      index: index,
      label: label,
      onTap: () => _seleccionarTab(index),
      icon: Icon(
        icon,
        size: _navIconoTam,
        color: selected
            ? ColoresLocales.acentoVioleta
            : ColoresLocales.textoSecundarioOnFondoClaro,
        shadows: _sombrasIconoNavActivo(selected),
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
    return _navShell(
      index: index,
      label: 'Notificaciones',
      onTap: () => _seleccionarTab(index),
      icon: ValueListenableBuilder<int>(
        valueListenable: ServicioNotificacionesLocales().contadorNoLeidas,
        builder: (context, sinLeer, _) {
          return SizedBox(
            width: _navIconoTam,
            height: _navIconoTam,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(
                  CupertinoIcons.bell_fill,
                  size: _navIconoTam,
                  color: colorActivo,
                  shadows: _sombrasIconoNavActivo(selected),
                ),
                if (sinLeer > 0)
                  Positioned(
                    right: -6,
                    top: -5,
                    child: IgnorePointer(
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 14,
                          minHeight: 14,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(
                            color: ColoresLocales.superficie,
                            width: 1.2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            sinLeer > 99 ? '99+' : '$sinLeer',
                            style: GoogleFonts.baloo2(
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              color: ColoresLocales.chipInactivo,
                              height: 1.0,
                            ),
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
    );
  }

  Widget _navItemAvatar(int index, String label) {
    final selected = _indiceNav == index;
    return _navShell(
      index: index,
      label: label,
      onTap: () => _seleccionarTab(index),
      // Hold en el avatar del navbar → switcher de cuentas (estilo Instagram).
      // El tap sigue navegando a "Mi local" como siempre.
      onLongPress: () => mostrarSwitcherCuentasLocales(context),
      icon: SizedBox(
        width: _navIconoTam,
        height: _navIconoTam,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? ColoresLocales.acentoVioleta
                  : ColoresLocales.bordeSuave,
              width: selected ? 2 : 1.3,
            ),
            boxShadow: _glowAvatarNavActivo(selected),
          ),
          child: ClipOval(
            child: _cargandoPerfil
                ? const Center(child: CupertinoActivityIndicator(radius: 8))
                : _fotoPerfilUrl != null && _fotoPerfilUrl!.isNotEmpty
                ? Image.network(
                    _fotoPerfilUrl!,
                    fit: BoxFit.cover,
                    width: _navIconoTam,
                    height: _navIconoTam,
                    errorBuilder: (_, __, ___) => _avatarFallback(),
                  )
                : _avatarFallback(),
          ),
        ),
      ),
    );
  }

  Widget _avatarFallback() {
    return ColoredBox(
      color: ColoresLocales.cardLavanda,
      child: Icon(
        CupertinoIcons.person_fill,
        color: ColoresLocales.acentoVioleta.withValues(alpha: 0.7),
        size: _navIconoTam * 0.72,
      ),
    );
  }

  Widget _badgePlan() {
    return BadgePlanSuscripcion(
      tipoPlan: _tipoPlanDashboard(),
      onTap: () => Navigator.pushNamed(context, '/administrar_subscripciones'),
    );
  }

  Widget _buildDashboard() {
    final displayUser = (_usernameLocal?.trim().isNotEmpty == true)
        ? _usernameLocal!.trim()
        : ((_nombreLocal?.trim().isNotEmpty == true)
              ? _nombreLocal!.trim()
              : 'local');
    final faltantesPerfil = _faltantesPerfilBasicos();
    final mostrarAvisoPerfil =
        faltantesPerfil.isNotEmpty && !_avisoPerfilOcultoSesion;
    final mostrarAvisoEventos =
        _eventosPublicados == 0 && !_avisoEventosOcultoSesion;
    final cartaDesactualizada = _cantidadItemsCarta > 0 &&
        (_ultimaActualizacionCarta == null ||
            DateTime.now().difference(_ultimaActualizacionCarta!).inDays >= 30);
    final mostrarAvisoCarta =
        cartaDesactualizada && !_avisoCartaOcultoSesion;

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
        subtitulo:
            'Control de acceso, listas de invitados y pases para tus eventos.',
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
      _Atajo(
        titulo: 'Planes',
        icon: CupertinoIcons.calendar,
        subtitulo:
            'Planes armados en tu local: proponé beneficios, aceptá pedidos y chateá con el grupo.',
      ),
    ];

    return RefreshIndicator(
      color: ColoresLocales.acentoVioleta,
      onRefresh: _refrescarDashboard,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                                    color: ColoresLocales
                                        .textoSecundarioOnFondoClaro,
                                  ),
                                ),
                              ),
                              const BotonModoOscuroLocales(),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _BotonDropdownCuenta(
                            onTap: () => mostrarSwitcherCuentasLocales(context),
                          ),
                        ],
                      ),
                    ),
                    if (!_cargandoPerfil) ...[SizedBox(width: 8), _badgePlan()],
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
                  final avisos = <Widget>[
                    if (mostrarAvisoPerfil)
                      _AvisoDashboardLocal(
                        icono: CupertinoIcons.wand_stars,
                        titulo: 'Tu perfil puede vender mucho más',
                        texto: _textoOportunidadPerfil(faltantesPerfil),
                        accion: 'Mejorar mi perfil',
                        onAccion: () => _seleccionarTab(4),
                        onCerrar: () {
                          setState(() => _avisoPerfilOcultoSesion = true);
                        },
                      ),
                    if (mostrarAvisoEventos)
                      _AvisoDashboardLocal(
                        icono: CupertinoIcons.ticket_fill,
                        titulo: 'Ganás más visibilidad con eventos',
                        texto:
                            'No tenés eventos publicados ahora. Subí una promo, flyer o fecha especial para aparecer en la cartelera.',
                        accion: 'Publicar evento',
                        onAccion: () =>
                            Navigator.pushNamed(context, '/crear_evento'),
                        onCerrar: () {
                          setState(() => _avisoEventosOcultoSesion = true);
                        },
                      ),
                    if (mostrarAvisoCarta)
                      _AvisoDashboardLocal(
                        icono: CupertinoIcons.list_bullet,
                        titulo: 'Tu carta puede vender más',
                        texto:
                            'Revisá precios y productos para que tus clientes decidan rápido y Fernecito IA recomiende tu local con datos frescos.',
                        accion: 'Actualizar carta',
                        onAccion: () => _seleccionarTab(4),
                        onCerrar: () {
                          setState(() => _avisoCartaOcultoSesion = true);
                        },
                      ),
                  ];
                  if (index < avisos.length) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: avisos[index],
                    );
                  }
                  final a = atajos[index - avisos.length];
                  return Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: a.estiloExclusivo
                        ? _buildCardAtajoExclusivo(a)
                        : _buildCardAtajo(a),
                  );
                },
                childCount:
                    atajos.length +
                    (mostrarAvisoPerfil ? 1 : 0) +
                    (mostrarAvisoEventos ? 1 : 0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _textoFaltantesPerfil(List<_FaltantePerfil> faltantes) {
    final nombres = faltantes.map((f) => f.nombre).take(4).toList();
    if (nombres.length == 1) return nombres.first;
    if (nombres.length == 2) return '${nombres[0]} y ${nombres[1]}';
    return '${nombres.sublist(0, nombres.length - 1).join(', ')} y ${nombres.last}';
  }

  String _textoOportunidadPerfil(List<_FaltantePerfil> faltantes) {
    final ids = faltantes.map((f) => f.id).toSet();
    if (ids.contains('horarios')) {
      return 'Agregá tus horarios para que la gente sepa cuándo estás abierto y pueda elegirte más fácil.';
    }
    if (ids.contains('descripcion')) {
      return 'Sumá una buena descripción para que Fernecito y los usuarios entiendan mejor qué ofrece tu local.';
    }
    if (ids.contains('banner') || ids.contains('logo')) {
      return 'Completá logo y banner para que tu local se vea más profesional en la app.';
    }
    if (ids.contains('fotos')) {
      return 'Agregá más fotos reales para mostrar la onda del lugar y generar más confianza.';
    }
    return 'Completá ${_textoFaltantesPerfil(faltantes)} para que tu local se vea más confiable y atractivo.';
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
          decoration: ColoresLocales.decoracionCard(
            exclusivo: true,
            sinBorde: true,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 76,
                height: 76,
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
          decoration: ColoresLocales.decoracionCard(sinBorde: true),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: Icon(
                  a.icon,
                  size: 42,
                  color: ColoresLocales.acentoVioleta,
                ),
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
    if (a.titulo == 'Planes') {
      Navigator.pushNamed(context, '/planes');
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

class _FaltantePerfil {
  const _FaltantePerfil(this.id, this.nombre);
  final String id;
  final String nombre;
}

class _AvisoDashboardLocal extends StatelessWidget {
  const _AvisoDashboardLocal({
    required this.icono,
    required this.titulo,
    required this.texto,
    required this.accion,
    required this.onAccion,
    required this.onCerrar,
  });

  final IconData icono;
  final String titulo;
  final String texto;
  final String accion;
  final VoidCallback onAccion;
  final VoidCallback onCerrar;

  @override
  Widget build(BuildContext context) {
    final mostaza = ColoresLocales.mostazaDestacado;
    final textoBase = TemaAppLocales.instancia.esOscuro
        ? Colors.white
        : ColoresLocales.tituloAcento;
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 7, 9),
      decoration: BoxDecoration(
        color: mostaza.withValues(
          alpha: TemaAppLocales.instancia.esOscuro ? 0.13 : 0.18,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: mostaza.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: mostaza.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icono, size: 15, color: mostaza),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: GoogleFonts.baloo2(
                    fontSize: 13.2,
                    fontWeight: FontWeight.w900,
                    color: textoBase,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  texto,
                  style: GoogleFonts.baloo2(
                    fontSize: 11.4,
                    fontWeight: FontWeight.w600,
                    color: textoBase.withValues(alpha: 0.76),
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: onAccion,
                  child: Text(
                    accion,
                    style: GoogleFonts.baloo2(
                      fontSize: 11.8,
                      fontWeight: FontWeight.w900,
                      color: mostaza,
                      height: 1,
                      decoration: TextDecoration.underline,
                      decorationColor: mostaza.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          GestureDetector(
            onTap: onCerrar,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Icon(
                CupertinoIcons.xmark,
                size: 14,
                color: textoBase.withValues(alpha: 0.55),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill chico "Cambiar de cuenta" del dashboard → abre el switcher multi-cuenta.
class _BotonDropdownCuenta extends StatelessWidget {
  const _BotonDropdownCuenta({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: ColoresLocales.acentoVioleta.withValues(alpha: 0.10),
              border: Border.all(
                color: ColoresLocales.acentoVioleta.withValues(alpha: 0.30),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.arrow_2_squarepath,
                    size: 15, color: ColoresLocales.acentoVioleta),
                const SizedBox(width: 7),
                Text(
                  'Cambiar de cuenta',
                  style: GoogleFonts.baloo2(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ColoresLocales.acentoVioleta,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(CupertinoIcons.chevron_down,
                    size: 13, color: ColoresLocales.acentoVioleta),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
