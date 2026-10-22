#!/usr/bin/env bash
# Small local-only wrapper. Production uses explicit Compose files; see docs/DEPLOYMENT.md.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v docker >/dev/null && [[ -x /Applications/Docker.app/Contents/Resources/bin/docker ]]; then
  export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
fi
compose() { docker compose -p vynic-local-prod --env-file .env.docker -f compose.yaml -f compose.local.yaml "$@"; }
# Opt-in LAN listener for POS/Manager on another machine (Windows/Parallels/device).
# Binds one selected private IPv4 address, never every interface.
lan_address() {
  local ip="${1:-${NATIVE_LAN_BIND:-}}" iface
  if [[ -z "$ip" ]]; then
    iface="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')"
    [[ -n "$iface" ]] && ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
  fi
  if [[ ! "$ip" =~ ^(10\.[0-9]+\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+)$ ]]; then
    echo "start-lan needs a private LAN IPv4 address (got '${ip:-none}'). Pass it: ./scripts/docker.sh start-lan <mac-lan-ip>" >&2
    return 1
  fi
  if ! ifconfig | grep -q "inet $ip "; then
    echo "$ip is not assigned to a network interface on this Mac." >&2
    return 1
  fi
  printf '%s' "$ip"
}
compose_lan() {
  NATIVE_LAN_BIND="$lan_ip" docker compose -p vynic-local-prod --env-file .env.docker \
    -f compose.yaml -f compose.local.yaml -f compose.lan.yaml "$@"
}
action="${1:-status}"
if [[ $# -gt 0 ]]; then shift; fi
case "$action" in
  start) compose up -d --build --wait "$@" ;;
  stop)
    if [[ $# -gt 0 ]]; then compose stop "$@"; else compose down; fi
    ;;
  start-lan)
    lan_ip="$(lan_address "${1:-}")" || exit 1
    # Reuses built images (Compose builds only a missing one); `rebuild` refreshes them.
    compose_lan up -d --wait
    port="${NATIVE_LAN_PORT:-8088}"
    echo "Native LAN API: http://$lan_ip:$port  (POS/Manager 'Development API URL')"
    echo "Same-Mac clients keep http://api.vynic.localhost. Turn off with: ./scripts/docker.sh stop-lan"
    ;;
  stop-lan)
    # Recreates only the proxy (and the backend's enrollment URL) without the LAN listener.
    compose up -d --wait reverse-proxy backend
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
