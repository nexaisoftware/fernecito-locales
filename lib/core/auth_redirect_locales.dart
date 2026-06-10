/// URL de redirect para auth (recuperar contraseña, confirmar email) — Fernecito Locales.
/// En web: misma URL del sitio. En app: scheme propio para que abra locales (no fernecito).
library;

import 'package:flutter/foundation.dart';

/// Producción PWA (Vercel).
const String kAuthRedirectWebLocalesProduccion = 'https://applocales.fernecitoapp.com/';

/// URL a la que Supabase redirige tras verificar el email o recuperar contraseña.
/// En web: el origen actual. En app móvil: fernecito-locales://auth-callback.
String get authRedirectUrlLocales {
  if (kIsWeb) {
    final origin = Uri.base.origin;
    if (origin.startsWith('http://') || origin.startsWith('https://')) {
      return origin.endsWith('/') ? origin : '$origin/';
    }
    return kAuthRedirectWebLocalesProduccion;
  }
  return 'fernecito-locales://auth-callback';
}
