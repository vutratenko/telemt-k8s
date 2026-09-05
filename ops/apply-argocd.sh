#!/usr/bin/env bash
set -euo pipefail

kubectl apply -f argocd/application.yaml
echo "Applied Argo CD Application telemt in namespace shturval-cd"
