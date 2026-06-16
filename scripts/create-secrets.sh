#!/usr/bin/env bash
# Create the provider-credential Secrets the gateway needs, from environment
# variables. Re-runnable (idempotent). Never writes keys to disk.
#
#   source .env && ./scripts/create-secrets.sh
set -euo pipefail

NS=agentgateway-system

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "WARNING: OPENAI_API_KEY is not set — the gpt-* route will return auth errors." >&2
fi
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "WARNING: ANTHROPIC_API_KEY is not set — the claude-* route will return auth errors." >&2
fi

# The Secret key MUST be "Authorization" — that is the key agentgateway reads the
# provider token from (see policies.auth.secretRef in k8s/agentgateway/10-backends.yaml).
kubectl create secret generic openai-secret -n "$NS" \
  --from-literal=Authorization="${OPENAI_API_KEY:-sk-missing}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic anthropic-secret -n "$NS" \
  --from-literal=Authorization="${ANTHROPIC_API_KEY:-sk-ant-missing}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Optional: Fireworks (only used if you apply extras/fireworks.yaml).
if [[ -n "${FIREWORKS_API_KEY:-}" ]]; then
  kubectl create secret generic fireworks-secret -n "$NS" \
    --from-literal=Authorization="$FIREWORKS_API_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

echo "Secrets created/updated in namespace $NS."
