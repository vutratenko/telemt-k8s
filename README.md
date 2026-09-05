# telemt-k8s — GitOps manifests for Telemt MTProxy

Kubernetes deployment for [Telemt](https://github.com/telemt/telemt) (MTProxy with Fake TLS) on a personal stand, managed via Argo CD in namespace `shturval-cd`.

## Layout

| Path | Purpose |
|------|---------|
| `argocd/` | Argo CD Application |
| `deploy/` | Namespace, ConfigMap, Service (LoadBalancer), Deployment |
| `secrets/` | Secret templates (no real values) |
| `ops/` | Apply secrets and Argo CD Application |

## Architecture

- External traffic hits `Service/telemt` on port **443** (LoadBalancer).
- Pod listens on **8443** (non-privileged port, no root, no `NET_BIND_SERVICE`).
- Fake TLS masking domain: **sion2k.ru** (do not change after issuing client links).

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

5. Wait for sync and get external IP:

```bash
kubectl get svc -n telemt telemt
kubectl logs -n telemt -l app.kubernetes.io/name=telemt -f
```

## Client link generation

Mask domain `sion2k.ru` in hex:

```bash
echo -n "sion2k.ru" | xxd -p
# 73696f6e326b2e7275
```

Build Fake TLS secret (prefix `ee` + 32-char hex + domain hex):

```
ee<YOUR_32_HEX_SECRET>73696f6e326b2e7275
```

Example:

```
eed3001234567890abcdef1234567890ab73696f6e326b2e7275
```

Telegram link:

```
tg://proxy?server=<LOAD_BALANCER_IP>&port=443&secret=ee<YOUR_32_HEX_SECRET>73696f6e326b2e7275
```

HTTPS link (for sharing):

```
https://t.me/proxy?server=<LOAD_BALANCER_IP>&port=443&secret=ee<YOUR_32_HEX_SECRET>73696f6e326b2e7275
```

## Verify masking

From a machine that can reach the LoadBalancer IP:

```bash
curl -v -I --resolve sion2k.ru:443:<LOAD_BALANCER_IP> https://sion2k.ru/
```

You should see a valid TLS response from the real site (TCP splice), not a proxy error.

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
