#!/usr/bin/env bash
# Disposable database only. Does not load .env or touch an application database.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
PG_BIN=${PG_BIN:-/opt/homebrew/opt/postgresql@17/bin}
RUN=$(mktemp -d /tmp/vynic-edge-dev.XXXXXX)
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
umask 077
cleanup() { "$PG_BIN/pg_ctl" -D "$RUN/pg" -m fast stop >/dev/null 2>&1 || true; }
trap cleanup EXIT
"$PG_BIN/initdb" -D "$RUN/pg" -U edgephase1 -A trust --no-locale >"$RUN/init.log"
"$PG_BIN/pg_ctl" -D "$RUN/pg" -l "$RUN/pg.log" -o "-h 127.0.0.1 -p $PORT -k $RUN" start
"$PG_BIN/createdb" -h 127.0.0.1 -p "$PORT" -U edgephase1 phase1_phase0_phase3_test
export DATABASE_URL="postgresql://edgephase1@127.0.0.1:$PORT/phase1_phase0_phase3_test"
export TENANT_INTEGRATION_DATABASE_URL="$DATABASE_URL"
cd "$ROOT/apps/backend"
./node_modules/.bin/prisma migrate deploy >"$RUN/migrations.log"
./node_modules/.bin/prisma migrate diff --from-url "$DATABASE_URL" --to-schema-datamodel prisma/schema.prisma --exit-code
npm test -- --runInBand --runTestsByPath src/edge-foundation/edge-foundation.integration.spec.ts src/edge/operational-authority.integration.spec.ts >"$RUN/backend-tests.log" 2>&1
cd "$ROOT/apps/edge"
go build -o bin/ ./cmd/...
python3 tool/prove.py --database-url "$DATABASE_URL" --output "$RUN/proof.json"
echo "Disposable proof and validation logs: $RUN"
