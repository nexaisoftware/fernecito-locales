/// Mi cuenta staff — perfil editable + locales vinculados + cerrar sesión.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/colores_staff.dart';
import '../core/constants.dart';
import '../core/modo_app_locales.dart';
import '../core/servicio_staff_locales.dart';
import '../core/tema_app_locales.dart';
import '../models/perfil_staff.dart';
import '../models/vinculo_staff_local.dart';
import '../widgets/scaffold_staff.dart';
import '../widgets/tema_locales_scope.dart';
import '../widgets/icono_local.dart';

class LocalesStaffMiCuenta extends StatefulWidget {
  const LocalesStaffMiCuenta({super.key});

  @override
  State<LocalesStaffMiCuenta> createState() => _LocalesStaffMiCuentaState();
}

class _LocalesStaffMiCuentaState extends State<LocalesStaffMiCuenta> {
  final _servicio = ServicioStaffLocales();
  PerfilStaff? _perfil;
  List<VinculoStaffLocal> _locales = const [];
  bool _cargando = true;
  String? _desvinculandoId;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final results = await Future.wait([
        _servicio.cargarMiPerfilStaff(),
        _servicio.listarMisLocales(),
      ]);
      if (!mounted) return;
      setState(() {
        _perfil = results[0] as PerfilStaff?;
        _locales = results[1] as List<VinculoStaffLocal>;
        _cargando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _msg(String t, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t, style: GoogleFonts.baloo2(color: Colors.white, fontWeight: FontWeight.w700)),
        backgroundColor: error ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _editarPerfil() async {
    final p = _perfil;
    if (p == null) return;
    final resultado = await Navigator.of(context).push<_EditResult?>(
      MaterialPageRoute(
        builder: (_) => _EditarPerfilStaff(perfilActual: p),
      ),
    );
    if (resultado != null && mounted) {
      await _cargar();
      _msg('Perfil actualizado');
    }
  }

  Future<void> _desvincular(VinculoStaffLocal v) async {
    // Doble confirmación.
    final paso1 = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('Desvincularte de "${v.nombreLocal}"'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Ya no vas a poder validar pases ni promos en este local hasta que te vuelvan a vincular con una clave nueva.',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (paso1 != true || !mounted) return;

    final paso2 = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('¿Estás seguro?'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Última confirmación. ¿Salir del staff de este local?'),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, salir'),
          ),
        ],
      ),
    );
    if (paso2 != true || !mounted) return;

