#!/usr/bin/env bash
# Small local-only wrapper. Production uses explicit Compose files; see docs/DEPLOYMENT.md.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v docker >/dev/null && [[ -x /Applications/Docker.app/Contents/Resources/bin/docker ]]; then
  export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
fi
compose() { docker compose -p vynic-local-prod --env-file .env.docker -f compose.yaml -f compose.local.yaml "$@"; }
action="${1:-status}"
if [[ $# -gt 0 ]]; then shift; fi
case "$action" in
  start) compose up -d --build --wait "$@" ;;
  stop)
    if [[ $# -gt 0 ]]; then compose stop "$@"; else compose down; fi
    ;;
  rebuild) compose up -d --build --wait "$@" ;;
  logs) compose logs -f "$@" ;;
  status) compose ps -a ;;
  migrate) compose run --rm migrate ;;
  seed) compose exec backend node dist/scripts/seed-docker-local.js --confirm-local ;;
  studio)
    compose --profile tools up -d --wait prisma-studio
    echo 'Prisma Studio: http://127.0.0.1:5555 (stop with ./scripts/docker.sh studio-stop)'
    ;;
  studio-stop) compose --profile tools stop prisma-studio ;;
  reset-customer-data) compose exec -T backend node dist/scripts/reset-docker-customers.js "$@" ;;
  cleanup-customer-media) compose exec -T backend node dist/scripts/reset-docker-customers.js --cleanup-media "$@" ;;
  admin) compose exec backend node dist/scripts/create-platform-admin.js "$@" ;;
  reset-local-db)
    [[ "${1:-}" == --confirm-local ]] || { echo 'Requires --confirm-local; deletes only vynic-local-prod_postgres-data. Back up first.' >&2; exit 1; }
    compose down
    docker volume rm vynic-local-prod_postgres-data
    compose up -d --wait
    ;;
  *) compose "$action" "$@" ;;
esac
