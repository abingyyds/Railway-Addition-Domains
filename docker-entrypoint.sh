#!/usr/bin/env bash
set -euo pipefail

export CLIENT_MAX_BODY_SIZE="${CLIENT_MAX_BODY_SIZE:-5G}"
export LISTEN_PORT="${PORT:-8080}"
export FORWARDED_PROTO="${FORWARDED_PROTO:-https}"
export FORWARDED_PORT="${FORWARDED_PORT:-443}"
export SUBROUTER_SCHEME="${SUBROUTER_SCHEME:-http}"
export SUBROUTER_HOST="${SUBROUTER_HOST:-subrouter.railway.internal}"
export SUBROUTER_PORT="${SUBROUTER_PORT:-3000}"
export SUBROUTER_PORTS="${SUBROUTER_PORTS:-${SUBROUTER_PORT},8080,8000,5000,80}"
export SUBROUTER_PROBE_TIMEOUT="${SUBROUTER_PROBE_TIMEOUT:-2}"
export UPSTREAM_AUTO_DETECT="${UPSTREAM_AUTO_DETECT:-true}"
export SUBROUTER_UPSTREAM="${SUBROUTER_UPSTREAM:-${SUBROUTER_SCHEME}://${SUBROUTER_HOST}:${SUBROUTER_PORT}}"

CONF_FILE="/etc/nginx/conf.d/default.conf"

# Fallback upstream when Host doesn't match any PROXY_ROUTE_n.
# Defaults to the Subrouter service on Railway private networking.
DEFAULT_UPSTREAM="${DEFAULT_UPSTREAM:-$SUBROUTER_UPSTREAM}"

upstream_host() {
  printf '%s' "$1" | sed -nE 's#^[a-zA-Z][a-zA-Z0-9+.-]*://([^/:]+)(:[0-9]+)?(/.*)?$#\1#p'
}

upstream_port() {
  printf '%s' "$1" | sed -nE 's#^[a-zA-Z][a-zA-Z0-9+.-]*://[^/:]+:([0-9]+)(/.*)?$#\1#p'
}

append_port() {
  port="$1"
  case "$port" in
    ''|*[!0-9]*) return ;;
  esac
  case " $probe_ports " in
    *" $port "*) return ;;
  esac
  probe_ports="${probe_ports} ${port}"
}

detect_subrouter_upstream() {
  current="$1"
  current_host="$(upstream_host "$current")"

  if [ "${UPSTREAM_AUTO_DETECT}" != "true" ] || [ "$current_host" != "$SUBROUTER_HOST" ]; then
    printf '%s' "$current"
    return
  fi

  probe_ports=""
  append_port "$(upstream_port "$current")"
  for port in $(printf '%s' "$SUBROUTER_PORTS" | tr ',;' '  '); do
    append_port "$port"
  done

  for port in $probe_ports; do
    candidate="${SUBROUTER_SCHEME}://${SUBROUTER_HOST}:${port}"
    echo "[entrypoint] probing Subrouter upstream tcp: ${SUBROUTER_HOST}:${port}" >&2
    if nc -z -w "$SUBROUTER_PROBE_TIMEOUT" "$SUBROUTER_HOST" "$port"; then
      echo "[entrypoint] selected Subrouter upstream: ${candidate}" >&2
      printf '%s' "$candidate"
      return
    fi
  done

  echo "[entrypoint] no probed Subrouter ports responded; keeping configured upstream: ${current}" >&2
  printf '%s' "$current"
}

DEFAULT_UPSTREAM="$(detect_subrouter_upstream "$DEFAULT_UPSTREAM")"

cat > "$CONF_FILE" <<EOF
log_format upstream_timing '\$remote_addr - \$host "\$request" \$status '
                           'upstream=\$upstream_addr upstream_status=\$upstream_status '
                           'request_time=\$request_time upstream_time=\$upstream_response_time';
access_log /dev/stdout upstream_timing;
error_log /dev/stderr info;

map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

resolver [fd12::10] ipv6=on valid=10s;
resolver_timeout 5s;
EOF

cat <<EOF
[entrypoint] listen port: ${LISTEN_PORT}
[entrypoint] default upstream: ${DEFAULT_UPSTREAM}
[entrypoint] forwarded proto: ${FORWARDED_PROTO}
[entrypoint] forwarded port: ${FORWARDED_PORT}
[entrypoint] subrouter probe ports: ${SUBROUTER_PORTS}
EOF

route_count=0
for i in 1 2 3 4 5; do
  var="PROXY_ROUTE_${i}"
  raw="${!var:-}"

  # Skip missing/empty
  [ -z "$raw" ] && continue

  # Normalize curly quotes that sometimes appear when copied from chat/apps
  route="$(printf '%s' "$raw" | sed 's/[“”]/"/g' | sed "s/[‘’]/'/g")"

  # Trim surrounding quotes if present
  route="${route#\"}"
  route="${route%\"}"
  route="${route#\'}"
  route="${route%\'}"

  # Expect: domain=scheme://host:port
  domain="${route%%=*}"
  upstream="${route#*=}"

  if [ -z "$domain" ] || [ -z "$upstream" ] || [ "$domain" = "$upstream" ]; then
    echo "[entrypoint] Invalid $var format. Expected: domain=scheme://host:port" >&2
    exit 1
  fi

  cat >> "$CONF_FILE" <<EOF

server {
    listen ${LISTEN_PORT};
    server_name $domain;

    client_max_body_size ${CLIENT_MAX_BODY_SIZE};

    proxy_connect_timeout 60s;
    proxy_send_timeout 600s;
    proxy_read_timeout 600s;
    send_timeout 600s;

    location / {
        set \$proxy_upstream "$upstream";
        proxy_http_version 1.1;
        proxy_pass \$proxy_upstream;
        proxy_ssl_server_name on;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto ${FORWARDED_PROTO};
        proxy_set_header X-Forwarded-Scheme ${FORWARDED_PROTO};
        proxy_set_header X-Forwarded-Ssl on;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port ${FORWARDED_PORT};
        proxy_set_header X-Original-Host \$host;
        proxy_set_header Forwarded "proto=${FORWARDED_PROTO};host=\$host";
        proxy_set_header X-Request-Id \$request_id;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;

        proxy_redirect off;
        proxy_buffering off;
    }
}
EOF

  route_count=$((route_count + 1))
done

if [ "$route_count" -eq 0 ] && [ -z "$DEFAULT_UPSTREAM" ]; then
  echo "[entrypoint] No upstream configured. Set DEFAULT_UPSTREAM or at least one PROXY_ROUTE_1..PROXY_ROUTE_5" >&2
  exit 1
fi

if [ -n "$DEFAULT_UPSTREAM" ]; then
  cat >> "$CONF_FILE" <<EOF

server {
    listen ${LISTEN_PORT} default_server;
    server_name _;

    client_max_body_size ${CLIENT_MAX_BODY_SIZE};

    location / {
        set \$proxy_upstream "$DEFAULT_UPSTREAM";
        proxy_http_version 1.1;
        proxy_pass \$proxy_upstream;
        proxy_ssl_server_name on;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto ${FORWARDED_PROTO};
        proxy_set_header X-Forwarded-Scheme ${FORWARDED_PROTO};
        proxy_set_header X-Forwarded-Ssl on;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port ${FORWARDED_PORT};
        proxy_set_header X-Original-Host \$host;
        proxy_set_header Forwarded "proto=${FORWARDED_PROTO};host=\$host";
        proxy_set_header X-Request-Id \$request_id;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;

        proxy_redirect off;
        proxy_buffering off;
    }
}
EOF
fi

nginx -t
exec "$@"
