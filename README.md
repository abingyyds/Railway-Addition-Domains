# railway-addition-domains

Minimal Nginx reverse proxy container for Railway/custom domains.

## Why do we need this?

Each service/container on Railway only supports 1 public railway domain (xxx.up.railway.app). This one gets you another, by using reserve proxy

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/5ARPkB?referralCode=kmHOLH&utm_medium=integration&utm_source=template&utm_campaign=generic)

## Features
- Exposes on **8080** by default (`PORT` can override it)
- Defaults to Subrouter on Railway private networking: `http://subrouter.railway.internal:3000`
- Enables Alpine private networking support for Railway
- Resolves `.railway.internal` upstreams at request time through Railway private DNS
- Supports up to **5 host-based routes** via env vars (`PROXY_ROUTE_1` ... `PROXY_ROUTE_5`)
- Adds Subrouter-friendly reverse-proxy headers, preserving the original public host for distributor/custom-domain routing
- Forces external scheme headers to HTTPS by default to avoid redirect loops behind Railway's internal HTTP hop
- Supports large uploads (default **5G**, configurable via env)

## Environment variables
### Upstream
By default, requests are proxied to:

```env
http://subrouter.railway.internal:3000
```

You can override this with either:
- `SUBROUTER_UPSTREAM`
- `DEFAULT_UPSTREAM`

`DEFAULT_UPSTREAM` format:
- `scheme://host:port`

`PROXY_ROUTE_x` format:
- `domain=scheme://host:port`

Examples:
- `DEFAULT_UPSTREAM=http://subrouter.railway.internal:3000`
- `PROXY_ROUTE_1=api.example.com=http://subrouter.railway.internal:3000`
- `PROXY_ROUTE_2=admin.example.com=http://subrouter.railway.internal:3000`

### Optional
- `PORT` (default: `8080`)
- `CLIENT_MAX_BODY_SIZE` (default: `5G`)
- `FORWARDED_PROTO` (default: `https`)
- `FORWARDED_PORT` (default: `443`)
- `SUBROUTER_UPSTREAM` (default: `http://subrouter.railway.internal:3000`)
- `ENABLE_ALPINE_PRIVATE_NETWORKING` (default: `true` in the image)
- `DEFAULT_UPSTREAM` acts as the default route when host doesn't match any `PROXY_ROUTE_x`

### Railway + Subrouter recommended variables

For the common Subrouter setup on Railway, you can deploy this service without
setting `DEFAULT_UPSTREAM`. These defaults are enough:

```env
PORT=8080
SUBROUTER_UPSTREAM=http://subrouter.railway.internal:3000
FORWARDED_PROTO=https
FORWARDED_PORT=443
ENABLE_ALPINE_PRIVATE_NETWORKING=true
```

## Build
```bash
docker build -t railway-addition-domains .
```

## Run
```bash
docker run --rm -p 8080:8080 \
  -e DEFAULT_UPSTREAM=http://subrouter.railway.internal:3000 \
  -e CLIENT_MAX_BODY_SIZE=5G \
  railway-addition-domains
```

With additional host-based routes:

```bash
docker run --rm -p 8080:8080 \
  -e DEFAULT_UPSTREAM=http://subrouter.railway.internal:3000 \
  -e PROXY_ROUTE_1=app.example.com=http://subrouter.railway.internal:3000 \
  -e PROXY_ROUTE_2=admin.example.com=http://subrouter.railway.internal:3000 \
  -e CLIENT_MAX_BODY_SIZE=5G \
  railway-addition-domains
```
