#!/usr/bin/env bash
# Asserts the langfuse passthrough wires SSO + secrets into the rendered web deployment.
set -euo pipefail
CHART_DIR="$(cd "$(dirname "$0")/.." && pwd)"
render=$(helm template lf "$CHART_DIR")
# Write to a temp file so grep -q does not trigger SIGPIPE on the echo pipe under pipefail.
_tmp=$(mktemp)
trap 'rm -f "$_tmp"' EXIT
printf '%s\n' "$render" > "$_tmp"

fail() { echo "FAIL: $1"; exit 1; }

grep -q 'name: AUTH_DISABLE_USERNAME_PASSWORD' "$_tmp" \
  || fail "AUTH_DISABLE_USERNAME_PASSWORD not set"
grep -qE 'value: "true"' "$_tmp" \
  || fail "AUTH_DISABLE_USERNAME_PASSWORD not true"
grep -q 'name: AUTH_KEYCLOAK_CLIENT_ID' "$_tmp" \
  || fail "AUTH_KEYCLOAK_CLIENT_ID not wired"
grep -q 'name: langfuse-oidc-client' "$_tmp" \
  || fail "OIDC secret not referenced"
grep -q 'name: SALT' "$_tmp" \
  || fail "SALT not wired"
grep -q 'name: langfuse-secrets' "$_tmp" \
  || fail "generated secret not referenced"
grep -q 'name: langfuse-web' "$_tmp" \
  || fail "web service not named langfuse-web"
if grep -qE 'image: .*docker.io/bitnami/' "$_tmp"; then
  fail "found non-legacy bitnami image"
fi
echo "PASS: values wiring assertions"
