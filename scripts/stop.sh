#!/usr/bin/env bash
# Usage: bash scripts/stop.sh [--clean]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'

CLEAN=false
[[ "${1:-}" == "--clean" ]] && CLEAN=true

if $CLEAN; then
  echo -e "${YELLOW}[WARN]${NC} --clean will DELETE all volumes (all data lost!)"
  read -rp "Type 'yes' to confirm: " C
  [[ "$C" == "yes" ]] || exit 0
fi

echo -e "${CYAN}[INFO]${NC} Stopping Liferay nodes..."
docker compose stop liferay-node2 liferay-node1 2>/dev/null || true

echo -e "${CYAN}[INFO]${NC} Stopping Elasticsearch..."
docker compose stop es-node2 es-node1 2>/dev/null || true

echo -e "${CYAN}[INFO]${NC} Stopping MySQL..."
docker compose stop mysql 2>/dev/null || true

if $CLEAN; then
  docker compose down -v --remove-orphans
  echo -e "${GREEN}[OK]${NC} All containers and volumes removed."
else
  docker compose down --remove-orphans
  echo -e "${GREEN}[OK]${NC} Cluster stopped. Volumes preserved."
fi
