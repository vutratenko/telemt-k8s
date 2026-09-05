#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-telemt}"
ENV_FILE="${1:-secrets/telemt-secrets.env}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}. Copy from secrets/telemt-secrets.env.example" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

if [[ -z "${TELEMT_SECRET:-}" || "${TELEMT_SECRET}" == "CHANGE_ME_32_HEX_SECRET_HERE" ]]; then
  echo "Set TELEMT_SECRET in ${ENV_FILE} (32 hex chars from: openssl rand -hex 16)" >&2
  exit 1
fi

if [[ "${#TELEMT_SECRET}" -ne 32 ]]; then
  echo "TELEMT_SECRET must be exactly 32 hex characters, got ${#TELEMT_SECRET}" >&2
  exit 1
fi

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic telemt-secrets \
  --namespace "${NAMESPACE}" \
  --from-literal=telemt-secret="${TELEMT_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Applied secret telemt-secrets in namespace ${NAMESPACE}"
