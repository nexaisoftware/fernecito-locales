/// Perfil staff — nombre, username, DNI, fecha de nacimiento.
/// Hereda valores de perfiles_usuarios si la cuenta ya existe ahí.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/colores_staff.dart';
import '../core/constants.dart';
import '../core/servicio_staff_locales.dart';
import '../core/tema_app_locales.dart';
import '../widgets/scaffold_staff.dart';
import '../widgets/tema_locales_scope.dart';
import 'locales_staff_home.dart';

class LocalesStaffCrearPerfil extends StatefulWidget {
  const LocalesStaffCrearPerfil({super.key});

  @override
  State<LocalesStaffCrearPerfil> createState() => _LocalesStaffCrearPerfilState();
}

class _LocalesStaffCrearPerfilState extends State<LocalesStaffCrearPerfil> {
  final _nombre = TextEditingController();
  final _username = TextEditingController();
  final _dni = TextEditingController();
  bool _guardando = false;
  bool _cargandoHerencia = true;
  bool _usernameHeredado = false; // Si vino de perfiles_usuarios → readonly
  String? _fotoHeredada;
  DateTime? _fechaNacimiento;

  @override
  void initState() {
    super.initState();
    _intentarHeredar();
  }

  Future<void> _intentarHeredar() async {
    try {
      final perfil = await ServicioStaffLocales().cargarPerfilUsuarioPropio();
      if (!mounted) return;
      if (perfil != null) {
        final username = perfil['username']?.toString().trim() ?? '';
        final nombre = perfil['nombre']?.toString().trim() ?? '';
        final foto = perfil['foto_perfil_url']?.toString().trim();
        if (username.isNotEmpty) {
          _username.text = username;
          _usernameHeredado = true;
        }
        if (nombre.isNotEmpty && _nombre.text.isEmpty) {
          _nombre.text = nombre;
        }
        if (foto != null && foto.isNotEmpty) {
          _fotoHeredada = foto;
        }
      }
    } catch (_) {
      // Sin perfil de usuario — está OK, el staff completa todo manual.
    } finally {
      if (mounted) setState(() => _cargandoHerencia = false);
    }
  }

  String _textoFechaNacimiento() {
    final f = _fechaNacimiento;
    if (f == null) return 'Seleccionar fecha';
    String dos(int n) => n.toString().padLeft(2, '0');
    final edad = _edadDesdeFecha();
    final base = '${dos(f.day)}/${dos(f.month)}/${f.year}';
    return edad != null ? '$base  ·  $edad años' : base;
  }

  Future<void> _elegirFechaNacimiento() async {
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
    if (hoy.month < f.month || (hoy.month == f.month && hoy.day < f.day)) {
      edad--;
    }
    return edad;
  }

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();
    final username = _username.text.trim().toLowerCase();
    final dni = _dni.text.trim();
    final edad = _edadDesdeFecha();

    if (nombre.isEmpty || username.isEmpty) {
      _msg('Completá nombre y username.');
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
    if (!RegExp(r'^[a-z0-9_.]{3,20}$').hasMatch(username)) {
      _msg('Username: 3-20 caracteres, solo letras, números, _ o .');
      return;
    }

    setState(() => _guardando = true);
    try {
      await ServicioStaffLocales().guardarPerfilStaff(
        username: username,
        nombre: nombre,
        dni: dni,
        edad: edad,
        fechaNacimiento: _fechaNacimiento,
        fotoPerfilUrl: _fotoHeredada, // hereda foto del perfil de usuario si tenía
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LocalesStaffHome()),
        (_) => false,
      );
    } catch (e) {
      if (mounted) _msg('No se pudo guardar el perfil. Revisá el username (debe ser único).');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _msg(String t) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t, style: GoogleFonts.baloo2())),
    );
  }

  InputDecoration _dec(String hint, {Widget? suffix, bool enabled = true}) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: enabled ? ColoresStaff.rellenoInput : ColoresStaff.cardElevada,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        suffixIcon: suffix,
      );

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    if (_cargandoHerencia) {
      return ScaffoldStaff(
        fondo: ColoresStaff.fondoFormulario,
        body: const Center(child: CupertinoActivityIndicator()),
      );
    }
    final fotoUrl = ServicioStaffLocales().resolverUrlFotoPerfil(_fotoHeredada);
    final sinFecha = _fechaNacimiento == null;
    return ScaffoldStaff(
      fondo: ColoresStaff.fondoFormulario,
      appBar: appBarStaff(
        title: Text(
          'Tu perfil staff',
          style: GoogleFonts.baloo2(
            color: ColoresStaff.acento,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _usernameHeredado
                  ? 'Detectamos tu cuenta de usuario. Usamos tu username y foto, y podés ajustar el nombre.'
                  : 'Completá tus datos para empezar a trabajar.',
              style: GoogleFonts.baloo2(
                color: ColoresStaff.textoSecundario,
              ),
            ),
            if (fotoUrl != null) ...[
              const SizedBox(height: 16),
              Center(
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: ColoresStaff.cardLavanda,
                  backgroundImage: NetworkImage(fotoUrl),
                ),
              ),
            ],
            const SizedBox(height: 20),
            // Nombre (editable siempre — puede tener un alias "más prolijo")
            TextField(controller: _nombre, decoration: _dec('Nombre completo')),
            const SizedBox(height: 12),
            // Username (readonly si lo heredamos)
            TextField(
              controller: _username,
              enabled: !_usernameHeredado,
              decoration: _dec(
                'Username (@) — no se podrá cambiar después',
                enabled: !_usernameHeredado,
                suffix: _usernameHeredado
                    ? const Icon(CupertinoIcons.lock_fill, size: 18)
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dni,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _dec('DNI'),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _elegirFechaNacimiento,
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
                    : Text('Continuar', style: GoogleFonts.baloo2(fontWeight: FontWeight.w800, fontSize: 17)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
