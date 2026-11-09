# telemt-k8s — GitOps manifests for Telemt MTProxy

Kubernetes deployment for [Telemt](https://github.com/telemt/telemt) (MTProxy with Fake TLS) on a personal stand, managed via Argo CD in namespace `shturval-cd`.

## Layout

| Path | Purpose |
|------|---------|
| `argocd/` | Argo CD Application |
| `deploy/` | Namespace, ConfigMap, Service (ClusterIP), Deployment |
| `secrets/` | Secret templates (no real values) |
| `ops/` | Apply secrets and Argo CD Application |

Внешний вход **не** в этом репозитории: TLS passthrough и `TLSRoute` задаются в [sion2k-gateway](https://github.com/vutratenko/sion2k-gateway) (`ListenerSet/sion2k-app-listeners`, `dist/httproutes/telemt-tlsroute.yaml`).

## Architecture

- External traffic: `cheeseburger.sion2k.ru:443` → VIP **`192.168.88.114`** (отдельный Gateway `telemt-passthrough`, **не** общий `shturval-gateway` на `.9`). MTProto Fake TLS ломается в одном Envoy с десятками HTTPS-terminate listener'ов — как раньше на отдельном `public` Gateway.
- **TLS passthrough** (L4, не HTTPRoute): `TLSRoute/telemt` → `Service/telemt:8443`. Манифесты в [sion2k-gateway](https://github.com/vutratenko/sion2k-gateway) (`05-gateway-telemt-passthrough.yaml`).
- Pod listens on **8443** (non-privileged port, no root, no `NET_BIND_SERVICE`).
- Fake TLS SNI / client domain: **cheeseburger.sion2k.ru** (`tls_domain` / `public_host` in ConfigMap — do not change after issuing client links).
- Unknown/probe handling and splice to **sion2k.ru** (`mask_host`) happen **inside telemt**, not on the Gateway.

## Prerequisites

### DNS

```
cheeseburger.sion2k.ru  →  192.168.88.114
```

Если A-запись всё ещё на `.9`, клиенты Telegram попадают на `shturval-gateway` без passthrough для telemt — прокси «мёртв». Перенесите DNS (или DNAT только для `cheeseburger` на `.114`).

### Gateway API (sion2k-gateway)

Argo CD Application `sion2k-gateway` должен быть Synced: `ListenerSet` programmed, `TLSRoute` `telemt` — `Accepted` + `ResolvedRefs=True`. Не добавляйте HTTPS Terminate listener с cert-manager для этого hostname.

## Quick start

1. Generate MTProxy secret and save it:

```bash
openssl rand -hex 16
# Example output: d3001234567890abcdef1234567890ab
```

2. Create secrets file:

```bash
cp secrets/telemt-secrets.env.example secrets/telemt-secrets.env
# Edit secrets/telemt-secrets.env and set TELEMT_SECRET=<32-char-hex>
```

3. Apply secret to cluster:

```bash
./ops/apply-secrets.sh
```

4. Push repo to GitHub and apply Argo CD Application:

```bash
./ops/apply-argocd.sh
```

5. Wait for sync and check status:

```bash
kubectl get tlsroute -n telemt telemt
kubectl get endpoints -n telemt telemt
kubectl logs -n telemt -l app.kubernetes.io/name=telemt -f
```

## Client link generation

Mask domain `cheeseburger.sion2k.ru` in hex:

```bash
echo -n "cheeseburger.sion2k.ru" | xxd -p
# 6368656573656275726765722e73696f6e326b2e7275
```

Build Fake TLS secret (prefix `ee` + 32-char hex + domain hex):

```
ee<YOUR_32_HEX_SECRET>6368656573656275726765722e73696f6e326b2e7275
```

Telegram link:

```
tg://proxy?server=cheeseburger.sion2k.ru&port=443&secret=ee<YOUR_32_HEX_SECRET>6368656573656275726765722e73696f6e326b2e7275
```

HTTPS link (for sharing):

```
https://t.me/proxy?server=cheeseburger.sion2k.ru&port=443&secret=ee<YOUR_32_HEX_SECRET>6368656573656275726765722e73696f6e326b2e7275
```

## Verify routing and proxy

**Kubernetes / Gateway API**

```bash
kubectl get listenerset -n gateway-system sion2k-app-listeners -o jsonpath='{.status.listeners[?(@.name=="tls-cheeseburger-sion2k-ru-passthrough")].attachedRoutes}{"\n"}'
# expect: 1
kubectl get tlsroute -n telemt telemt -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status}{"\n"}{end}'
```

**Negative check (край не терминирует TLS):** для SNI `cheeseburger.sion2k.ru` на `.9` не должен отдаваться платформенный/ACME-сертификат с CN=cheeseburger (в отличие от `openssl s_client -servername sion2k.ru -connect 192.168.88.9:443`, где виден CN=sion2k.ru).

**Masking / curl:** обычный `curl https://cheeseburger.sion2k.ru/` без MTProxy-секрета может **не** завершить TLS handshake (Fake TLS на telemt — это не обычный HTTPS). Та же картина при прямом обращении к `telemt:8443` внутри кластера. Рабочий критерий для прокси — клиент Telegram с `ee…` ссылкой и/или активные сессии в логах (`ME key derivation`, `RPC handshake OK`).

```bash
VIP=192.168.88.9
openssl s_client -connect ${VIP}:443 -servername cheeseburger.sion2k.ru -brief </dev/null
# ожидаемо: нет валидного peer cert cheeseburger от Gateway; не subject=CN=sion2k.ru (это другой listener)
```

## Metrics

Prometheus metrics are exposed on port **9090** inside the pod (ClusterIP only by default). To scrape externally, add a dedicated Service or ServiceMonitor.

## Security notes

- Do not commit real secrets; use `secrets/telemt-secrets.env` locally and `./ops/apply-secrets.sh`.
- Keep API/management ports disabled or bound to localhost in production configs.
- Do not change `tls_domain` after distributing client links — existing links will break.

## Image

Default image: `ghcr.io/telemt/telemt:latest`

Pin a specific version in `deploy/kustomization.yaml` for production:

```yaml
images:
  - name: ghcr.io/telemt/telemt
    newTag: "3.4.12"
```
