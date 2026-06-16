#!/usr/bin/env bash
# Tear down the demo: delete the whole kind cluster.
set -euo pipefail
CLUSTER=agentgateway-demo
echo "Deleting kind cluster '$CLUSTER'..."
kind delete cluster --name "$CLUSTER"
echo "Done."
