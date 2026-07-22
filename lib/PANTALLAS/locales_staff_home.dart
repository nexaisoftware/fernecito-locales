/// Dashboard staff — locales habilitados + acciones.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/bootstrap_locales.dart';
import '../core/colores_staff.dart';
import '../core/servicio_staff_locales.dart';
import '../core/tema_app_locales.dart';
import '../core/permisos_staff_validar.dart';
import '../models/vinculo_staff_local.dart';
import '../widgets/splash_carga_locales.dart';
import '../widgets/scaffold_staff.dart';
import '../widgets/tema_locales_scope.dart';
import '../widgets/dialog_permiso_push_locales.dart';
import '../widgets/icono_local.dart';
import 'locales_validar.dart';

class LocalesStaffHome extends StatefulWidget {
  const LocalesStaffHome({super.key});

  @override
  State<LocalesStaffHome> createState() => _LocalesStaffHomeState();
}

class _LocalesStaffHomeState extends State<LocalesStaffHome> {
  final _servicio = ServicioStaffLocales();
  List<VinculoStaffLocal> _locales = const [];
  bool _cargando = true;
  String? _error;
  String? _nombreStaff;
  String? _fotoStaffUrl;

  @override
  void initState() {
    super.initState();
    _cargar();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      DialogPermisoPushLocales.mostrarSiCorresponde(context);
    });
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final perfil = await _servicio.cargarMiPerfilStaff();
      final lista = await _servicio.listarMisLocales();
      if (!mounted) return;
      setState(() {
        _nombreStaff = perfil?.nombre ?? perfil?.username ?? 'Staff';
        _fotoStaffUrl = _servicio.resolverUrlFotoPerfil(perfil?.fotoPerfilUrl);
        _locales = lista;
        _cargando = false;
      });
      BootstrapLocales.marcarLista();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos cargar tus locales.';
        _cargando = false;
      });
      BootstrapLocales.marcarLista();
    }
  }

  void _abrirValidar(VinculoStaffLocal v) {
    if (v.localBloqueado) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${v.nombreLocal} tiene la cuenta bloqueada. Comunicate con el '
            'administrador del local.',
            style: GoogleFonts.baloo2(),
          ),
          backgroundColor: ColoresStaff.cardElevada,
        ),
      );
      return;
    }
    if (!v.activo) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Estás en pausa en ${v.nombreLocal}. Pedile al local que te reactive.',
            style: GoogleFonts.baloo2(),
          ),
          backgroundColor: ColoresStaff.cardElevada,
        ),
      );
      return;
    }
    Navigator.push(
      context,
      CupertinoPageRoute<void>(
        builder: (_) => LocalesValidar(
          idLocalOperando: v.idLocal,
          permisosStaff: PermisosStaffValidar.desdeVinculo(v),
        ),
      ),
    );
  }

  Future<void> _abrirMiCuenta() async {
    await Navigator.pushNamed(context, '/staff_mi_cuenta');
    if (mounted) _cargar();
  }

  Widget _avatarPerfil({required double radius, double? iconSize}) {
    final icon = iconSize ?? radius;
    return CircleAvatar(
      radius: radius,
      backgroundColor: ColoresStaff.cardLavanda,
      backgroundImage:
          _fotoStaffUrl != null ? NetworkImage(_fotoStaffUrl!) : null,
      child: _fotoStaffUrl == null
          ? Icon(
              CupertinoIcons.person_solid,
              color: ColoresStaff.acento,
              size: icon,
            )
          : null,
    );
  }

  Widget _avatarAppBar({double size = 22}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: ColoresStaff.acento.withOpacity(0.35),
          width: 1.2,
        ),
      ),
      child: ClipOval(
        child: _fotoStaffUrl != null
            ? Image.network(
                _fotoStaffUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: ColoresStaff.cardLavanda,
                  child: Icon(
                    CupertinoIcons.person_solid,
                    color: ColoresStaff.acento,
                    size: size * 0.55,
                  ),
                ),
              )
            : ColoredBox(
                color: ColoresStaff.cardLavanda,
                child: Icon(
                  CupertinoIcons.person_solid,
                  color: ColoresStaff.acento,
                  size: size * 0.55,
                ),
              ),
      ),
    );
  }

  Widget _accionAppBar({
    required String label,
    required VoidCallback onTap,
    required Widget icono,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 24, height: 24, child: Center(child: icono)),
              const SizedBox(height: 2),
              Text(
                label,
                style: GoogleFonts.baloo2(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: ColoresStaff.acento,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _botonAdherirLocal() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () async {
          await Navigator.pushNamed(context, '/staff_vincular');
          _cargar();
        },
        icon: Icon(CupertinoIcons.plus_circle_fill, size: 18),
        label: Text(
          'Adherirme a un local',
          style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: ColoresStaff.acento,
          side: BorderSide(color: ColoresStaff.acento.withOpacity(0.4)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _contenidoDashboard() {
    final activos = _locales.where((v) => v.activo && !v.localBloqueado).length;
    final pausados = _locales.length - activos;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Row(
          children: [
            _avatarPerfil(radius: 24, iconSize: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hola, $_nombreStaff',
                    style: GoogleFonts.baloo2(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: ColoresStaff.textoPrincipal,
                    ),
                  ),
                  if (_locales.isNotEmpty)
                    Text(
                      pausados > 0
                          ? '$activos activos · $pausados en pausa'
                          : '$activos ${_locales.length == 1 ? 'local' : 'locales'}',
                      style: GoogleFonts.baloo2(
                        fontSize: 12,
                        color: ColoresStaff.textoSecundario,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Icon(
              CupertinoIcons.briefcase_fill,
              size: 18,
              color: ColoresStaff.acento,
            ),
            const SizedBox(width: 8),
            Text(
              'Mis lugares de trabajo',
              style: GoogleFonts.baloo2(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: ColoresStaff.textoPrincipal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_error != null)
          Text(_error!, style: GoogleFonts.baloo2(color: Colors.red.shade400))
        else if (_locales.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: ColoresStaff.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ColoresStaff.bordeSuave),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Todavía no estás adherido a ningún local.',
                  style: GoogleFonts.baloo2(
                    fontWeight: FontWeight.w800,
                    color: ColoresStaff.textoPrincipal,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Pedile la clave al dueño para sumarte.',
                  style: GoogleFonts.baloo2(
                    color: ColoresStaff.textoSecundario,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          )
        else
          ..._locales.map((v) {
            // La cuenta del local fue bloqueada por Fernecito (más severo que
            // el vínculo en pausa). Tiene prioridad de mensaje.
            final bloqueado = v.localBloqueado;
            final pausado = !bloqueado && !v.activo;
            final inactivo = bloqueado || pausado;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: ColoresStaff.card,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _abrirValidar(v),
                  child: Opacity(
                    opacity: bloqueado ? 0.5 : (pausado ? 0.72 : 1),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: ColoresStaff.cardLavanda,
                            child: IconoLocal(
                              size: 18,
                              color: ColoresStaff.acento,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        v.nombreLocal,
                                        style: GoogleFonts.baloo2(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          color: ColoresStaff.textoPrincipal,
                                        ),
                                      ),
                                    ),
                                    if (inactivo)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: bloqueado
                                              ? Colors.red.withValues(alpha: 0.12)
                                              : ColoresStaff.cardElevada,
                                          borderRadius: BorderRadius.circular(999),
                                          border: Border.all(
                                            color: bloqueado
                                                ? Colors.red.shade400
                                                    .withValues(alpha: 0.5)
                                                : ColoresStaff.bordeSuave,
                                          ),
                                        ),
                                        child: Text(
                                          bloqueado
                                              ? 'Cuenta bloqueada'
                                              : 'En pausa',
                                          style: GoogleFonts.baloo2(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w900,
                                            color: bloqueado
                                                ? Colors.red.shade400
                                                : ColoresStaff.textoSecundario,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                if (v.localUsername != null)
                                  Text(
                                    '@${v.localUsername}',
                                    style: GoogleFonts.baloo2(
                                      fontSize: 12,
                                      color: ColoresStaff.textoSecundario,
                                    ),
                                  ),
                                if (inactivo) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    bloqueado
                                        ? 'Este local tiene la cuenta bloqueada. '
                                            'Comunicate con el administrador del local.'
                                        : 'Pedile al local que te reactive para volver a operar.',
                                    style: GoogleFonts.baloo2(
                                      fontSize: 12,
                                      height: 1.25,
                                      color: bloqueado
                                          ? Colors.red.shade400
                                          : ColoresStaff.textoSecundario,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Icon(
                            bloqueado
                                ? CupertinoIcons.lock_fill
                                : pausado
                                    ? CupertinoIcons.pause_circle_fill
                                    : CupertinoIcons.chevron_right,
                            color: bloqueado
                                ? Colors.red.shade400
                                : pausado
                                    ? ColoresStaff.textoSecundario
                                    : ColoresStaff.acento,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        const SizedBox(height: 16),
        _botonAdherirLocal(),
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const ColoredBox(color: kVioletaSplashLocales);
    }
    final oscuro = TemaLocalesScope.of(context);
    final usarDegradado = ColoresStaff.usarDegradado;

    final body = RefreshIndicator(
      color: ColoresStaff.acento,
      onRefresh: _cargar,
      child: _contenidoDashboard(),
    );

    return ScaffoldStaff(
      conDegradado: usarDegradado,
      toolbarHeight: 64,
      appBar: appBarStaff(
        toolbarHeight: 64,
        title: Text(
          'Staff',
          style: GoogleFonts.baloo2(
            fontWeight: FontWeight.w900,
            color: ColoresStaff.acento,
          ),
        ),
        actions: [
          _accionAppBar(
            label: 'Historial',
            onTap: () => Navigator.pushNamed(context, '/staff_actividad'),
            icono: Icon(
              CupertinoIcons.clock_fill,
              size: 22,
              color: ColoresStaff.acento,
            ),
          ),
          _accionAppBar(
            label: oscuro ? 'Claro' : 'Oscuro',
            onTap: TemaAppLocales.instancia.toggle,
            icono: Icon(
              oscuro ? CupertinoIcons.sun_max_fill : CupertinoIcons.moon_fill,
              size: 22,
              color: ColoresStaff.acento,
            ),
          ),
          _accionAppBar(
            label: 'Perfil',
            onTap: _abrirMiCuenta,
            icono: _avatarAppBar(size: 22),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: body,
    );
  }
}
