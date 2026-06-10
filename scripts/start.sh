#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════
# start.sh — Ordered cluster startup for Liferay DXP
# Sequence: MySQL → ES Node1 → ES Node2 → Liferay Node1 → Liferay Node2
# Usage: bash scripts/start.sh [--build]
# ══════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info()   { echo -e "${CYAN}[INFO]${NC}   $*"; }
log_ok()     { echo -e "${GREEN}[OK]${NC}     $*"; }
log_warn()   { echo -e "${YELLOW}[WARN]${NC}   $*"; }
log_error()  { echo -e "${RED}[ERROR]${NC}  $*"; }
log_header() { echo -e "\n${BOLD}${CYAN}══ $* ══${NC}"; }

LOG_PIDS=()

cleanup() {
  echo ""
  log_info "Stopping log streams (containers keep running)..."
  for pid in "${LOG_PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

BUILD_FLAG=""
if [[ "${1:-}" == "--build" ]]; then
  BUILD_FLAG="true"
  log_info "Build flag set — Elasticsearch image will be rebuilt."
fi

cd "$PROJECT_DIR"

# ── Pre-flight ────────────────────────────────────────────────────
log_info "Running pre-flight checks..."
command -v docker >/dev/null 2>&1 || { log_error "docker not found."; exit 1; }
docker compose version >/dev/null 2>&1 || { log_error "docker compose not found."; exit 1; }

VM_MAP_COUNT=$(cat /proc/sys/vm/max_map_count 2>/dev/null || echo 0)
if [ "$VM_MAP_COUNT" -lt 262144 ]; then
  log_warn "vm.max_map_count=${VM_MAP_COUNT} — Elasticsearch requires >= 262144"
  log_warn "Fix: sudo sysctl -w vm.max_map_count=262144"
  read -rp "Continue anyway? (y/N): " CONTINUE
  [[ "$CONTINUE" =~ ^[Yy]$ ]] || exit 1
fi

# ── Step 1: Build Elasticsearch image ────────────────────────────
log_header "Step 1/5 — Building Elasticsearch image"
if [[ -n "$BUILD_FLAG" ]]; then
  docker compose build --no-cache es-node1
else
  docker compose build es-node1
fi
log_ok "Elasticsearch image built."

# ── Step 1b: Pre-pull Liferay image ──────────────────────────────
log_info "Pre-pulling Liferay image..."
docker compose pull liferay-node1
log_ok "Liferay image ready."

# ── Step 2: MySQL ─────────────────────────────────────────────────
log_header "Step 2/5 — Starting MySQL 8.4"
docker compose up -d mysql
echo ""
docker logs -f liferay-mysql 2>&1 | awk -v p="${YELLOW}[mysql]${NC} " '{print p $0; fflush();}' &
LOG_PIDS+=($!)
log_info "Waiting for MySQL to be healthy..."
until docker inspect liferay-mysql --format='{{.State.Health.Status}}' 2>/dev/null | grep -q "healthy"; do
  sleep 3
done
log_ok "MySQL is healthy."

# ── Step 3: Elasticsearch Node 1 ─────────────────────────────────
log_header "Step 3/5 — Starting Elasticsearch Node 1"
docker compose up -d es-node1
echo ""
docker logs -f liferay-es-node1 2>&1 | awk -v p="${MAGENTA}[es-node1]${NC} " '{print p $0; fflush();}' &
LOG_PIDS+=($!)
log_info "Waiting for ES Node 1 to be healthy..."
until docker inspect liferay-es-node1 --format='{{.State.Health.Status}}' 2>/dev/null | grep -q "healthy"; do
  sleep 5
done
log_ok "Elasticsearch Node 1 is healthy."

# ── Step 4: Elasticsearch Node 2 ─────────────────────────────────
log_header "Step 4/5 — Starting Elasticsearch Node 2"
docker compose up -d es-node2
echo ""
docker logs -f liferay-es-node2 2>&1 | awk -v p="${BLUE}[es-node2]${NC} " '{print p $0; fflush();}' &
LOG_PIDS+=($!)
log_info "Waiting for ES Node 2 to be healthy..."
until docker inspect liferay-es-node2 --format='{{.State.Health.Status}}' 2>/dev/null | grep -q "healthy"; do
  sleep 5
done
log_ok "Elasticsearch Node 2 is healthy."

# ── Step 5: Liferay Node 1 ────────────────────────────────────────
log_header "Step 5/5a — Starting Liferay Node 1 (first boot: 5-10 min)"
docker compose up -d liferay-node1
echo ""
docker logs -f liferay-node1 2>&1 | awk -v p="${CYAN}[liferay-node1]${NC} " '{print p $0; fflush();}' &
LOG_PIDS+=($!)
log_info "Waiting for Liferay Node 1 to be healthy..."
TIMEOUT=600; ELAPSED=0
until curl -sf "http://localhost:8080/c/portal/layout" -o /dev/null 2>/dev/null; do
  [ $ELAPSED -ge $TIMEOUT ] && { log_error "Node 1 timed out."; exit 1; }
  sleep 10; ELAPSED=$((ELAPSED+10))
done
log_ok "Liferay Node 1 is up!"

# ── Step 6: Liferay Node 2 ────────────────────────────────────────
log_header "Step 5/5b — Starting Liferay Node 2 (joining cluster...)"
docker compose up -d liferay-node2
echo ""
docker logs -f liferay-node2 2>&1 | awk -v p="${GREEN}[liferay-node2]${NC} " '{print p $0; fflush();}' &
LOG_PIDS+=($!)
log_info "Waiting for Liferay Node 2 to be healthy..."
TIMEOUT=600; ELAPSED=0
until curl -sf "http://localhost:8081/c/portal/layout" -o /dev/null 2>/dev/null; do
  [ $ELAPSED -ge $TIMEOUT ] && { log_error "Node 2 timed out."; exit 1; }
  sleep 10; ELAPSED=$((ELAPSED+10))
done
log_ok "Liferay Node 2 is up and joined the cluster!"

# ── Stop log streams, print summary ──────────────────────────────
for pid in "${LOG_PIDS[@]:-}"; do
  kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
done
LOG_PIDS=()

echo ""
echo "════════════════════════════════════════════════════════════"
log_ok "Liferay DXP Cluster is fully up!"
echo ""
echo -e "  ${CYAN}Liferay Node 1${NC}       → http://localhost:8080"
echo -e "  ${GREEN}Liferay Node 2${NC}       → http://localhost:8081"
echo -e "  ${MAGENTA}Elasticsearch 1${NC}      → http://localhost:9200"
echo -e "  ${BLUE}Elasticsearch 2${NC}      → http://localhost:9201"
echo -e "  ${YELLOW}MySQL${NC}                → localhost:3306"
echo ""
echo -e "  Credentials: test@liferay.com / test"
echo "════════════════════════════════════════════════════════════"
echo ""
log_info "Verify cluster:      bash scripts/verify.sh"
log_info "Follow all logs:     docker compose logs -f"
log_info "Stop cluster:        bash scripts/stop.sh"
