/// Vincular staff a un local con username + clave.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/colores_staff.dart';
import '../core/constants.dart';
import '../core/servicio_staff_locales.dart';
import '../widgets/scaffold_staff.dart';
import '../widgets/tema_locales_scope.dart';

class LocalesStaffVincular extends StatefulWidget {
  const LocalesStaffVincular({super.key});

  @override
  State<LocalesStaffVincular> createState() => _LocalesStaffVincularState();
}

class _LocalesStaffVincularState extends State<LocalesStaffVincular> {
  final _localUsername = TextEditingController();
  final _clave = TextEditingController();
  bool _cargando = false;

  @override
  void dispose() {
    _localUsername.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _vincular() async {
    final user = _localUsername.text.trim();
    final clave = _clave.text.trim().toUpperCase();
    if (user.isEmpty || clave.length != 8) {
      _msg('Ingresá el @ del local y la clave de 8 caracteres.');
      return;
    }
    setState(() => _cargando = true);
    try {
      final res = await ServicioStaffLocales().vincularStaff(
        localUsername: user,
        clave: clave,
      );
      if (!mounted) return;
      final msg = (res['message'] as String?) ?? '¡Listo! Ya podés operar en ese local.';
      _msg(msg);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _msg('No se pudo vincular. Revisá la clave o pedí una nueva.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _msg(String t) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t, style: GoogleFonts.baloo2()), backgroundColor: ColoresStaff.acento),
    );
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return ScaffoldStaff(
      fondo: ColoresStaff.fondoFormulario,
      appBar: appBarStaff(
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: Icon(CupertinoIcons.chevron_back, color: ColoresStaff.acento),
        ),
        title: Text(
          'Unirme a un local',
          style: GoogleFonts.baloo2(color: ColoresStaff.acento, fontWeight: FontWeight.w900),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'El dueño del local te comparte su @ y una clave de 8 caracteres (válida 7 días).',
              style: GoogleFonts.baloo2(color: ColoresStaff.textoSecundario, height: 1.35),
            ),
            SizedBox(height: 20),
            TextField(
              controller: _localUsername,
              decoration: InputDecoration(
                labelText: 'Username del local',
                prefixText: '@',
                filled: true,
                fillColor: ColoresStaff.rellenoInput,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: _clave,
              textCapitalization: TextCapitalization.characters,
              maxLength: 8,
              decoration: InputDecoration(
                labelText: 'Clave de vinculación',
                filled: true,
                fillColor: ColoresStaff.rellenoInput,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _cargando ? null : _vincular,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ColoresStaff.acento,
                  foregroundColor: ColoresLocales.textoEnBoton,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                ),
                child: _cargando
                    ? CupertinoActivityIndicator(color: ColoresLocales.textoEnBoton)
                    : Text('Confirmar', style: GoogleFonts.baloo2(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
