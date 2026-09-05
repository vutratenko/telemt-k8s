# Application secrets (do not commit real values)

Copy `telemt-secrets.env.example` to `telemt-secrets.env`, fill in values, then run:

```bash
./ops/apply-secrets.sh
```

## Required keys

| Key | Description |
|-----|-------------|
| `TELEMT_SECRET` | 32-character hex MTProxy secret (`openssl rand -hex 16`) |

The secret is **not** managed by Argo CD (applied out-of-band). After changing it, restart the deployment:

```bash
kubectl rollout restart deployment/telemt -n telemt
```
