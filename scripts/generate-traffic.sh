#!/usr/bin/env bash
# Generate demo traffic so the Grafana dashboards have something to show.
# Assumes the gateway is port-forwarded on localhost:8080:
#   kubectl port-forward -n agentgateway-system deploy/agentgateway-proxy 8080:80
#
#   ./scripts/generate-traffic.sh [iterations]   (default: loop forever)
set -euo pipefail

URL=${GATEWAY_URL:-http://localhost:8080}/v1/chat/completions
API_KEY=${API_KEY:-demo-key-engineering}
ITERS=${1:-0}   # 0 = loop forever

ORGS=(engineering customer-success marketing)
PROMPTS=("say hi" "name a color" "count to three" "tell a one-line joke")

i=0
while :; do
  org=${ORGS[$RANDOM % ${#ORGS[@]}]}
  prompt=${PROMPTS[$RANDOM % ${#PROMPTS[@]}]}
  code=$(curl -s -o /dev/null -w '%{http_code}' -m 60 -X POST "$URL" \
    -H 'Content-Type: application/json' \
    -H "X-API-Key: $API_KEY" \
    -H "x-org: $org" \
    -d "{\"model\":\"gpt-4o-mini\",\"messages\":[{\"role\":\"user\",\"content\":\"$prompt\"}],\"max_tokens\":16}")
  printf 'org=%-16s -> HTTP %s\n' "$org" "$code"
  i=$((i + 1))
  [[ "$ITERS" -ne 0 && "$i" -ge "$ITERS" ]] && break
  sleep 1
done
