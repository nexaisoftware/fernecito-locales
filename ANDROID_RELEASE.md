# Release Android — Fernecito Locales

App **Locales** para Google Play. Cuenta de desarrollador: **nexaisoftware@gmail.com**
(ojo: sam97.c@gmail.com no tiene cuenta — cambiar de cuenta de Google en Play Console).

- **applicationId (permanente):** `com.fernecitoapp.locales`
- **Versionado:** `versionName` semver + `versionCode` entero SIEMPRE creciente, definidos en `pubspec.yaml` → `version: X.Y.Z+N`.

---

## Fase 0 — Estado

- [x] Package definitivo `com.fernecitoapp.locales` (build.gradle.kts, namespace, MainActivity.kt)
- [x] `compileSdk` = 36 · `targetSdk` = 35 (Play)
- [x] Firma release cableada a `android/key.properties` (con fallback a debug si no existe)
- [x] `.gitignore` protege `key.properties`, `*.jks`, `*.keystore`
- [ ] **Generar el keystore de upload** (paso manual, abajo)
- [ ] Crear `android/key.properties` desde `key.properties.example`
- [ ] Build del AAB y prueba en dispositivo

---

## 1. Generar el keystore (una sola vez)

Desde la carpeta `android/`:

```bash
cd android
keytool -genkey -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Te va a pedir una contraseña y algunos datos. **Guardá el `.jks` y las contraseñas en un gestor de
contraseñas + un backup externo.** Si perdés este keystore, no vas a poder volver a actualizar la app.

> Si activás **Play App Signing** (recomendado, es el default en Play Console), este keystore es solo
> el de *upload* y Google puede resetearlo si lo perdés — pero igual guardalo bien.

## 2. Crear `android/key.properties`

```bash
cp android/key.properties.example android/key.properties
```

Editá `android/key.properties` con tus contraseñas reales (`upload-keystore.jks` va en `android/`).

## 3. Build del AAB para Play

```bash
flutter clean
flutter pub get
flutter build appbundle --release
```

El AAB queda en: `build/app/outputs/bundle/release/app-release.aab`

Para probar en un dispositivo antes de subir (instala el APK release firmado):

```bash
flutter build apk --release
flutter install
```

## 4. Subir a Play Console

- Segmento **Prueba cerrada - Alpha** (o crear uno nuevo para esta app; es la primera versión de Locales).
- Subir el `.aab`, completar ficha de tienda, política de privacidad, content rating y data safety.

---

## OAuth Google (tras cambio de package)

El login con Google en la app nativa **no usa el package directamente en Dart**: abre el browser,
Supabase autentica y redirige al deep link `fernecito-locales://auth-callback`. Eso ya está cableado en:

- `lib/core/auth_redirect_locales.dart` → `kAuthRedirectMobileLocales`
- `AndroidManifest.xml` → intent-filter `fernecito-locales` / `auth-callback`
- `ios/Runner/Info.plist` → URL scheme `fernecito-locales`
- `supabase_flutter` escucha el deep link y completa la sesión (PKCE)

### Checklist externo (obligatorio si OAuth falla)

**1. Supabase → Authentication → URL Configuration**

Agregar en *Redirect URLs*:

- `https://applocales.fernecitoapp.com/`
- `fernecito-locales://auth-callback`
- `fernecito-locales://auth-callback/**` (wildcard recomendado)

**2. Google Cloud Console → APIs & Services → Credentials**

- El proveedor Google en Supabase usa el client **Web** (Client ID + Secret en el dashboard de Supabase).
- Si tenés un client **Android** con el package viejo (`com.example.frontendLocales`), crealo de nuevo o
  actualizalo con:
  - **Package name:** `com.fernecitoapp.locales`
  - **SHA-1 debug** (desarrollo local): `BE:84:6A:F0:B2:54:DE:2D:FA:72:21:04:59:1C:50:BD:1F:5E:37:0C`
  - **SHA-1 release:** sacarlo del keystore de upload (`./gradlew :app:signingReport` con Java/Android Studio)
- Client **iOS** (si publicás en App Store): bundle ID `com.fernecitoapp.locales`

**3. Probar en dispositivo**

```bash
flutter run
# Login → Continuar con Google → elegir cuenta → debe volver a la app sola
```

Si el browser queda colgado o no vuelve: casi siempre falta el redirect en Supabase o hay otra app
instalada que intercepta el mismo scheme.

---

## Pendientes de otras fases (no bloquean el build, pero sí la aprobación / calidad)

- **Fase 1 — Billing:** suscripciones digitales dentro del APK de Play deben usar **Google Play Billing**.
  Modelo híbrido acordado: Play Billing en Android, transferencia en la PWA (gateado por plataforma).
- **Fase 4 — Seguridad:** revisión de RLS/edge/CORS + verificación anti-estafa de locales.
- **Data safety / permisos:** el manifest pide `CAMERA`; declararlo en el formulario de Data Safety.
