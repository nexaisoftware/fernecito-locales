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

  /// Portada de plan (`planes-portadas`). Path, asset o URL absoluta.
  String? urlPortadaPlan(String? pathOrUrl) {
    if (pathOrUrl == null || pathOrUrl.isEmpty) return null;
    if (pathOrUrl.startsWith('assets/') || pathOrUrl.startsWith('http')) {
      return pathOrUrl;
    }
    return cliente.storage.from('planes-portadas').getPublicUrl(pathOrUrl);
  }
}
