library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants.dart';
import '../core/tema_app_locales.dart';
import '../widgets/tema_locales_scope.dart';
import '../core/servicio_edges_eventos.dart';
import '../core/servicio_staff_locales.dart';
import '../models/actividad_staff.dart';
import '../models/empleado_staff.dart';

class LocalesStaff extends StatefulWidget {
  const LocalesStaff({super.key});

  @override
  State<LocalesStaff> createState() => _LocalesStaffState();
}

class _LocalesStaffState extends State<LocalesStaff> {
  final _servicio = ServicioStaffLocales();

  List<EmpleadoStaff> _empleados = const [];
  String? _localUsername;
  bool _cargando = true;
  bool _generandoClave = false;
  String? _error;
  final Set<String> _accionEnCurso = {};

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _servicio.cargarUsernameLocal(),
        _servicio.listarEmpleados(),
      ]);
      if (!mounted) return;
      setState(() {
        _localUsername = results[0] as String?;
        _empleados = results[1] as List<EmpleadoStaff>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _mensajeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _mensajeError(Object e) {
    if (e is EdgeException) return e.mensaje;
    return 'No pudimos cargar tu staff. Reintentá.';
  }

  String _mensajeInvitacion({
    required String usernameLocal,
    required String clave,
  }) {
    return 'Hola! Unite a mi staff en Fernecito con este username de local: '
        '$usernameLocal, y esta clave de vinculación: $clave';
  }

  void _copiar(String texto, String label) {
    Clipboard.setData(ClipboardData(text: texto));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copiado', style: GoogleFonts.baloo2()),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  void _mostrarSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.baloo2()),
        backgroundColor: error ? const Color(0xFFDC2626) : null,
        duration: const Duration(milliseconds: 1800),
      ),
    );
  }

  Future<void> _abrirHistorialEmpleado(EmpleadoStaff e) async {
    final tituloEmpleado = e.nombre?.trim().isNotEmpty == true
        ? e.nombre!.trim()
        : (e.username.trim().isNotEmpty ? e.username.trim() : 'Staff');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return FractionallySizedBox(
          heightFactor: 0.82,
          child: Container(
            decoration: BoxDecoration(
              color: ColoresLocales.superficie,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(top: BorderSide(color: ColoresLocales.separador)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: ColoresLocales.bordeSuave,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Historial de $tituloEmpleado',
                        style: GoogleFonts.baloo2(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: ColoresLocales.acentoVioleta,
                        ),
                      ),
                      if (e.username.trim().isNotEmpty &&
                          e.nombre?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 2),
                        Text(
                          '@${e.username.trim()}',
                          style: GoogleFonts.baloo2(
                            fontSize: 12.5,
                            color: ColoresLocales.textoSecundarioOnFondoClaro,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        'Listas, invitaciones QR y canjes en tu local.',
                        style: GoogleFonts.baloo2(
                          fontSize: 13,
                          color: ColoresLocales.textoSecundarioOnFondoClaro,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: FutureBuilder<List<ActividadStaffItem>>(
                    future: _servicio.listarActividadEmpleado(idStaff: e.idStaff),
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return Center(
                          child: CircularProgressIndicator(color: ColoresLocales.acentoVioleta),
                        );
                      }
                      if (snap.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'No pudimos cargar el historial. Reintentá.',
                            style: GoogleFonts.baloo2(color: Colors.red.shade700),
                          ),
                        );
                      }
                      final items = snap.data ?? const [];
                      if (items.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'Todavía no hay acciones registradas para este empleado.',
                            style: GoogleFonts.baloo2(
                              color: ColoresLocales.textoSecundarioOnFondoClaro,
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _tileHistorialEmpleado(items[i]),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _fmtFechaHistorial(DateTime d) {
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

  Widget _chipHistorialMeta(String label, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (color ?? ColoresLocales.acentoVioleta).withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: (color ?? ColoresLocales.acentoVioleta).withOpacity(0.22),
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.baloo2(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color ?? ColoresLocales.acentoVioleta,
        ),
      ),
    );
  }

  Widget _tileHistorialEmpleado(ActividadStaffItem a) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ColoresLocales.cardLavanda,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: TemaAppLocales.instancia.esOscuro
              ? ColoresLocales.bordeSuave
              : a.colorEstado.withOpacity(0.20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: a.colorEstado.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(a.icono, color: a.colorEstado, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.baloo2(
                        fontWeight: FontWeight.w900,
                        color: ColoresLocales.textoOnFondoClaro,
                        fontSize: 14,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      a.tieneUsuario ? a.usuarioDisplay : 'Usuario no disponible',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.baloo2(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: ColoresLocales.textoOnFondoClaro,
                      ),
                    ),
                    if (a.infoGrupo != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        a.infoGrupo!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.baloo2(
                          fontSize: 11.5,
                          color: ColoresLocales.textoSecundarioOnFondoClaro,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
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
                    _fmtFechaHistorial(a.fecha),
                    style: GoogleFonts.baloo2(
                      fontSize: 11,
                      color: ColoresLocales.textoSecundarioOnFondoClaro,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chipHistorialMeta(a.subtitulo, color: a.colorEstado),
              if (a.codigoToken != null)
                _chipHistorialMeta('Cód. ${a.codigoToken}', color: a.colorEstado),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _abrirBottomSheetAgregar() async {
    final username = (_localUsername?.isNotEmpty == true)
        ? _localUsername!
        : 'tu_username_local';
    String? clave;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> generarClave() async {
              setSheetState(() => _generandoClave = true);
              try {
                final res = await _servicio.generarClaveVinculacion();
                final nueva = (res['clave_vinculacion']?.toString() ?? '').trim();
                if (nueva.isEmpty) {
                  throw EdgeException(
                    funcion: 'gestionar_staff',
                    status: 500,
                    code: 'empty_clave',
                    mensaje: 'No se recibió la clave del servidor',
                  );
                }
                setSheetState(() => clave = nueva);
              } catch (e) {
                if (mounted) _mostrarSnack(_mensajeError(e), error: true);
              } finally {
                setSheetState(() => _generandoClave = false);
              }
            }

            return FractionallySizedBox(
              heightFactor: 0.88,
              child: Container(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 18),
                decoration: BoxDecoration(
                  color: ColoresLocales.superficie,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border(
                    top: BorderSide(color: ColoresLocales.separador),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 46,
                          height: 5,
                          decoration: BoxDecoration(
                            color: ColoresLocales.bordeSuave,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Agregar empleado',
                        style: GoogleFonts.baloo2(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: ColoresLocales.acentoVioleta,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Flujo simple:',
                        style: GoogleFonts.baloo2(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: ColoresLocales.textoOnFondoClaro,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '1) Tu empleado se crea cuenta y entra por Staff.\n'
                        '2) Vos generás una clave de vinculación.\n'
                        '3) Le compartís tu username + clave.\n'
                        '4) Él la ingresa y queda unido a tu staff.',
                        style: GoogleFonts.baloo2(
                          fontSize: 13,
                          color: ColoresLocales.textoSecundarioOnFondoClaro,
                          height: 1.33,
                        ),
                      ),
                      SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _generandoClave ? null : generarClave,
                        icon: _generandoClave
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CupertinoActivityIndicator(color: ColoresLocales.textoEnBoton),
                              )
                            : Icon(CupertinoIcons.lock_fill, size: 18),
                        label: Text(
                          _generandoClave
                              ? 'Generando...'
                              : 'Generar código de vinculación',
                          style: GoogleFonts.baloo2(fontWeight: FontWeight.w900),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: ColoresLocales.botonVioletaFondo,
                          foregroundColor: ColoresLocales.botonVioletaTexto,
                          minimumSize: Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50),
                          ),
                        ),
                      ),
                      if (clave != null) ...[
                        SizedBox(height: 14),
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: ColoresLocales.superficieElevada,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: ColoresLocales.bordeSuave),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Listo. Compartí estos datos a tu empleado:',
                                style: GoogleFonts.baloo2(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: ColoresLocales.textoOnFondoClaro,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Válida 7 días. Al usarse se invalida sola.',
                                style: GoogleFonts.baloo2(
                                  fontSize: 12,
                                  color: ColoresLocales.textoSecundarioOnFondoClaro,
                                ),
                              ),
                              SizedBox(height: 10),
                              Text(
                                'Mi username',
                                style: GoogleFonts.baloo2(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: ColoresLocales.acentoVioleta,
                                ),
                              ),
                              SizedBox(height: 6),
                              OutlinedButton.icon(
                                onPressed: () => _copiar(username, 'Username'),
                                icon: Icon(CupertinoIcons.doc_on_doc, size: 17),
                                label: Text(
                                  username,
                                  style: GoogleFonts.baloo2(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15.5,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: Size.fromHeight(44),
                                  foregroundColor: ColoresLocales.acentoVioleta,
                                  backgroundColor: ColoresLocales.superficieElevada,
                                  side: BorderSide(color: ColoresLocales.bordeSuave),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(50),
                                  ),
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Clave de vinculación',
                                style: GoogleFonts.baloo2(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: ColoresLocales.acentoVioleta,
                                ),
                              ),
                              SizedBox(height: 6),
                              OutlinedButton.icon(
                                onPressed: () => _copiar(clave!, 'Clave'),
                                icon: Icon(CupertinoIcons.doc_on_doc, size: 17),
                                label: Text(
                                  clave!,
                                  style: GoogleFonts.baloo2(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15.5,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: Size.fromHeight(44),
                                  foregroundColor: ColoresLocales.acentoVioleta,
                                  backgroundColor: ColoresLocales.superficieElevada,
                                  side: BorderSide(color: ColoresLocales.bordeSuave),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(50),
                                  ),
                                ),
                              ),
                              SizedBox(height: 10),
                              FilledButton.icon(
                                onPressed: () => SharePlus.instance.share(
                                  ShareParams(
                                    text: _mensajeInvitacion(
                                      usernameLocal: username,
                                      clave: clave!,
                                    ),
                                  ),
                                ),
                                icon: Icon(CupertinoIcons.paperplane_fill),
                                label: Text(
                                  'Compartir clave y username',
                                  style: GoogleFonts.baloo2(fontWeight: FontWeight.w900),
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: ColoresLocales.botonVioletaFondo,
                                  foregroundColor: ColoresLocales.botonVioletaTexto,
                                  minimumSize: const Size.fromHeight(44),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(50),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

  Future<bool> _confirmarEliminar(String username) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Eliminar empleado',
          style: GoogleFonts.baloo2(fontWeight: FontWeight.w900),
        ),
        content: Text(
          '¿Seguro que querés eliminar a @$username?',
          style: GoogleFonts.baloo2(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar', style: GoogleFonts.baloo2()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Eliminar',
              style: GoogleFonts.baloo2(
                fontWeight: FontWeight.w900,
                color: const Color(0xFFDC2626),
              ),
            ),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _eliminarEmpleado(EmpleadoStaff e) async {
    final username = e.displayName;
    final ok = await _confirmarEliminar(username);
    if (!ok || !mounted) return;

    setState(() => _accionEnCurso.add(e.idStaff));
    try {
      await _servicio.eliminarEmpleado(idStaff: e.idStaff);
      if (!mounted) return;
      setState(() => _empleados = _empleados.where((x) => x.idStaff != e.idStaff).toList());
      _mostrarSnack('Empleado eliminado');
    } catch (err) {
      if (mounted) _mostrarSnack(_mensajeError(err), error: true);
    } finally {
      if (mounted) setState(() => _accionEnCurso.remove(e.idStaff));
    }
  }

  Future<void> _toggleActivo(EmpleadoStaff e) async {
    if (_accionEnCurso.contains(e.idStaff)) return;
    final nuevo = !e.activo;
    setState(() => _accionEnCurso.add(e.idStaff));
    try {
      await _servicio.toggleActivo(idStaff: e.idStaff, activo: nuevo);
      if (!mounted) return;
      setState(() {
        _empleados = _empleados
            .map((x) => x.idStaff == e.idStaff ? x.copyWith(activo: nuevo) : x)
            .toList();
      });
    } catch (err) {
      if (mounted) _mostrarSnack(_mensajeError(err), error: true);
    } finally {
      if (mounted) setState(() => _accionEnCurso.remove(e.idStaff));
    }
  }

  /// Togglea un permiso específico del empleado. Optimista: actualiza UI
  /// primero y revierte si la edge falla.
  Future<void> _togglePermiso(
    EmpleadoStaff e, {
    bool? aceptarListas,
    bool? qrPases,
    bool? qrPromos,
    bool? verListaAceptados,
    bool? qrInvitacion,
    bool? qrInvitacionPasarCupo,
  }) async {
    if (_accionEnCurso.contains(e.idStaff)) return;
    final original = e;
    final actualizado = e.copyWith(
      habilitadoAceptarListas: aceptarListas,
      habilitadoQrPases: qrPases,
      habilitadoQrPromos: qrPromos,
      habilitadoVerListaAceptados: verListaAceptados,
      habilitadoQrInvitacion: qrInvitacion,
      qrInvitacionPasarCupo: qrInvitacionPasarCupo,
    );
    setState(() {
      _accionEnCurso.add(e.idStaff);
      _empleados = _empleados
          .map((x) => x.idStaff == e.idStaff ? actualizado : x)
          .toList();
    });
    try {
      await _servicio.actualizarPermisos(
        idStaff: e.idStaff,
        habilitadoAceptarListas: aceptarListas,
        habilitadoQrPases: qrPases,
        habilitadoQrPromos: qrPromos,
        habilitadoVerListaAceptados: verListaAceptados,
        habilitadoQrInvitacion: qrInvitacion,
        qrInvitacionPasarCupo: qrInvitacionPasarCupo,
      );
    } catch (err) {
      // Revertir
      if (mounted) {
        setState(() {
          _empleados = _empleados
              .map((x) => x.idStaff == e.idStaff ? original : x)
              .toList();
        });
        _mostrarSnack(_mensajeError(err), error: true);
      }
    } finally {
      if (mounted) setState(() => _accionEnCurso.remove(e.idStaff));
    }
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final sinEmpleados = !_cargando && _error == null && _empleados.isEmpty;

    return Scaffold(
      backgroundColor: ColoresLocales.fondoClaro,
      appBar: AppBar(
        backgroundColor: ColoresLocales.fondoClaro,
        surfaceTintColor: ColoresLocales.fondoClaro,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: ColoresLocales.separador),
        ),
        centerTitle: true,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: Icon(CupertinoIcons.chevron_back, color: ColoresLocales.acentoVioleta),
        ),
        title: Text(
          'Mi staff',
          style: GoogleFonts.baloo2(
            fontWeight: FontWeight.w900,
            color: ColoresLocales.acentoVioleta,
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: ColoresLocales.acentoVioleta,
          onRefresh: _cargarDatos,
          child: SingleChildScrollView(
            physics: AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Mi staff',
                            style: GoogleFonts.baloo2(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: ColoresLocales.textoOnFondoClaro,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Gestioná permisos, historial y acceso de tu equipo.',
                      style: GoogleFonts.baloo2(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: ColoresLocales.textoSecundarioOnFondoClaro,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _abrirBottomSheetAgregar,
                      icon: Icon(CupertinoIcons.person_badge_plus_fill),
                      label: Text(
                        'Agregar empleado',
                        style: GoogleFonts.baloo2(fontWeight: FontWeight.w900),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: ColoresLocales.botonVioletaFondo,
                        foregroundColor: ColoresLocales.botonVioletaTexto,
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_cargando)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: CupertinoActivityIndicator(),
                        ),
                      )
                    else if (_error != null)
                      _buildError(_error!, _cargarDatos)
                    else if (sinEmpleados)
                      _emptyStaff()
                    else
                      ..._empleados.map(_cardEmpleado),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError(String msg, Future<void> Function() retry) {
    return Container(
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.35)),
      ),
      child: Column(
        children: [
          Text(msg, textAlign: TextAlign.center, style: GoogleFonts.baloo2()),
          SizedBox(height: 12),
          CupertinoButton(
            color: ColoresLocales.acentoVioleta,
            borderRadius: BorderRadius.circular(50),
            onPressed: retry,
            child: Text('Reintentar', style: GoogleFonts.baloo2(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _emptyStaff() {
    return Container(
      padding: EdgeInsets.fromLTRB(18, 22, 18, 20),
      decoration: ColoresLocales.decoracionCard(),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: ColoresLocales.superficieElevada,
              shape: BoxShape.circle,
              border: Border.all(color: ColoresLocales.bordeSuave),
            ),
            child: Icon(
              CupertinoIcons.add,
              size: 42,
              color: ColoresLocales.acentoVioleta,
            ),
          ),
          SizedBox(height: 14),
          Text(
            'Aún no tenés empleados.\n¿Deseás agregar ahora?',
            textAlign: TextAlign.center,
            style: GoogleFonts.baloo2(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: ColoresLocales.textoOnFondoClaro,
              height: 1.2,
            ),
          ),
          SizedBox(height: 14),
          FilledButton(
            onPressed: _abrirBottomSheetAgregar,
            style: FilledButton.styleFrom(
              backgroundColor: ColoresLocales.botonVioletaFondo,
              foregroundColor: ColoresLocales.botonVioletaTexto,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
            ),
            child: Text(
              'Agregar empleado',
              style: GoogleFonts.baloo2(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarEmpleado(EmpleadoStaff e, Color avatarColor) {
    final inicial = e.displayName.isNotEmpty
        ? e.displayName.substring(0, 1).toUpperCase()
        : '?';
    final fotoUrl = _servicio.resolverUrlFotoPerfil(e.fotoPerfilUrl);
    if (fotoUrl != null && fotoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundColor: avatarColor,
        backgroundImage: NetworkImage(fotoUrl),
        onBackgroundImageError: (_, __) {},
        child: Text(
          inicial,
          style: GoogleFonts.baloo2(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: ColoresLocales.acentoVioleta.withValues(alpha: 0.35),
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: 22,
      backgroundColor: avatarColor,
      child: Text(
        inicial,
        style: GoogleFonts.baloo2(
          fontWeight: FontWeight.w900,
          fontSize: 18,
          color: ColoresLocales.acentoVioleta,
        ),
      ),
    );
  }

  Widget _cardEmpleado(EmpleadoStaff e) {
    final username = e.displayName;
    final busy = _accionEnCurso.contains(e.idStaff);
    final avatarColor = e.avatarColorFor(e.idStaff);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: ColoresLocales.decoracionCard(radius: 20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Cabecera empleado ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
            decoration: BoxDecoration(
              color: ColoresLocales.cardLavanda,
              border: Border(
                bottom: BorderSide(color: ColoresLocales.separador),
              ),
            ),
            child: Row(
              children: [
                _avatarEmpleado(e, avatarColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        username.isNotEmpty ? '@$username' : 'Staff',
                        style: GoogleFonts.baloo2(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: ColoresLocales.textoOnFondoClaro,
                        ),
                      ),
                      if (e.nombre != null && e.nombre!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          e.nombre!.trim(),
                          style: GoogleFonts.baloo2(
                            fontSize: 12.5,
                            color: ColoresLocales.textoSecundarioOnFondoClaro,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _badgeEstadoEmpleado(e.activo),
                IconButton(
                  tooltip: 'Eliminar empleado',
                  onPressed: busy ? null : () => _eliminarEmpleado(e),
                  icon: const Icon(
                    CupertinoIcons.trash_fill,
                    color: Color(0xFFDC2626),
                    size: 19,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!e.activo)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: ColoresLocales.mostazaDestacado.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: ColoresLocales.mostazaBadge.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          CupertinoIcons.pause_circle_fill,
                          size: 18,
                          color: ColoresLocales.mostazaBadge,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Empleado pausado. Los permisos quedan guardados pero no puede operar hasta que lo habilites.',
                            style: GoogleFonts.baloo2(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: ColoresLocales.textoOnFondoClaro,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (e.activo) ...[
                  _SeccionPermisosEmpleado(
                    icono: CupertinoIcons.list_bullet,
                    color: ColoresLocales.acentoVioletaMarca,
                    titulo: 'Listas e invitaciones',
                    subtitulo: 'Listas, confirmados e invitaciones RRPP',
                    permisosActivos: _permisosListasActivos(e),
                    permisosTotal: _permisosListasTotal(e),
                    children: [
                      _FilaPermisoSwitch(
                        icono: CupertinoIcons.checkmark_seal_fill,
                        titulo: 'Aceptar y rechazar listas',
                        subtitulo: 'Confirmar o denegar solicitudes de entrada',
                        value: e.habilitadoAceptarListas,
                        disabled: busy,
                        onChanged: (v) => _togglePermiso(e, aceptarListas: v),
                      ),
                      _FilaPermisoSwitch(
                        icono: CupertinoIcons.person_2_fill,
                        titulo: 'Ver lista de aceptados',
                        subtitulo: 'Consultar quién ya quedó confirmado',
                        value: e.habilitadoVerListaAceptados,
                        disabled: busy,
                        onChanged: (v) => _togglePermiso(e, verListaAceptados: v),
                      ),
                      _FilaPermisoSwitch(
                        icono: CupertinoIcons.qrcode,
                        titulo: 'Otorgar QR de RRPP',
                        subtitulo: 'Generar invitaciones para eventos',
                        value: e.habilitadoQrInvitacion,
                        disabled: busy,
                        onChanged: (v) => _togglePermiso(
                          e,
                          qrInvitacion: v,
                          qrInvitacionPasarCupo: v ? null : false,
                        ),
                      ),
                      if (e.habilitadoQrInvitacion)
                        _FilaPermisoCheckbox(
                          titulo: 'Pasar grupo con lista llena',
                          subtitulo:
                              'Sigue aceptando invitados del QR aunque el cupo del evento ya esté completo.',
                          tooltip:
                              'Útil para RRPP que traen grupos grandes. Sin esto, al completarse el cupo del evento el QR deja de sumar gente.',
                          value: e.qrInvitacionPasarCupo,
                          disabled: busy,
                          onChanged: (v) =>
                              _togglePermiso(e, qrInvitacionPasarCupo: v),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _SeccionPermisosEmpleado(
                    icono: CupertinoIcons.qrcode_viewfinder,
                    color: const Color(0xFF059669),
                    titulo: 'Canje de QR',
                    subtitulo: 'Validación en puerta del local',
                    permisosActivos: _permisosQrActivos(e),
                    permisosTotal: 2,
                    children: [
                      _FilaPermisoSwitch(
                        icono: CupertinoIcons.ticket_fill,
                        titulo: 'Canjear QR de pases',
                        value: e.habilitadoQrPases,
                        disabled: busy,
                        onChanged: (v) => _togglePermiso(e, qrPases: v),
                      ),
                      _FilaPermisoSwitch(
                        icono: CupertinoIcons.gift_fill,
                        titulo: 'Canjear QR de promos',
                        value: e.habilitadoQrPromos,
                        disabled: busy,
                        onChanged: (v) => _togglePermiso(e, qrPromos: v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : () => _abrirHistorialEmpleado(e),
                        icon: const Icon(CupertinoIcons.time_solid, size: 16),
                        label: Text(
                          'Historial',
                          style: GoogleFonts.baloo2(fontWeight: FontWeight.w900),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ColoresLocales.acentoVioleta,
                          side: BorderSide(
                            color: ColoresLocales.acentoVioleta.withValues(alpha: 0.35),
                          ),
                          backgroundColor: ColoresLocales.superficieElevada,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: busy ? null : () => _toggleActivo(e),
                        icon: Icon(
                          busy
                              ? CupertinoIcons.clock
                              : (e.activo
                                  ? CupertinoIcons.pause_circle_fill
                                  : CupertinoIcons.play_circle_fill),
                          size: 16,
                        ),
                        label: Text(
                          busy ? '...' : (e.activo ? 'Pausar' : 'Habilitar'),
                          style: GoogleFonts.baloo2(fontWeight: FontWeight.w900),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: e.activo
                              ? ColoresLocales.botonVioletaFondo
                              : const Color(0xFF059669),
                          foregroundColor: ColoresLocales.botonVioletaTexto,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _permisosListasActivos(EmpleadoStaff e) {
    var n = 0;
    if (e.habilitadoAceptarListas) n++;
    if (e.habilitadoVerListaAceptados) n++;
    if (e.habilitadoQrInvitacion) n++;
    if (e.habilitadoQrInvitacion && e.qrInvitacionPasarCupo) n++;
    return n;
  }

  int _permisosListasTotal(EmpleadoStaff e) =>
      3 + (e.habilitadoQrInvitacion ? 1 : 0);

  int _permisosQrActivos(EmpleadoStaff e) {
    var n = 0;
    if (e.habilitadoQrPases) n++;
    if (e.habilitadoQrPromos) n++;
    return n;
  }

  Widget _badgeEstadoEmpleado(bool activo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: activo
            ? const Color(0xFF059669).withValues(alpha: 0.12)
            : ColoresLocales.superficieElevada,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: activo
              ? const Color(0xFF059669).withValues(alpha: 0.35)
              : ColoresLocales.bordeSuave,
        ),
      ),
      child: Text(
        activo ? 'Activo' : 'Pausado',
        style: GoogleFonts.baloo2(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: activo
              ? const Color(0xFF047857)
              : ColoresLocales.textoSecundarioOnFondoClaro,
        ),
      ),
    );
  }
}

// ─── Secciones de permisos (estilo suscripciones / pagos) ─────────────────────

class _SeccionPermisosEmpleado extends StatefulWidget {
  const _SeccionPermisosEmpleado({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.subtitulo,
    required this.permisosActivos,
    required this.permisosTotal,
    required this.children,
  });

  final IconData icono;
  final Color color;
  final String titulo;
  final String subtitulo;
  final int permisosActivos;
  final int permisosTotal;
  final List<Widget> children;

  @override
  State<_SeccionPermisosEmpleado> createState() =>
      _SeccionPermisosEmpleadoState();
}

class _SeccionPermisosEmpleadoState extends State<_SeccionPermisosEmpleado> {
  bool _expandido = false;

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final color = widget.color;
    final hayActivos = widget.permisosActivos > 0;

    return Container(
      decoration: BoxDecoration(
        color: ColoresLocales.superficieElevada,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: color.withValues(alpha: 0.08),
            child: InkWell(
              onTap: () => setState(() => _expandido = !_expandido),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                decoration: BoxDecoration(
                  border: _expandido
                      ? Border(
                          bottom: BorderSide(
                            color: color.withValues(alpha: 0.12),
                          ),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(widget.icono, size: 18, color: color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.titulo,
                            style: GoogleFonts.baloo2(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                              color: ColoresLocales.textoOnFondoClaro,
                            ),
                          ),
                          Text(
                            _expandido
                                ? widget.subtitulo
                                : '${widget.permisosActivos} de ${widget.permisosTotal} permisos activos · Tocá para ver opciones',
                            style: GoogleFonts.baloo2(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: ColoresLocales.textoSecundarioOnFondoClaro,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_expandido && hayActivos) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: color.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Text(
                          '${widget.permisosActivos}/${widget.permisosTotal}',
                          style: GoogleFonts.baloo2(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _expandido ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      child: Icon(
                        CupertinoIcons.chevron_down,
                        size: 16,
                        color: ColoresLocales.textoSecundarioOnFondoClaro,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            clipBehavior: Clip.hardEdge,
            child: _expandido
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < widget.children.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              color: ColoresLocales.separador,
                            ),
                          widget.children[i],
                        ],
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _FilaPermisoSwitch extends StatelessWidget {
  const _FilaPermisoSwitch({
    required this.icono,
    required this.titulo,
    this.subtitulo,
    required this.value,
    required this.disabled,
    required this.onChanged,
  });

  final IconData icono;
  final String titulo;
  final String? subtitulo;
  final bool value;
  final bool disabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            icono,
            size: 17,
            color: value
                ? ColoresLocales.acentoVioleta
                : ColoresLocales.textoSecundarioOnFondoClaro,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: GoogleFonts.baloo2(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: ColoresLocales.textoOnFondoClaro,
                  ),
                ),
                if (subtitulo != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitulo!,
                    style: GoogleFonts.baloo2(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: ColoresLocales.textoSecundarioOnFondoClaro,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Transform.scale(
            scale: 0.82,
            child: CupertinoSwitch(
              value: value,
              activeTrackColor: ColoresLocales.acentoVioleta,
              onChanged: disabled ? null : onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaPermisoCheckbox extends StatelessWidget {
  const _FilaPermisoCheckbox({
    required this.titulo,
    required this.subtitulo,
    required this.tooltip,
    required this.value,
    required this.disabled,
    required this.onChanged,
  });

  final String titulo;
  final String subtitulo;
  final String tooltip;
  final bool value;
  final bool disabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: value
          ? ColoresLocales.acentoVioletaMarca.withValues(alpha: 0.06)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: disabled ? null : () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    value: value,
                    activeColor: ColoresLocales.acentoVioleta,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                    onChanged: disabled
                        ? null
                        : (v) {
                            if (v != null) onChanged(v);
                          },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            titulo,
                            style: GoogleFonts.baloo2(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: ColoresLocales.textoOnFondoClaro,
                            ),
                          ),
                        ),
                        Tooltip(
                          message: tooltip,
                          preferBelow: false,
                          triggerMode: TooltipTriggerMode.tap,
                          showDuration: const Duration(seconds: 5),
                          child: Icon(
                            CupertinoIcons.info_circle,
                            size: 17,
                            color: ColoresLocales.acentoVioleta.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitulo,
                      style: GoogleFonts.baloo2(
                        fontSize: 11,
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
}
