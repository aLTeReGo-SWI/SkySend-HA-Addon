#!/bin/sh
set -e

CONFIG_PATH=/data/options.json

opt() {
  # $1 = jq filter, $2 = default
  jq -r "$1 // \"$2\"" "$CONFIG_PATH"
}

SSL=$(opt '.ssl' 'true')
CERTFILE=$(opt '.certfile' 'fullchain.pem')
KEYFILE=$(opt '.keyfile' 'privkey.pem')
# Must match the container-side port declared in config.yaml's 'ports:' map;
# users change the externally-exposed port from the add-on's Network settings
# in Home Assistant instead (Supervisor remaps host -> this fixed container port).
LISTEN_PORT=3333
BASE_URL=$(opt '.base_url' '')
PUID=$(opt '.puid' '1001')
PGID=$(opt '.pgid' '1001')
TZ_OPT=$(opt '.tz' 'Etc/UTC')
FILE_MAX_SIZE=$(opt '.file_max_size' '2GB')
ENABLED_SERVICES=$(jq -r '
  (.enabled_services // ["file","note"]) as $es |
  if ($es | type) == "array" then ($es | join(",")) else $es end
' "$CONFIG_PATH")

SSL_DIR=/ssl
CERT_PATH="${SSL_DIR}/${CERTFILE}"
KEY_PATH="${SSL_DIR}/${KEYFILE}"

if [ "$SSL" != "true" ]; then
  echo "[skysend-addon] ERROR: 'ssl' is disabled in the add-on configuration." >&2
  echo "This add-on always serves SkySend over HTTPS using the Home Assistant certificate; enable 'ssl' in the add-on options and restart." >&2
  exit 1
fi

if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
  echo "[skysend-addon] ERROR: certificate files not found at ${CERT_PATH} / ${KEY_PATH}." >&2
  echo "[skysend-addon] Make sure Home Assistant has an SSL certificate configured under /ssl (Settings > Add-ons, e.g. Let's Encrypt / Duck DNS add-on, or your own cert copied into the 'ssl' share)," >&2
  echo "[skysend-addon] and that 'certfile'/'keyfile' in this add-on's configuration match the actual file names in /ssl." >&2
  exit 1
fi

if [ -z "$BASE_URL" ]; then
  HA_HOSTNAME=$(hostname)
  BASE_URL="https://${HA_HOSTNAME}:${LISTEN_PORT}"
  echo "[skysend-addon] WARNING: 'base_url' is not set; defaulting to ${BASE_URL}." >&2
  echo "[skysend-addon] Set 'base_url' explicitly in the add-on configuration to the URL your users actually use to reach this add-on, or generated share links will be wrong." >&2
fi

export TZ="$TZ_OPT"
export PORT=3000
export HOST=127.0.0.1
export PUID="$PUID"
export PGID="$PGID"
export BASE_URL="$BASE_URL"
export TRUST_PROXY=true
export FILE_MAX_SIZE="$FILE_MAX_SIZE"
export ENABLED_SERVICES="$ENABLED_SERVICES"
export DATA_DIR=/data
# Keep uploads under /data so they persist via the add-on's automatically
# persisted /data volume, without needing an extra volume mapping.
export UPLOADS_DIR=/data/uploads

# OIDC / SSO (e.g. Microsoft Entra ID). SkySend requires OIDC_ISSUER,
# OIDC_CLIENT_ID and OIDC_CLIENT_SECRET to all be set together or it refuses
# to start, so validate that here with a clearer error than SkySend's own.
OIDC_ENABLED=$(opt '.oidc_enabled' 'false')
if [ "$OIDC_ENABLED" = "true" ]; then
  OIDC_PROVIDER=$(opt '.oidc_provider' 'generic')
  OIDC_ISSUER=$(opt '.oidc_issuer' '')
  OIDC_CLIENT_ID=$(opt '.oidc_client_id' '')
  OIDC_CLIENT_SECRET=$(opt '.oidc_client_secret' '')
  OIDC_PROTECT_FILES=$(opt '.oidc_protect_files' 'true')
  OIDC_PROTECT_NOTES=$(opt '.oidc_protect_notes' 'true')
  OIDC_REDIRECT_URI=$(opt '.oidc_redirect_uri' '')
  OIDC_SESSION_SECRET=$(opt '.oidc_session_secret' '')
  OIDC_SCOPES=$(opt '.oidc_scopes' 'openid profile email')
  OIDC_SESSION_DURATION=$(opt '.oidc_session_duration' '86400')

  if [ -z "$OIDC_ISSUER" ] || [ -z "$OIDC_CLIENT_ID" ] || [ -z "$OIDC_CLIENT_SECRET" ]; then
    echo "[skysend-addon] ERROR: 'oidc_enabled' is true but 'oidc_issuer', 'oidc_client_id' and 'oidc_client_secret' must all be set together." >&2
    echo "[skysend-addon] See the Configuration tab's OIDC field descriptions (or DOCS.md) for how to create the Entra ID app registration and get these values." >&2
    exit 1
  fi

  export OIDC_PROVIDER="$OIDC_PROVIDER"
  export OIDC_ISSUER="$OIDC_ISSUER"
  export OIDC_CLIENT_ID="$OIDC_CLIENT_ID"
  export OIDC_CLIENT_SECRET="$OIDC_CLIENT_SECRET"
  export OIDC_PROTECT_FILES="$OIDC_PROTECT_FILES"
  export OIDC_PROTECT_NOTES="$OIDC_PROTECT_NOTES"
  export OIDC_SCOPES="$OIDC_SCOPES"
  export OIDC_SESSION_DURATION="$OIDC_SESSION_DURATION"
  [ -n "$OIDC_REDIRECT_URI" ] && export OIDC_REDIRECT_URI="$OIDC_REDIRECT_URI"
  [ -n "$OIDC_SESSION_SECRET" ] && export OIDC_SESSION_SECRET="$OIDC_SESSION_SECRET"
fi

# Pass through any additional raw KEY=VALUE environment variables the user
# listed under 'extra_env' (e.g. CUSTOM_TITLE=MyShare). Read from a file
# (not a pipe) so the exports affect this shell, not a subshell.
EXTRA_ENV_FILE=$(mktemp)
jq -r '.extra_env // [] | .[]' "$CONFIG_PATH" > "$EXTRA_ENV_FILE"
while IFS='=' read -r key value; do
  [ -n "$key" ] && export "$key=$value"
done < "$EXTRA_ENV_FILE"
rm -f "$EXTRA_ENV_FILE"

export CERT_PATH KEY_PATH LISTEN_PORT
# Alpine's nginx package uses /etc/nginx/http.d/ for site configs (unlike
# the Debian/Ubuntu /etc/nginx/conf.d/ convention) - create it defensively
# in case the package layout ever changes, and drop its stock default site.
NGINX_SITE_DIR=/etc/nginx/http.d
mkdir -p "$NGINX_SITE_DIR"
rm -f "$NGINX_SITE_DIR/default.conf"
envsubst '${CERT_PATH} ${KEY_PATH} ${LISTEN_PORT}' \
  < /etc/nginx/templates/default.conf.template \
  > "$NGINX_SITE_DIR/default.conf"

echo "[skysend-addon] Starting SkySend on 127.0.0.1:${PORT} (internal only)..."
/usr/local/bin/docker-entrypoint.sh node apps/server/dist/index.js &
NODE_PID=$!

term_handler() {
  echo "[skysend-addon] Stopping..."
  kill -TERM "$NODE_PID" 2>/dev/null || true
  [ -n "${NGINX_PID:-}" ] && kill -TERM "$NGINX_PID" 2>/dev/null || true
  wait
  exit 0
}
trap term_handler TERM INT

echo "[skysend-addon] Starting nginx on port ${LISTEN_PORT} with certificate ${CERT_PATH}..."
nginx -g 'daemon off;' &
NGINX_PID=$!

wait "$NGINX_PID"
