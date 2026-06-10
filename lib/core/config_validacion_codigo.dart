import 'evento_activo.dart';
import 'permisos_staff_validar.dart';

/// Configuración de la pantalla reutilizable de validación QR/manual.
class ConfigValidacionCodigo {
  const ConfigValidacionCodigo({
    required this.evento,
    this.tituloAppBar = 'Validar ingreso',
    this.permisosStaff,
  });

  final EventoActivo evento;
  final String tituloAppBar;
  final PermisosStaffValidar? permisosStaff;
}
