#!/usr/bin/env bash
set -euo pipefail

export CLIENT_MAX_BODY_SIZE="${CLIENT_MAX_BODY_SIZE:-5G}"

CONF_FILE="/etc/nginx/conf.d/default.conf"

# Optional fallback upstream when Host doesn't match any PROXY_ROUTE_n
DEFAULT_UPSTREAM="${DEFAULT_UPSTREAM:-}"

cat > "$CONF_FILE" <<'EOF'
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
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
    listen 8080;
    server_name $domain;

    client_max_body_size ${CLIENT_MAX_BODY_SIZE};

    proxy_connect_timeout 60s;
    proxy_send_timeout 600s;
    proxy_read_timeout 600s;
    send_timeout 600s;

    location / {
        proxy_http_version 1.1;
        proxy_pass $upstream;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_set_header X-Request-Id \$request_id;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;

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
    listen 8080 default_server;
    server_name _;

    client_max_body_size ${CLIENT_MAX_BODY_SIZE};

    location / {
        proxy_http_version 1.1;
        proxy_pass $DEFAULT_UPSTREAM;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_set_header X-Request-Id \$request_id;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;

        proxy_buffering off;
    }
}
EOF
fi

nginx -t
exec "$@"
