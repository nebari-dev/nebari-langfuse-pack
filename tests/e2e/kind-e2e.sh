#!/usr/bin/env bash
# Spin up a throwaway kind cluster, install the pack standalone, run black-box tests, tear down.
# Usage: ./tests/e2e/kind-e2e.sh   (requires kind, kubectl, helm)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CHART="$HERE/../../chart"
CLUSTER="nebari-langfuse-e2e"
cleanup() { kind delete cluster --name "$CLUSTER" >/dev/null 2>&1 || true; }
trap cleanup EXIT
kind create cluster --name "$CLUSTER"
helm dependency update "$CHART"
helm install langfuse "$CHART" -f "$HERE/ci-values.yaml" --wait --timeout 12m
kubectl port-forward svc/langfuse-web 3000:3000 >/dev/null 2>&1 &
pf=$!; trap 'kill $pf 2>/dev/null; cleanup' EXIT
for i in $(seq 1 30); do curl -sf http://localhost:3000/api/public/health >/dev/null 2>&1 && break; sleep 5; done
BASE_URL=http://localhost:3000 MODE=standalone bash "$HERE/run.sh"
