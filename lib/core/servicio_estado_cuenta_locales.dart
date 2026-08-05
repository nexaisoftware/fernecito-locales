/// Switch de cuenta suspendida — una fuente de verdad vía RPC mi_estado_cuenta.
library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'motivos_pausa_cuenta.dart';

/// Rutas accesibles con la cuenta suspendida.
const Set<String> rutasPermitidasCuentaSuspendida = {
  '/cuenta_bloqueada',
  '/soporte',
  '/recargar_cuenta',
};

class ServicioEstadoCuentaLocales extends ChangeNotifier {
  ServicioEstadoCuentaLocales._();
  static final ServicioEstadoCuentaLocales instancia = ServicioEstadoCuentaLocales._();

  bool _suspendida = false;
  String? _motivoLabel;
  bool _cargando = false;

  bool get suspendida => _suspendida;
  String? get motivoLabel => _motivoLabel;
  bool get cargando => _cargando;

  bool rutaPermitida(String? nombre) {
    if (nombre == null) return false;
    return rutasPermitidasCuentaSuspendida.contains(nombre);
  }

  /// Refresca desde backend. Devuelve true si la cuenta sigue suspendida.
  Future<bool> refrescar() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      _suspendida = false;
      _motivoLabel = null;
      notifyListeners();
      return false;
    }

    _cargando = true;
    notifyListeners();

    try {
      final raw = await Supabase.instance.client.rpc('mi_estado_cuenta');
      final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      if (map['ok'] == true && map['tipo'] == 'local') {
        final activa = map['activa'] == true;
        _suspendida = !activa;
        _motivoLabel = map['motivo_label']?.toString() ??
            etiquetaMotivoPublico(map['motivo_publico']?.toString());
      } else {
        _suspendida = false;
        _motivoLabel = null;
      }
    } catch (_) {
      // Fallback lectura directa del perfil
      try {
        final row = await Supabase.instance.client
            .from('perfiles_locales')
            .select('estado_cuenta, pausada_motivo_publico')
            .eq('id', uid)
            .maybeSingle();
        _suspendida = (row?['estado_cuenta']?.toString() ?? 'activa') == 'pausada';
        _motivoLabel = etiquetaMotivoPublico(row?['pausada_motivo_publico']?.toString());
      } catch (_) {
        _suspendida = false;
      }
    } finally {
      _cargando = false;
      notifyListeners();
    }
    return _suspendida;
  }

  void limpiar() {
    _suspendida = false;
    _motivoLabel = null;
    notifyListeners();
  }
}
