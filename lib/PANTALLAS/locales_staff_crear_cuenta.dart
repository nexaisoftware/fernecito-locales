/// Registro staff — signUp + modo staff.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/auth_errors.dart';
import '../core/auth_redirect_locales.dart';
import '../core/colores_staff.dart';
import '../core/constants.dart';
import '../core/modo_app_locales.dart';
import '../core/supabase_client.dart';
import '../widgets/scaffold_staff.dart';
import '../widgets/tema_locales_scope.dart';

class LocalesStaffCrearCuenta extends StatefulWidget {
  const LocalesStaffCrearCuenta({super.key});

  @override
  State<LocalesStaffCrearCuenta> createState() => _LocalesStaffCrearCuentaState();
}

class _LocalesStaffCrearCuentaState extends State<LocalesStaffCrearCuenta> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _rep = TextEditingController();
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    ModoAppLocales.instancia.establecerStaff();
  }

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _rep.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
    final email = _email.text.trim();
    if (email.isEmpty || _pass.text.length < 6) {
      _msg('Email válido y contraseña de al menos 6 caracteres.');
      return;
    }
    if (_pass.text != _rep.text) {
      _msg('Las contraseñas no coinciden.');
      return;
    }
    setState(() => _cargando = true);
    try {
      final r = await ServicioSupabase().cliente.auth.signUp(
            email: email,
            password: _pass.text,
            emailRedirectTo: authRedirectUrlLocales,
          );
      if (!mounted) return;
      if (r.user != null && r.session == null) {
        _msg(TraductorErroresAuth.mensajeSignupExitoso(email));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        _msg(TraductorErroresAuth.esCuentaYaRegistrada(e)
            ? TraductorErroresAuth.mensajeCuentaExistenteEnFernecito()
            : 'No se pudo crear la cuenta.');
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _msg(String t) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t, style: GoogleFonts.baloo2())));
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: ColoresStaff.rellenoInput,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      );

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return ScaffoldStaff(
      appBar: appBarStaff(
        title: Text(
          'Cuenta staff',
          style: GoogleFonts.baloo2(color: ColoresStaff.acento, fontWeight: FontWeight.w900),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(controller: _email, decoration: _dec('Email')),
            SizedBox(height: 12),
            TextField(controller: _pass, obscureText: true, decoration: _dec('Contraseña')),
            SizedBox(height: 12),
            TextField(controller: _rep, obscureText: true, decoration: _dec('Repetir contraseña')),
            SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _cargando ? null : _crear,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ColoresStaff.acento,
                  foregroundColor: ColoresLocales.textoEnBoton,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                ),
                child: Text('Registrarme', style: GoogleFonts.baloo2(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
