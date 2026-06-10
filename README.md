# Liferay DXP Cluster — Docker Compose Setup

A production-style Liferay DXP cluster running two application nodes backed by a two-node Elasticsearch cluster and a shared MySQL 8.4 database, all wired together on a single Docker bridge network.

---

## Architecture Overview

```
                          ┌─────────────────────────────┐
                          │  liferay-cluster-net        │
                          │  172.28.0.0/16 (bridge)     │
                          │                             │
                          │   ┌──────────────────────┐  │
                          │   │    MySQL 8.4         │  │
                          │   │  liferay-mysql :3306 │  │
                          │   └──────────┬───────────┘  │
                          │              │ shared DB    │
                    ┌─────┼──────────────┴──────────────┼─────┐
                    │     │                             │     │
              ┌─────▼─────┴──┐                   ┌───────┴─────▼──┐
              │ Liferay Node1│◄────JGroups TCP────►│ Liferay Node2│
              │  :8080 :8443 │                   │  :8081 :9443   │
              └───┬───────┬──┘                   └────┬────────┬──┘
                  │       └─────────────────────────┐ │        │
               primary                              │ │     primary
                  │       ┌─────────────────────────│─┘        │
                  ▼       ▼                         ▼          ▼
          ┌────────────────┐      ES transport   ┌────────────────────┐
          │  ES Node 1     │◄───────:9300───────►│  ES Node 2         │
          │ 172.28.1.1     │                     │  172.28.1.2        │
          │ :9200 / :9300  │                     │  :9201 / :9301     │
          └────────────────┘                     └────────────────────┘
```

---

## Services

| Container | Image | Internal port | Host port(s) |
|---|---|---|---|
| `liferay-mysql` | mysql:8.4 | 3306 | 3306 |
| `liferay-es-node1` | liferay-elasticsearch:8.19 | 9200, 9300 | 9200, 9300 |
| `liferay-es-node2` | liferay-elasticsearch:8.19 | 9200, 9300 | 9201, 9301 |
| `liferay-node1` | liferay/dxp:2025.q1.6-lts | 8080, 8443 | 8080, 8443 |
| `liferay-node2` | liferay/dxp:2025.q1.6-lts | 8080, 8443 | 8081, 9443 |

### Startup order

```
MySQL  →  ES Node 1  →  ES Node 2  →  Liferay Node 1  →  Liferay Node 2
```

Each step waits for the previous service's healthcheck to pass before proceeding.

---

## Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| Docker Engine | 24+ | `docker --version` |
| Docker Compose | v2 plugin | `docker compose version` |
| RAM | 12 GB+ | ES × 2 = 2 GB, Liferay × 2 = 8 GB |
| `vm.max_map_count` | ≥ 262144 | Required by Elasticsearch |

### Setting `vm.max_map_count` (Optional / If Required)(Linux)
Note on Permissions: Tuning host kernel variables requires root privileges. If your host system already meets the minimum requirements, or if you are on a managed corporate runner without sudo access, you can skip this block.

```bash
# Temporary (resets on reboot)
sudo sysctl -w vm.max_map_count=262144

# Permanent
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

On **macOS** with Docker Desktop, open a shell into the VM:

```bash
docker run --rm --privileged alpine sysctl -w vm.max_map_count=262144
```

---

## Project Structure

```
liferay-cluster-fixed-logging-v1/
├── docker-compose.yml
├── .env                          # All tunable variables
│
├── elasticsearch/
│   ├── Dockerfile                # Installs analysis plugins (icu, kuromoji, smartcn, stempel)
│   ├── log4j2.properties         # Human-readable log format, noise suppressed
│   ├── node1/
│   │   └── elasticsearch.yml
│   └── node2/
│       └── elasticsearch.yml
│
├── mysql/
│   └── init-scripts/
│       └── 01-init-lportal.sql   # Creates lportal DB with correct charset
│
├── node1/liferay-shared/
│   ├── files/
│   │   ├── portal-ext.properties
│   │   ├── jgroups/tcp.xml
│   │   └── osgi/configs/
│   │       └── com.liferay.portal.search.elasticsearch7.configuration
│   │           .ElasticsearchConfiguration.config
│   ├── scripts/
│   │   └── 01-jgroups-opts.sh
│   └── patching/
│
├── node2/liferay-shared/         # Mirrors node1 with node2-specific values
│
└── scripts/
    ├── start.sh                  # Ordered startup with health-checks
    ├── stop.sh
    └── verify.sh
```

---

## Quick Start

### 1. Clone or unzip the project

```bash
unzip liferay-cluster-fixed-logging-v1.zip
cd liferay-cluster-fixed-logging-v1
```

### 2. Review `.env`

Open `.env` and adjust passwords, memory settings, or ports as needed:

```dotenv
LIFERAY_IMAGE=liferay/dxp:2025.q1.6-lts
MYSQL_IMAGE=mysql:8.4

MYSQL_ROOT_PASSWORD=root          # Change in production
MYSQL_DATABASE=lportal

ES_CLUSTER_NAME=LiferayElasticsearchCluster
ES_JAVA_OPTS=-Xms1g -Xmx1g

LIFERAY_JVM_OPTS=-Xms2g -Xmx4g -XX:+UseG1GC ...

