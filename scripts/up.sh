#!/usr/bin/env bash
# One-shot setup of the whole demo on a local kind cluster.
# Prefer running the steps by hand from the README the first time — but this is
# here for repeat runs and CI. Re-runnable (idempotent).
#
#   source .env && ./scripts/up.sh
set -euo pipefail
cd "$(dirname "$0")/.."

CLUSTER=agentgateway-demo
GATEWAY_API_VERSION=v1.5.0
AGW_VERSION=v1.2.1

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

# --- 0. Prerequisites -------------------------------------------------------
for bin in docker kind kubectl helm; do
  command -v "$bin" >/dev/null || { echo "Missing required tool: $bin" >&2; exit 1; }
done

# --- 1. kind cluster --------------------------------------------------------
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  say "kind cluster '$CLUSTER' already exists — reusing it"
else
  say "Creating kind cluster '$CLUSTER'"
  kind create cluster --name "$CLUSTER" --wait 120s
fi
kubectl config use-context "kind-$CLUSTER" >/dev/null

# --- 2. Kubernetes Gateway API CRDs ----------------------------------------
say "Installing Kubernetes Gateway API CRDs ($GATEWAY_API_VERSION)"
kubectl apply --server-side --force-conflicts \
  -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

# --- 3. agentgateway control plane (via Helm) -------------------------------
say "Installing agentgateway CRDs ($AGW_VERSION)"
helm upgrade -i agentgateway-crds oci://cr.agentgateway.dev/charts/agentgateway-crds \
  --create-namespace --namespace agentgateway-system \
  --version "$AGW_VERSION" --set controller.image.pullPolicy=Always

say "Installing agentgateway control plane ($AGW_VERSION)"
helm upgrade -i agentgateway oci://cr.agentgateway.dev/charts/agentgateway \
  --namespace agentgateway-system --version "$AGW_VERSION" \
  --set controller.image.pullPolicy=Always \
  --set controller.extraEnv.KGW_ENABLE_GATEWAY_API_EXPERIMENTAL_FEATURES=true \
  --wait --timeout 5m

# --- 4. Provider credentials (from env) ------------------------------------
say "Creating provider secrets from environment variables"
./scripts/create-secrets.sh

# --- 5. Observability stack -------------------------------------------------
say "Deploying observability stack (ClickHouse, OTel Collector, Prometheus, Grafana)"
kubectl apply -f k8s/observability/

# --- 6. Gateway, backends, routes, policies --------------------------------
say "Applying the Gateway, provider backends, routes, and policies"
kubectl apply -f k8s/agentgateway/00-gateway.yaml
kubectl apply -f k8s/agentgateway/10-backends.yaml
kubectl apply -f k8s/agentgateway/20-routes.yaml
kubectl apply -f k8s/agentgateway/30-auth.yaml
kubectl apply -f k8s/agentgateway/40-telemetry.yaml

# --- 7. Wait for everything to be ready ------------------------------------
say "Waiting for workloads to become ready"
kubectl wait --for=condition=Programmed gateway/agentgateway-proxy -n agentgateway-system --timeout=120s
kubectl -n observability rollout status deploy/clickhouse --timeout=180s
kubectl -n observability rollout status deploy/otel-collector --timeout=180s
kubectl -n observability rollout status deploy/prometheus --timeout=180s
kubectl -n observability rollout status deploy/grafana --timeout=180s

cat <<'EOF'

================================================================
  Done. Next steps:

  # 1. Expose the gateway locally
  kubectl port-forward -n agentgateway-system deploy/agentgateway-proxy 8080:80

  # 2. In another terminal, send a request
  curl -s http://localhost:8080/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -H 'X-API-Key: demo-key-engineering' \
    -H 'x-org: engineering' \
    -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"hello"}]}'

  # 3. Open Grafana (admin / admin)
  kubectl port-forward -n observability svc/grafana 3000:3000
  #    -> http://localhost:3000  (dashboards under the "Agentgateway" folder)

  See README.md for the full guided walkthrough.
================================================================
EOF
