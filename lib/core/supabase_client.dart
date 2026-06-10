/// Servicio singleton para acceso centralizado al cliente de Supabase.
/// Compartido con fernecito_frontend (mismo proyecto Supabase).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

class ServicioSupabase {
  static final ServicioSupabase _instancia = ServicioSupabase._interno();
  factory ServicioSupabase() => _instancia;
  ServicioSupabase._interno();

  SupabaseClient get cliente => Supabase.instance.client;
  User? get usuarioActual => cliente.auth.currentUser;
}