    setState(() => _desvinculandoId = v.idLocal);
    try {
      await _servicio.desvincularDelLocal(idLocal: v.idLocal);
      if (!mounted) return;
      setState(() {
        _locales = _locales.where((x) => x.idLocal != v.idLocal).toList();
        _desvinculandoId = null;
      });
      _msg('Te desvinculaste de "${v.nombreLocal}"');
    } catch (e) {
      if (!mounted) return;
      setState(() => _desvinculandoId = null);
      _msg('No se pudo desvincular. Intentá de nuevo.', error: true);
    }
  }

  Future<void> _cerrarSesion() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Vas a volver a la pantalla de login.'),
        ),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    ModoAppLocales.instancia.establecerStaff();
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final p = _perfil;
    final fotoUrl = _servicio.resolverUrlFotoPerfil(p?.fotoPerfilUrl);
    return ScaffoldStaff(
      appBar: appBarStaff(
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: Icon(CupertinoIcons.chevron_back, color: ColoresStaff.acento),
        ),
        title: Text(
          'Mi cuenta',
          style: GoogleFonts.baloo2(fontWeight: FontWeight.w900, color: ColoresStaff.acento),
        ),
      ),
      body: _cargando
          ? Center(child: CircularProgressIndicator(color: ColoresStaff.acento))
          : RefreshIndicator(
              color: ColoresStaff.acento,
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  // Card perfil con botón editar
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: ColoresStaff.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: ColoresStaff.acento.withOpacity(0.18)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 32,
                              backgroundColor: ColoresStaff.cardLavanda,
                              backgroundImage: fotoUrl != null
                                  ? NetworkImage(fotoUrl)
                                  : null,
                              child: fotoUrl == null
                                  ? Icon(CupertinoIcons.person_solid, color: ColoresStaff.acento, size: 32)
                                  : null,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p?.nombre ?? '—',
                                    style: GoogleFonts.baloo2(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: ColoresStaff.textoPrincipal,
                                    ),
                                  ),
                                  Text(
                                    '@${p?.username ?? '—'}',
                                    style: GoogleFonts.baloo2(
                                      color: ColoresStaff.acento,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Editar',
                              onPressed: _editarPerfil,
                              icon: Icon(CupertinoIcons.pencil, color: ColoresStaff.acento),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Divider(color: ColoresStaff.acento.withOpacity(0.1), height: 1),
                        const SizedBox(height: 10),
                        _filaInfo('DNI', p?.dni ?? '—'),
                        if (p?.fechaNacimiento != null)
                          _filaInfo(
                            'Nacimiento',
                            '${p!.fechaNacimiento!.day.toString().padLeft(2, '0')}/${p.fechaNacimiento!.month.toString().padLeft(2, '0')}/${p.fechaNacimiento!.year}${p.edadCalculada != null ? '  ·  ${p.edadCalculada} años' : ''}',
                          )
                        else
                          _filaInfo('Edad', p?.edadCalculada?.toString() ?? '—'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Locales vinculados
                  Text(
                    'Mis vínculos',
                    style: GoogleFonts.baloo2(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: ColoresStaff.textoPrincipal,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_locales.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: ColoresStaff.card,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        'No estás vinculado a ningún local.',
                        style: GoogleFonts.baloo2(color: ColoresStaff.textoSecundario),
                      ),
                    )
                  else
                    ..._locales.map((v) {
                      final ocupado = _desvinculandoId == v.idLocal;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: ColoresStaff.card,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: ColoresStaff.acento.withOpacity(0.12)),
                          ),
                          child: Row(
                            children: [
                              IconoLocal(
                                size: 18,
                                color: ColoresStaff.acento,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      v.nombreLocal,
                                      style: GoogleFonts.baloo2(
                                        fontWeight: FontWeight.w800,
                                        color: ColoresStaff.textoPrincipal,
                                      ),
                                    ),
                                    if (v.localUsername != null)
                                      Text(
                                        '@${v.localUsername}',
                                        style: GoogleFonts.baloo2(
                                          fontSize: 12,
                                          color: ColoresStaff.textoSecundario,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: ocupado ? null : () => _desvincular(v),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red.shade700,
                                ),
                                child: ocupado
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : Text(
                                        'Salir',
                                        style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _cerrarSesion,
                    icon: const Icon(CupertinoIcons.square_arrow_right, size: 18),
                    label: Text('Cerrar sesión', style: GoogleFonts.baloo2(fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _filaInfo(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.baloo2(
              fontSize: 13,
              color: ColoresStaff.textoSecundario,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.baloo2(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: ColoresStaff.textoPrincipal,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditResult {
  const _EditResult();
}

/// Sub-pantalla para editar perfil staff. Username es readonly.
class _EditarPerfilStaff extends StatefulWidget {
  final PerfilStaff perfilActual;
  const _EditarPerfilStaff({required this.perfilActual});

  @override
  State<_EditarPerfilStaff> createState() => _EditarPerfilStaffState();
}

class _EditarPerfilStaffState extends State<_EditarPerfilStaff> {
  late final TextEditingController _nombre;
  late final TextEditingController _dni;
  DateTime? _fechaNacimiento;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: widget.perfilActual.nombre ?? '');
    _dni = TextEditingController(text: widget.perfilActual.dni ?? '');
    _fechaNacimiento = widget.perfilActual.fechaNacimiento;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _dni.dispose();
    super.dispose();
  }

  String _textoFechaNacimiento() {
    final f = _fechaNacimiento;
    if (f == null) return 'Seleccionar fecha';
    String dos(int n) => n.toString().padLeft(2, '0');
    final edad = _edadDesdeFecha();
    final base = '${dos(f.day)}/${dos(f.month)}/${f.year}';
    return edad != null ? '$base  ·  $edad años' : base;
  }

  Future<void> _elegirFecha() async {
    final ahora = DateTime.now();
    final DateTime minDate = DateTime(ahora.year - 100);
    final DateTime maxDate = DateTime(ahora.year - 16, ahora.month, ahora.day);
    final base = _fechaNacimiento ?? DateTime(ahora.year - 18, ahora.month, ahora.day);
    DateTime temporal = base.isBefore(minDate)
        ? minDate
        : (base.isAfter(maxDate) ? maxDate : base);

    final res = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: ColoresStaff.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SizedBox(
              height: 300,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: ColoresStaff.bordeSuave,
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
                            brightness: TemaAppLocales.instancia.esOscuro
                                ? Brightness.dark
                                : Brightness.light,
                          ),
                          child: CupertinoDatePicker(
                            mode: CupertinoDatePickerMode.date,
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: ColoresStaff.cardLavanda,
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(
                            color: ColoresStaff.acento.withOpacity(0.2),
                          ),
                        ),
                        child: Text(
                          'Año: ${temporal.year}',
                          style: GoogleFonts.baloo2(
                            color: ColoresStaff.acento,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text(
                            'Cancelar',
                            style: GoogleFonts.baloo2(
                              color: ColoresStaff.acento,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: () => Navigator.of(ctx).pop(temporal),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ColoresStaff.acento,
                            foregroundColor: ColoresLocales.textoEnBoton,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(50),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            elevation: 0,
        surfaceTintColor: Colors.transparent,
                          ),
                          child: Text(
                            'Listo',
                            style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
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
    if (res != null && mounted) setState(() => _fechaNacimiento = res);
  }

  int? _edadDesdeFecha() {
    final f = _fechaNacimiento;
    if (f == null) return null;
    final hoy = DateTime.now();
    var edad = hoy.year - f.year;
    if (hoy.month < f.month || (hoy.month == f.month && hoy.day < f.day)) edad--;
    return edad;
  }

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();
    final dni = _dni.text.trim();
    final edad = _edadDesdeFecha();

    if (nombre.isEmpty) {
      _msg('El nombre no puede quedar vacío');
      return;
    }
    if (dni.isEmpty) {
      _msg('Completá tu DNI.');
      return;
    }
    if (_fechaNacimiento == null || edad == null || edad < 16) {
      _msg('Indicá tu fecha de nacimiento (mín. 16 años).');
      return;
    }

    setState(() => _guardando = true);
    try {
      // El upsert necesita username, lo pasamos sin tocar (trigger SQL bloquea cambios).
      await ServicioStaffLocales().guardarPerfilStaff(
        username: widget.perfilActual.username ?? '',
        nombre: nombre,
        dni: dni,
        edad: edad,
        fechaNacimiento: _fechaNacimiento,
        fotoPerfilUrl: widget.perfilActual.fotoPerfilUrl,
      );
      if (!mounted) return;
      Navigator.pop(context, const _EditResult());
    } catch (e) {
      if (mounted) _msg('No se pudo guardar. Intentá de nuevo.');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _msg(String t) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t, style: GoogleFonts.baloo2())),
    );
  }

  InputDecoration _dec(String hint, {bool enabled = true, Widget? suffix}) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: enabled ? ColoresStaff.rellenoInput : ColoresStaff.cardElevada,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        suffixIcon: suffix,
      );

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    final sinFecha = _fechaNacimiento == null;
    return ScaffoldStaff(
      fondo: ColoresStaff.fondoFormulario,
      appBar: appBarStaff(
        title: Text(
          'Editar perfil',
          style: GoogleFonts.baloo2(color: ColoresStaff.acento, fontWeight: FontWeight.w900),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Username readonly siempre (inmutable post-creación).
            TextField(
              enabled: false,
              decoration: _dec(
                '@${widget.perfilActual.username ?? ''}',
                enabled: false,
                suffix: const Icon(CupertinoIcons.lock_fill, size: 18),
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: _nombre, decoration: _dec('Nombre')),
            const SizedBox(height: 12),
            TextField(
              controller: _dni,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _dec('DNI'),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _elegirFecha,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: ColoresStaff.cardLavanda,
                  border: Border.all(
                    color: ColoresStaff.acento.withOpacity(0.35),
                    width: 1.1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Fecha de nacimiento: ${_textoFechaNacimiento()}',
                        style: GoogleFonts.baloo2(
                          color: sinFecha
                              ? ColoresStaff.textoSecundario
                              : ColoresStaff.textoPrincipal,
                          fontWeight: sinFecha ? FontWeight.w500 : FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(
                      CupertinoIcons.calendar,
                      color: ColoresStaff.acento,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ColoresStaff.acento,
                  foregroundColor: ColoresLocales.textoEnBoton,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                ),
                child: _guardando
                    ? CupertinoActivityIndicator(color: ColoresLocales.textoEnBoton)
                    : Text('Guardar', style: GoogleFonts.baloo2(fontWeight: FontWeight.w800, fontSize: 17)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
