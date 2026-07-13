# FIAP Cloud Games — Orchestration

Local infrastructure and (later) deployment setup for the FIAP Cloud Games
Phase 2 event-driven microservices platform.

This repository is the **orchestration** repo of a five-repository solution:

| Repository | Role |
|---|---|
| `fiap-cloud-games-users-api` | Identity: register, login, JWT, roles |
| `fiap-cloud-games-catalog-api` | Games, library, purchase orchestration |
| `fiap-cloud-games-payments-api` | Simulated payment processing |
| `fiap-cloud-games-notifications-api` | Console "e-mail" notifications |
| **`fiap-cloud-games-orchestration`** | **Local infra: Kafka, PostgreSQL, topics, docs (this repo)** |

> **Milestone status: M0 — Orchestration Bootstrap.**
> Only the local infrastructure exists so far: a single-broker Apache Kafka
> (KRaft mode) and PostgreSQL with two logical databases. **No .NET services,
> Dockerfiles, or Kubernetes manifests exist yet** — those arrive in later
> milestones.

---

## What M0 provides

- **PostgreSQL 16** with two logical databases: `fcg_users`, `fcg_catalog`.
- **Apache Kafka 3.9** — single broker, **KRaft mode (no Zookeeper)**.
  - internal listener `kafka:9092` (docker network, used by services from M1)
  - host listener `localhost:29092` (host machine access during development)
- **Three pre-created topics**: `fcg.users.created`, `fcg.orders.placed`,
  `fcg.payments.processed` (1 partition, replication factor 1).
- **Canonical event contracts** documentation: [`contracts/README.md`](contracts/README.md).

Single-broker, RF=1, single-partition are deliberate **MVP** choices — simple,
local, and easy to demonstrate.

---

## Prerequisites

- Docker Desktop (with the Docker Engine running)
- Docker Compose v2

---

## Run

```bash
# optional: create your local env file (compose also has safe defaults)
cp .env.example .env

# start the infrastructure
docker compose up -d
```

`kafka-init` is a one-shot job that creates the topics and then exits with
code `0` — that is expected.

Stop everything:

```bash
docker compose down          # keeps data
docker compose down -v       # also removes the postgres volume (forces DB re-init)
```

---

## Validate

```bash
# 1) service status  (postgres + kafka healthy, kafka-init exited 0)
docker compose ps

# 2) list topics
docker compose exec kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --list

# 3) describe one topic (expect PartitionCount: 1, ReplicationFactor: 1)
docker compose exec kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --describe --topic fcg.orders.placed

# 4) list databases (expect fcg_users and fcg_catalog)
docker compose exec postgres psql -U fcg -d postgres -c "\l"
```

> **Windows note:** run the `docker compose exec kafka ...` commands from
> **PowerShell** or **CMD**. In Git Bash (MSYS) the leading `/opt/...` argument
> is auto-rewritten to a Windows path and the exec fails; if you must use Git
> Bash, prefix the path with an extra slash (`//opt/kafka/bin/kafka-topics.sh`).

Expected:

- `docker compose ps` → `fcg-postgres` healthy, `fcg-kafka` healthy,
  `fcg-kafka-init` exited (0).
- topic list → `fcg.users.created`, `fcg.orders.placed`, `fcg.payments.processed`.
- database list → includes `fcg_users` and `fcg_catalog`.

---

## Configuration

All values come from environment variables (see [`.env.example`](.env.example)).
Only **local/development placeholders** are used; no real secrets are committed.
The JWT variables are defined for forward use and are **not** consumed in M0.

---

## Repository layout (M0)

```
fiap-cloud-games-orchestration/
├── docker-compose.yml          # postgres + kafka + kafka-init
├── .env.example                # config template (placeholders only)
├── .gitignore
├── README.md                   # this file
├── db/
│   └── init/
│       └── 01-create-databases.sql   # creates fcg_users + fcg_catalog
├── contracts/
│   └── README.md               # canonical event-contract reference (docs only)
└── docs/                        # reserved for diagrams (later milestones)
```

---

## Next milestone

**M1 — extract UsersAPI** (HTTP + JWT + `fcg_users`, containerized, still no
Kafka), in the `fiap-cloud-games-users-api` repository.
