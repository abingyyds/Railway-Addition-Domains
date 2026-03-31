# railway-addition-domains

Minimal Nginx reverse proxy container for Railway/custom domains.

## Why do we need this?

Each service/container on Railway only supports 1 public railway domain (xxx.up.railway.app). This one gets you another, by using reserve proxy

## Features
- Exposes on **8080**
- Supports up to **5 host-based routes** via env vars (`PROXY_ROUTE_1` ... `PROXY_ROUTE_5`)
- Adds common reverse-proxy headers
- Supports large uploads (default **5G**, configurable via env)

## Environment variables
### Required
Set at least one of:
- `PROXY_ROUTE_1`
- `PROXY_ROUTE_2`
- `PROXY_ROUTE_3`
- `PROXY_ROUTE_4`
- `PROXY_ROUTE_5`

Each route must be in this format:
- `domain=scheme://host:port`

Examples:
- `PROXY_ROUTE_1=app.example.com=http://192.168.1.10:3000`
- `PROXY_ROUTE_2=admin.example.com=http://192.168.1.11:8080`

### Optional
- `CLIENT_MAX_BODY_SIZE` (default: `5G`)
- `DEFAULT_UPSTREAM` fallback when host doesn't match any route (format: `scheme://host:port`)

## Build
```bash
docker build -t railway-addition-domains .
```

## Run
```bash
docker run --rm -p 8080:8080 \
  -e PROXY_ROUTE_1=app.example.com=http://192.168.1.10:3000 \
  -e PROXY_ROUTE_2=admin.example.com=http://192.168.1.11:8080 \
  -e CLIENT_MAX_BODY_SIZE=5G \
  railway-addition-domains
```
