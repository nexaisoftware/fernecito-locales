# Fernecito Locales — PWA

PWA (Progressive Web App) para el panel de **locales** / negocios de Fernecito.

## Cómo ejecutar

```bash
# Desarrollo (web)
flutter run -d chrome

# Build para producción (PWA)
flutter build web
```

Los archivos generados estarán en `build/web/` (incluye `manifest.json`, service worker y assets para instalar como PWA).

## Plataformas

- **Web (PWA)** — principal
- iOS y Android — creados por defecto; puedes usarlos si más adelante quieres app nativa para locales

## Estructura

- `lib/main.dart` — punto de entrada
- `web/` — index.html, manifest.json, icons para PWA
