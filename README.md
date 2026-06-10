# Fernecito - Locales App

Venue-facing dashboard for Fernecito.

Live PWA: [applocales.fernecitoapp.com](https://applocales.fernecitoapp.com)

## What It Does

Fernecito Locales App gives venues, bars and their staff a focused workspace to manage real operational flows.

Core flows:

- Create, edit and manage events.
- Publish promotions and control redemptions.
- Validate attendance, reservations and QR flows.
- Manage venue profile, images and public information.
- Invite and manage staff roles.
- Track operational status from a mobile-friendly PWA.

## Product Context

This app is one part of the Fernecito platform:

- Users App: discovery, reservations, squads and social event flows.
- Locales App: this repository, focused on venues and staff.
- Owner Manager: internal/admin operations for the platform.
- Backend: private Supabase project with Edge Functions and database logic.

## Stack

- Flutter / Dart
- Flutter Web as PWA
- Supabase Auth, Database, Storage and Realtime
- Edge Functions integration
- QR and staff workflows
- Vercel deployment

## Security Notes

This public repository is prepared for portfolio visibility. Production backend source, private migrations, secrets and operational credentials are not included.

Local `.env` files are ignored. Build-time values are injected with `--dart-define`, so environment files are not shipped as public web assets.

## Run Locally

```bash
flutter pub get
flutter run -d chrome \
  --dart-define=URL_SUPABASE="your-url" \
  --dart-define=CLAVE_PUBLICA_SUPABASE="your-anon-key"
```

## Production Build

```bash
./deploy.sh
```

The deploy script builds the Flutter web app and deploys the production PWA to Vercel.

## Why It Matters

This project shows product engineering around operational dashboards, role-based workflows, realtime backend integration and production PWA deployment.
