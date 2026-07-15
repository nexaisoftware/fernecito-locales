/// URL de redirect para auth (Google OAuth, confirmación de email, recovery) — Fernecito Locales.
/// En web: misma URL del sitio. En app: scheme propio para que abra locales (no fernecito app).
library;

import 'package:flutter/foundation.dart';

/// Producción PWA (Vercel).
const String kAuthRedirectWebLocalesProduccion = 'https://applocales.fernecitoapp.com/';

/// Deep link nativo (Android + iOS). Debe coincidir con:
/// - AndroidManifest.xml → intent-filter `fernecito-locales` / `auth-callback`
/// - iOS Info.plist → CFBundleURLSchemes `fernecito-locales`
/// - Supabase Auth → Redirect URLs (allow list)
const String kAuthRedirectMobileLocales = 'fernecito-locales://auth-callback';

/// Package / bundle definitivo de la app nativa (Play + App Store).
const String kPackageNativoLocales = 'com.fernecitoapp.locales';

/// URL a la que Supabase redirige tras OAuth Google, verificar email o recovery.
/// En web: el origen actual. En app móvil: [kAuthRedirectMobileLocales].
String get authRedirectUrlLocales {
  if (kIsWeb) {
    final origin = Uri.base.origin;
    if (origin.startsWith('http://') || origin.startsWith('https://')) {
      return origin.endsWith('/') ? origin : '$origin/';
    }
    return kAuthRedirectWebLocalesProduccion;
  }
  return kAuthRedirectMobileLocales;
}
