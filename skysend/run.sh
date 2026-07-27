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
envsubst '${CERT_PATH} ${KEY_PATH} ${LISTEN_PORT}' \
  < /etc/nginx/templates/default.conf.template \
  > /etc/nginx/conf.d/default.conf

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
