/// Login staff — misma auth, modo staff persistido.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/auth_errors.dart';
import '../core/colores_staff.dart';
import '../core/constants.dart';
import '../core/modo_app_locales.dart';
import '../core/navegacion_auth_locales.dart';
import '../core/supabase_client.dart';
import '../widgets/scaffold_staff.dart';
import '../widgets/tema_locales_scope.dart';

class LocalesStaffLogin extends StatefulWidget {
  const LocalesStaffLogin({super.key});

  @override
  State<LocalesStaffLogin> createState() => _LocalesStaffLoginState();
}

class _LocalesStaffLoginState extends State<LocalesStaffLogin> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _ocultar = true;
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
    super.dispose();
  }

  Future<void> _entrar() async {
    final email = _email.text.trim();
    final pass = _pass.text;
    if (email.isEmpty || pass.isEmpty) {
      _error('Ingresá email y contraseña');
      return;
    }
    setState(() => _cargando = true);
    try {
      await ServicioSupabase().cliente.auth.signInWithPassword(
            email: email,
            password: pass,
          );
    } on AuthException catch (e) {
      if (mounted) _error(TraductorErroresAuth.traducir(e));
    } catch (_) {
      if (mounted) _error('No pudimos iniciar sesión. Intentá de nuevo.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _error(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: GoogleFonts.baloo2())),
    );
  }

  @override
  Widget build(BuildContext context) {
    TemaLocalesScope.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        volverAlLoginLocal(context);
      },
      child: ScaffoldStaff(
        safeAreaBottom: true,
        appBar: appBarStaff(
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: ColoresStaff.acento),
            onPressed: () => volverAlLoginLocal(context),
          ),
        ),
        body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 16),
              Text(
                'Staff Fernecito',
                textAlign: TextAlign.center,
                style: GoogleFonts.baloo2(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: ColoresStaff.acento,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Ingresá con tu cuenta de empleado para validar en puerta.',
                textAlign: TextAlign.center,
                style: GoogleFonts.baloo2(
                  fontSize: 14,
                  color: ColoresStaff.textoSecundario,
                ),
              ),
              SizedBox(height: 32),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'Email',
                  filled: true,
                  fillColor: ColoresStaff.rellenoInput,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(50)),
                ),
              ),
              SizedBox(height: 14),
              TextField(
                controller: _pass,
                obscureText: _ocultar,
                decoration: InputDecoration(
                  hintText: 'Contraseña',
                  filled: true,
                  fillColor: ColoresStaff.rellenoInput,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(50)),
                  suffixIcon: IconButton(
                    icon: Icon(_ocultar ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _ocultar = !_ocultar),
                  ),
                ),
              ),
              SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _cargando ? null : _entrar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ColoresStaff.acento,
                    foregroundColor: ColoresLocales.textoEnBoton,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                  ),
                  child: _cargando
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ColoresLocales.textoEnBoton,
                          ),
                        )
                      : Text('Entrar', style: GoogleFonts.baloo2(fontWeight: FontWeight.w800, fontSize: 17)),
                ),
              ),
              SizedBox(height: 14),
              OutlinedButton(
                onPressed: () => Navigator.pushNamed(context, '/staff_crear_cuenta'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ColoresStaff.acento,
                  side: BorderSide(color: ColoresStaff.acento, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                  minimumSize: Size.fromHeight(48),
                ),
                child: Text('Crear cuenta staff', style: GoogleFonts.baloo2(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
