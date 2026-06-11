# E2E Black-Box Tests

Externally-runnable HTTP-only tests for a deployed `nebari-langfuse` pack. No `kubectl` required for `run.sh`; only `curl`.

## Prerequisites

- `run.sh` only: `curl`
- `kind-e2e.sh` orchestrator: `curl`, `kind`, `kubectl`, `helm`

## Running against any deployed instance

```bash
BASE_URL=https://langfuse.mycluster MODE=sso ./tests/e2e/run.sh
```

For a standalone deployment (no Keycloak):

```bash
BASE_URL=https://langfuse.mycluster MODE=standalone ./tests/e2e/run.sh
```

## Running fully locally (kind cluster)

```bash
./tests/e2e/kind-e2e.sh
```

This script:

1. Creates a throwaway `kind` cluster named `nebari-langfuse-e2e`.
2. Installs the chart using `tests/e2e/ci-values.yaml` (standalone mode, no NebariApp operator).
3. Waits for `helm install --wait` to succeed (up to 12 minutes).
4. Port-forwards `svc/langfuse-web:3000` to `localhost:3000`.
5. Polls the health endpoint until the app is up.
6. Runs `run.sh` with `MODE=standalone`.
7. Tears down the cluster on exit (even on failure).

## MODE=sso vs MODE=standalone

### MODE=sso (default)

Expects a Nebari deployment with Keycloak SSO configured. Checks:

- Health endpoint (`/api/public/health`) returns 200 - the chart liveness probe target.
- Web UI (`/`) returns 200.
- Unauthenticated ingestion (`POST /api/public/otel/v1/traces`) is rejected with 401. This is the primary Beta capability assertion (journey 11): the OTLP ingestion route must require credentials.
- `/api/auth/providers` JSON contains `keycloak` and does NOT contain `credentials` (password auth disabled).

### MODE=standalone

Expects a standalone deployment with `auth.disableUsernamePassword: false`. Checks:

- Health endpoint (`/api/public/health`) returns 200.
- Web UI (`/`) returns 200.
- Unauthenticated ingestion (`POST /api/public/otel/v1/traces`) is rejected with 401.
- `/api/auth/providers` JSON contains `credentials` or `email` (password auth enabled).

## CI values file

`ci-values.yaml` configures a minimal standalone deployment suitable for a kind cluster:

- `nebariapp.enabled: false` - no NebariApp operator dependency.
- ClickHouse `replicaCount: 1` and `zookeeper.replicaCount: 1` - reduces resource usage from the default of 3 replicas.
- Persistence disabled on all datastores (ClickHouse, PostgreSQL, Redis/Valkey, MinIO/S3) - uses `emptyDir` volumes; data is not retained across restarts but avoids PVC provisioning requirements in CI.
- Password auth enabled (`auth.disableUsernamePassword: false`) so `MODE=standalone` tests can assert on the credentials provider.

## Output format

The script prints `PASS:` or `FAIL:` for each assertion, then a summary line:

```
PASS: health endpoint 200 (200)
PASS: web UI reachable 200 (200)
PASS: unauthenticated ingestion rejected 401 (401)
PASS: credentials provider present (standalone)
----
PASS=4 FAIL=0
```

Exit code is 0 when all assertions pass, non-zero on any failure.
