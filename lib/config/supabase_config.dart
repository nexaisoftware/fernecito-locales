/// Configuración centralizada de Supabase (misma que fernecito_frontend).
library;

import 'package:flutter_dotenv/flutter_dotenv.dart';

class ConfiguracionSupabase {
  static const String _nombreVariableUrl = 'URL_SUPABASE';
  static const String _nombreVariableClave = 'CLAVE_PUBLICA_SUPABASE';

  static String? obtenerUrl() => dotenv.env[_nombreVariableUrl];
  static String? obtenerClavePublica() => dotenv.env[_nombreVariableClave];

  static bool estaConfigurado() {
    final url = obtenerUrl();
    final clave = obtenerClavePublica();
    return url != null &&
        url.isNotEmpty &&
        clave != null &&
        clave.isNotEmpty &&
        url.startsWith('https://');
  }
}
