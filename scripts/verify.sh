#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════
# verify.sh — Verify Liferay DXP Cluster health
# ══════════════════════════════════════════════════════════════════

set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS="${GREEN}[PASS]${NC}"; FAIL="${RED}[FAIL]${NC}"; INFO="${CYAN}[INFO]${NC}"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Liferay DXP Cluster — Verification"
echo "════════════════════════════════════════════════════════════"
echo ""

# MySQL
echo -e "${INFO} MySQL connectivity..."
docker exec liferay-mysql mysqladmin ping -u root -proot --silent 2>/dev/null \
  && echo -e "${PASS} MySQL reachable" || echo -e "${FAIL} MySQL unreachable"

docker exec liferay-mysql mysql -u root -proot \
  -e "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='lportal';" 2>/dev/null \
  | grep -q lportal && echo -e "${PASS} Database 'lportal' exists" || echo -e "${FAIL} Database missing"

echo ""

# Elasticsearch cluster
echo -e "${INFO} Elasticsearch cluster health..."
ES_HEALTH=$(curl -sf "http://localhost:9200/_cluster/health?pretty" 2>/dev/null || echo "{}")
echo "$ES_HEALTH" | grep -qE '"status" : "(green|yellow)"' \
  && echo -e "${PASS} ES cluster healthy ($(echo "$ES_HEALTH" | grep '"status"' | head -1 | tr -d ' '))" \
  || echo -e "${FAIL} ES cluster unhealthy"

NODE_COUNT=$(curl -sf "http://localhost:9200/_cluster/health" 2>/dev/null | grep -o '"number_of_nodes":[0-9]*' | grep -o '[0-9]*' || echo 0)
echo -e "${INFO} ES cluster nodes: ${NODE_COUNT} (expected: 2)"
[ "$NODE_COUNT" -eq 2 ] && echo -e "${PASS} Both ES nodes in cluster" || echo -e "${FAIL} ES node count mismatch"

echo ""

# ES plugins
echo -e "${INFO} Elasticsearch plugins on es-node1..."

PLUGINS=$(docker exec liferay-es-node1 elasticsearch-plugin list 2>/dev/null || true)

for P in analysis-icu analysis-kuromoji analysis-smartcn analysis-stempel; do
    if echo "$PLUGINS" | grep -q "$P"; then
        echo -e "${PASS} $P"
    else
        echo -e "${FAIL} $P missing"
    fi
done

echo ""

echo -e "${INFO} Elasticsearch plugins on es-node2..."

PLUGINS=$(docker exec liferay-es-node2 elasticsearch-plugin list 2>/dev/null || true)

for P in analysis-icu analysis-kuromoji analysis-smartcn analysis-stempel; do
    if echo "$PLUGINS" | grep -q "$P"; then
        echo -e "${PASS} $P"
    else
        echo -e "${FAIL} $P missing"
    fi
done

echo ""

# Liferay nodes
echo -e "${INFO} Liferay Node 1 (port 8080)..."
STATUS1=$(curl -so /dev/null -w "%{http_code}" "http://localhost:8080/c/portal/layout" 2>/dev/null || echo "000")
[[ "$STATUS1" =~ ^(200|302)$ ]] && echo -e "${PASS} Node 1 responding (HTTP $STATUS1)" || echo -e "${FAIL} Node 1 not ready (HTTP $STATUS1)"

echo -e "${INFO} Liferay Node 2 (port 8081)..."
STATUS2=$(curl -so /dev/null -w "%{http_code}" "http://localhost:8081/c/portal/layout" 2>/dev/null || echo "000")
[[ "$STATUS2" =~ ^(200|302)$ ]] && echo -e "${PASS} Node 2 responding (HTTP $STATUS2)" || echo -e "${FAIL} Node 2 not ready (HTTP $STATUS2)"

echo ""

# JGroups cluster check
echo -e "${INFO} Checking JGroups cluster formation (Node 1 logs)..."
docker logs liferay-node1 2>&1 | grep -i "cluster\|jgroups\|members" | tail -5 || true

echo ""

# Container summary
echo -e "${INFO} Container status:"
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || docker-compose ps

echo ""
echo "════════════════════════════════════════════════════════════"
echo -e "  ${INFO} Useful commands:"
echo "  docker logs -f liferay-node1"
echo "  docker logs -f liferay-node2"
echo "  curl http://localhost:9200/_cluster/health?pretty"
echo "  curl http://localhost:9200/_cat/nodes?v"
echo "════════════════════════════════════════════════════════════"
