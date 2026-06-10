#!/usr/bin/env bash
# Deploy Fernecito LOCALES (Flutter web -> Vercel PWA)
# Subdominio: https://applocales.fernecitoapp.com
# Uso: ./deploy.sh
set -euo pipefail

cd "$(dirname "$0")"

echo "==> [1/3] flutter build web --release --base-href /"
flutter build web --release --base-href /

echo "==> [2/3] escribiendo build/web/vercel.json"
cat > build/web/vercel.json <<'JSON'
{
  "$schema": "https://openapi.vercel.sh/vercel.json",
  "cleanUrls": true,
  "rewrites": [
    { "source": "/(.*)", "destination": "/index.html" }
  ],
  "headers": [
    {
      "source": "/flutter_service_worker.js",
      "headers": [
        { "key": "Cache-Control", "value": "no-cache, no-store, must-revalidate" }
      ]
    },
    {
      "source": "/(index.html|main.dart.js|flutter_bootstrap.js|flutter.js|version.json)",
      "headers": [
        { "key": "Cache-Control", "value": "no-cache, no-store, must-revalidate" }
      ]
    },
    {
      "source": "/(.*)",
      "headers": [
        { "key": "X-Content-Type-Options", "value": "nosniff" }
      ]
    }
  ]
}
JSON

echo "==> [3/3] vercel deploy --prod (proyecto fernecito-locales)"
cd build/web
vercel link --project fernecito-locales --yes
vercel deploy --prod --yes

echo ""
echo "OK -> https://applocales.fernecitoapp.com"
