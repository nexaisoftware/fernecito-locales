#!/usr/bin/env bash
# Deploy Fernecito LOCALES (Flutter web -> Vercel PWA)
# Subdominio: https://applocales.fernecitoapp.com
# Uso: ./deploy.sh
set -euo pipefail

cd "$(dirname "$0")"

load_env_file() {
  local file="$1"
  while IFS='=' read -r key value || [ -n "$key" ]; do
    key="$(printf '%s' "$key" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case "$key" in ''|\#*) continue ;; esac
    value="$(printf '%s' "${value:-}" | tr -d '\r')"
    value="${value%\"}"
    value="${value#\"}"
    export "$key=$value"
  done < "$file"
}

if [ -f .env ]; then
  load_env_file .env
fi
if [ -z "${URL_SUPABASE:-}" ] && [ -f assets/.env ]; then
  load_env_file assets/.env
fi

: "${URL_SUPABASE:?Falta URL_SUPABASE en frontend_locales/.env, assets/.env o entorno}"
: "${CLAVE_PUBLICA_SUPABASE:?Falta CLAVE_PUBLICA_SUPABASE en frontend_locales/.env, assets/.env o entorno}"

echo "==> [1/3] flutter build web --release --base-href /"
flutter build web --release --base-href / \
  --dart-define=URL_SUPABASE="$URL_SUPABASE" \
  --dart-define=CLAVE_PUBLICA_SUPABASE="$CLAVE_PUBLICA_SUPABASE"

echo "==> [1b/3] deploy_id en build/web/version.json"
python3 - <<'PY'
import json, os, subprocess, time

path = "build/web/version.json"
with open(path, encoding="utf-8") as f:
    data = json.load(f)

git_ref = (os.environ.get("VERCEL_GIT_COMMIT_SHA") or "").strip()
if not git_ref:
    try:
        git_ref = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], text=True, stderr=subprocess.DEVNULL
        ).strip()
    except Exception:
        git_ref = "local"

# Un id único por deploy (mismo commit ≠ mismo deploy).
data["deploy_id"] = f"{git_ref[:12]}-{int(time.time())}"
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, separators=(",", ":"))
PY

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
      "source": "/assets/assets/.env",
      "headers": [
        { "key": "Cache-Control", "value": "no-store" },
        { "key": "X-Robots-Tag", "value": "noindex" }
      ]
    },
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
rm -f .env.local .env .env.production .env.development
vercel deploy --prod --yes

echo ""
echo "OK -> https://applocales.fernecitoapp.com"
