# railway-addition-domains

Minimal Nginx reverse proxy container for Railway/custom domains.

## Why do we need this?

Each service/container on Railway only supports 1 public railway domain (xxx.up.railway.app). This one gets you another, by using reserve proxy

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/5ARPkB?referralCode=kmHOLH&utm_medium=integration&utm_source=template&utm_campaign=generic)

## Features
- Exposes on **8080**
- Supports up to **5 host-based routes** via env vars (`PROXY_ROUTE_1` ... `PROXY_ROUTE_5`)
- Adds common reverse-proxy headers
- Supports large uploads (default **5G**, configurable via env)

## Environment variables
### Required
Set at least one upstream:
- `DEFAULT_UPSTREAM`, or
- at least one of `PROXY_ROUTE_1` ... `PROXY_ROUTE_5`

`DEFAULT_UPSTREAM` format:
- `scheme://host:port`

`PROXY_ROUTE_x` format:
- `domain=scheme://host:port`

Examples:
- `DEFAULT_UPSTREAM=http://192.168.1.10:3000`
- `PROXY_ROUTE_1=app.example.com=http://192.168.1.10:3000`
- `PROXY_ROUTE_2=admin.example.com=http://192.168.1.11:8080`

### Optional
- `CLIENT_MAX_BODY_SIZE` (default: `5G`)
- `DEFAULT_UPSTREAM` acts as the default route when host doesn't match any `PROXY_ROUTE_x`

## Build
```bash
docker build -t railway-addition-domains .
```

## Run
```bash
docker run --rm -p 8080:8080 \
  -e DEFAULT_UPSTREAM=http://192.168.1.10:3000 \
  -e CLIENT_MAX_BODY_SIZE=5G \
  railway-addition-domains
```

With additional host-based routes:

```bash
docker run --rm -p 8080:8080 \
  -e DEFAULT_UPSTREAM=http://192.168.1.10:3000 \
  -e PROXY_ROUTE_1=app.example.com=http://192.168.1.10:3000 \
  -e PROXY_ROUTE_2=admin.example.com=http://192.168.1.11:8080 \
  -e CLIENT_MAX_BODY_SIZE=5G \
  railway-addition-domains
```
