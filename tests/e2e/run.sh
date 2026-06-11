#!/usr/bin/env bash
# Externally-runnable black-box tests for a deployed Langfuse (nebari-langfuse pack).
# Usage: BASE_URL=https://langfuse.example.com MODE=sso ./run.sh
#   MODE=sso (default): expects Keycloak SSO configured, password auth disabled
#   MODE=standalone:    expects email/password (credentials) auth enabled
set -uo pipefail
BASE_URL="${BASE_URL:?set BASE_URL to the deployed Langfuse base URL}"
MODE="${MODE:-sso}"
CURL=(curl -sk --max-time 15)   # -k: dev self-signed TLS
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then echo "PASS: $1 ($3)"; pass=$((pass+1)); else echo "FAIL: $1 (expected $2, got $3)"; fail=$((fail+1)); fi; }

# 1. Public health endpoint -> 200 (the chart's liveness probe)
code=$("${CURL[@]}" -o /dev/null -w '%{http_code}' "$BASE_URL/api/public/health")
check "health endpoint 200" 200 "$code"

# 2. Web UI reachable -> 200
code=$("${CURL[@]}" -o /dev/null -w '%{http_code}' "$BASE_URL/")
check "web UI reachable 200" 200 "$code"

# 3. Auth-protected ingestion rejects unauthenticated -> 401 (journey 11)
code=$("${CURL[@]}" -o /dev/null -w '%{http_code}' -X POST \
  -H 'Content-Type: application/json' --data '{}' \
  "$BASE_URL/api/public/otel/v1/traces")
check "unauthenticated ingestion rejected 401" 401 "$code"

# 4. Auth providers reflect the mode (NextAuth /api/auth/providers JSON)
# NOTE: Langfuse ALWAYS lists the "credentials" provider in /api/auth/providers, even when
# AUTH_DISABLE_USERNAME_PASSWORD=true - the flag rejects credential *login*, it does not
# remove the provider entry. So provider absence is NOT a valid signal. In SSO mode we
# assert (a) keycloak is offered, and (b) a credential login attempt is actually rejected
# (HTTP 401, no session cookie). In standalone mode we assert credentials is offered.
providers=$("${CURL[@]}" "$BASE_URL/api/auth/providers")
if [ "$MODE" = "sso" ]; then
  echo "$providers" | grep -qi 'keycloak' && { echo "PASS: keycloak provider present"; pass=$((pass+1)); } || { echo "FAIL: keycloak provider missing in: $providers"; fail=$((fail+1)); }
  # Credential login must be rejected when password auth is disabled.
  jar=$(mktemp)
  csrf=$("${CURL[@]}" -c "$jar" "$BASE_URL/api/auth/csrf" | sed -E 's/.*"csrfToken":"([^"]+)".*/\1/')
  code=$("${CURL[@]}" -b "$jar" -c "$jar" -o /dev/null -w '%{http_code}' \
    -d "csrfToken=$csrf" -d "email=probe@example.com" -d "password=probe" \
    -d "callbackUrl=$BASE_URL" -d "json=true" \
    "$BASE_URL/api/auth/callback/credentials")
  sess=$(grep -ciE 'next-auth.session-token|authjs.session-token' "$jar"); rm -f "$jar"
  if [ "$code" = "401" ] && [ "$sess" = "0" ]; then echo "PASS: credential login rejected (401, no session)"; pass=$((pass+1));
  else echo "FAIL: credential login not rejected (code=$code session-cookies=$sess)"; fail=$((fail+1)); fi
else
  echo "$providers" | grep -qiE 'credentials|email' && { echo "PASS: credentials provider present (standalone)"; pass=$((pass+1)); } || { echo "FAIL: credentials provider missing in: $providers"; fail=$((fail+1)); }
fi

echo "----"; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