NODE1_HTTP_PORT=8080
NODE2_HTTP_PORT=8081
ES1_HTTP_PORT=9200
ES2_HTTP_PORT=9201
```

### 3. Build the Elasticsearch image

The custom image installs the four analysis plugins Liferay requires:

```bash
docker compose build es-node1
```

### 4. Start the cluster (recommended)

Use the provided startup script for ordered bringup with progress output:

```bash
bash scripts/start.sh
```

To rebuild the ES image before starting:

```bash
bash scripts/start.sh --build
```

### 5. Verify the cluster

```bash
bash scripts/verify.sh
```

Or check manually:

```bash
# MySQL
docker exec liferay-mysql mysqladmin ping -uroot -proot --silent

# Elasticsearch cluster health
curl -s http://localhost:9200/_cluster/health?pretty

# Liferay Node 1
curl -sf http://localhost:8080/c/portal/layout

# Liferay Node 2
curl -sf http://localhost:8081/c/portal/layout
```

Liferay takes **3–5 minutes** to complete its first-run database population. The node footer displays which node served the request (`web.server.display.node=true`).

### 6. Stop the cluster

```bash
bash scripts/stop.sh
# or
docker compose down
```

To also remove all persistent volumes:

```bash
docker compose down -v
```

---

## Key Configuration Details

### Document Library — DBStore

Both nodes use `DBStore`, which stores document library files inside MySQL rather than the filesystem. This means no shared NFS/EFS volume is needed between the two Liferay nodes.

```properties
dl.store.impl=com.liferay.portal.store.db.DBStore
```

### Cluster communication — JGroups TCP

Nodes discover each other via TCPPING (static member list in `tcp.xml`). The JGroups channel is mounted via `/mnt/liferay`:

```properties
cluster.link.enabled=true
cluster.link.channel.properties.control=/opt/liferay/jgroups/tcp.xml
cluster.link.channel.properties.transport.0=/opt/liferay/jgroups/tcp.xml
```

### Cache and session replication

```properties
ehcache.cluster.link.replication.enabled=true
portlet.session.replicate.enabled=true
```

### Elasticsearch connector

Located at `node{1,2}/liferay-shared/files/osgi/configs/com.liferay.portal.search.elasticsearch7.configuration.ElasticsearchConfiguration.config`

```
operationMode="REMOTE"
productionModeEnabled=B"true"
clusterName="LiferayElasticsearchCluster"
networkHostAddresses=["es-node1:9200","172.28.1.1:9200","es-node2:9200","172.28.1.2:9200"]
authenticationEnabled=B"false"
httpSSLEnabled=B"false"
```

---

## Ports Reference

| Service | Protocol | Host port | Container port |
|---|---|---|---|
| MySQL | TCP | 3306 | 3306 |
| ES Node 1 HTTP | HTTP | 9200 | 9200 |
| ES Node 1 Transport | TCP | 9300 | 9300 |
| ES Node 2 HTTP | HTTP | 9201 | 9200 |
| ES Node 2 Transport | TCP | 9301 | 9300 |
| Liferay Node 1 HTTP | HTTP | 8080 | 8080 |
| Liferay Node 1 HTTPS | HTTPS | 8443 | 8443 |
| Liferay Node 1 JGroups | TCP | 7800 | 7800 |
| Liferay Node 1 OSGi | TCP | 11311 | 11311 |
| Liferay Node 2 HTTP | HTTP | 8081 | 8080 |
| Liferay Node 2 HTTPS | HTTPS | 9443 | 8443 |
| Liferay Node 2 JGroups | TCP | 7801 | 7801 |
| Liferay Node 2 OSGi | TCP | 11312 | 11311 |

---

## Troubleshooting

**Elasticsearch fails to start — `max virtual memory areas` error**

```
bootstrap check failure: max virtual memory areas vm.max_map_count [65530] is too low
```

Fix: `sudo sysctl -w vm.max_map_count=262144`

**Liferay stuck in boot loop — database not ready**

The healthcheck retries up to 30 times (10 s interval). If MySQL is slow on first init, Liferay will wait. Check with:

```bash
docker compose logs mysql --tail 30
```

**JGroups `UnknownHostException: liferay-node2`**

This is the V3 fix: Node 2's hostname is now declared explicitly so Docker DNS registers it before Node 1 initializes the JGroups channel. Both containers get `hostname:` set in `docker-compose.yml`.

**Elasticsearch shows `yellow` cluster status**

Yellow is expected with 2 nodes and default replica settings — some shards have no replica to assign. This does not affect Liferay functionality. To suppress: set `number_of_replicas: 0` in the index template, or add a third ES node.

**Node 2 not appearing in cluster**

Check JGroups sees both members:

```bash
docker exec liferay-node1 curl -sf http://localhost:8080/api/jsonws/portal/get-server-info
```

Or tail the logs for `ClusterExecutorImpl` entries:

```bash
docker compose logs liferay-node1 | grep -i cluster
```

---

## Volumes

All data is persisted in named Docker volumes:

| Volume | Used by |
|---|---|
| `mysql-data` | MySQL data directory |
| `es1-data` | Elasticsearch Node 1 indices |
| `es2-data` | Elasticsearch Node 2 indices |
| `liferay-node1-data` | Liferay Node 1 `/opt/liferay/data` |
| `liferay-node2-data` | Liferay Node 2 `/opt/liferay/data` |
---

## License

Internal infrastructure configuration — not for public distribution without review.
