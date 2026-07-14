# FIAP Cloud Games — Orchestration

Local infrastructure **and** full-system runner for the FIAP Cloud Games Phase 2
event-driven microservices platform. From this repo, `docker compose up -d --build`
brings up PostgreSQL, Kafka, and all four microservices.

This repository is the **orchestration** repo of a five-repository solution:

| Repository | Role |
|---|---|
| `fiap-cloud-games-users-api` | Identity: register, login, JWT, roles |
| `fiap-cloud-games-catalog-api` | Games, library, purchase orchestration |
| `fiap-cloud-games-payments-api` | Simulated payment processing |
| `fiap-cloud-games-notifications-api` | Console "e-mail" notifications |
| **`fiap-cloud-games-orchestration`** | **Infra + full compose + docs (this repo)** |

> **Milestone status: M6 — Full Docker Compose Integration.**
> The complete system runs locally with one command. Kubernetes manifests arrive
> in M7.

---

## What the system provides

- **PostgreSQL 16** — two logical databases: `fcg_users`, `fcg_catalog`.
- **Apache Kafka 3.9** — single broker, **KRaft (no Zookeeper)**.
  - internal listener `kafka:9092` (used by the service containers)
  - host listener `localhost:29092` (host-run dev)
- **Three topics**: `fcg.users.created`, `fcg.orders.placed`, `fcg.payments.processed`
  (1 partition, RF 1) pre-created by `kafka-init`.
- **Four microservices** built from the sibling repos, wired to `kafka:9092` and
  `postgres:5432`, sharing a JWT secret between UsersAPI and CatalogAPI.
- **Canonical event contracts**: [`contracts/README.md`](contracts/README.md).

Single-broker, RF 1, single-partition are deliberate **MVP** choices.

---

## Prerequisites

- Docker Desktop (Docker Engine running) + Docker Compose v2.
- **The four service repos must be cloned as siblings of this repo** (same parent
  folder), because the compose build contexts point at `../fiap-cloud-games-*`:
  ```
  <parent>/
  ├── fiap-cloud-games-users-api
  ├── fiap-cloud-games-catalog-api
  ├── fiap-cloud-games-payments-api
  ├── fiap-cloud-games-notifications-api
  └── fiap-cloud-games-orchestration   (this repo)
  ```

---

## Run the full system

```bash
cp .env.example .env          # optional; compose has safe defaults
docker compose up -d --build  # builds the 4 service images + starts everything
```

`kafka-init` is a one-shot job that creates the topics and exits `0` — expected.

Stop:
```bash
docker compose down           # keeps the postgres volume
docker compose down -v        # also removes the volume (forces DB re-init)
```

### Service URLs (host)

| Service | URL | Notes |
|---|---|---|
| UsersAPI | http://localhost:8080/swagger | register / login / users |
| CatalogAPI | http://localhost:8082/swagger | games / library |
| NotificationsAPI | http://localhost:8081/health | console e-mails (see logs) |
| PaymentsAPI | http://localhost:8083/health | payment simulation (see logs) |

---

## Demo flow (containers only)

1. `POST http://localhost:8080/api/auth/register` → 201 → **welcome e-mail** in
   `docker compose logs notifications-api`.
2. `POST http://localhost:8080/api/auth/login` → copy the token.
3. `GET http://localhost:8082/api/games` with the token → 200 (CatalogAPI validates
   the UsersAPI token via the shared secret).
4. `POST http://localhost:8082/api/library/acquire/{gameId}` → **202** `{ orderId }`.
5. `GET http://localhost:8082/api/library/my-games` → the game appears.
6. Watch the chain: `docker compose logs -f users-api catalog-api payments-api notifications-api`.

Seeded users: `admin@fcg.com / Admin@123`, `user@fcg.com / User@123`.

---

## Validate

```bash
docker compose ps                       # infra healthy, kafka-init Exited(0), 4 services Up

# topics / databases
docker compose exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
docker compose exec postgres psql -U fcg -d postgres -c "\l"

# event flow + consumer groups (LAG 0)
docker compose exec kafka /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic fcg.payments.processed --from-beginning --timeout-ms 5000
docker compose exec kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group catalog-service
docker compose exec kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group notifications-service
```

> **Windows note:** run the `docker compose exec kafka ...` commands from
> **PowerShell** or **CMD**. In Git Bash (MSYS) the leading `/opt/...` argument is
> auto-rewritten to a Windows path; if you must use Git Bash, prefix it with an
> extra slash (`//opt/kafka/bin/...`).

---

## Configuration

All values come from environment variables (see [`.env.example`](.env.example));
only **local/development placeholders** — no real secrets committed. The compose
file supplies fallback defaults, so it runs with or without a `.env`.

- **Shared JWT** (`JWT__SECRETKEY`, `JWT__ISSUER`, `JWT__AUDIENCE`) is injected into
  **both** `users-api` and `catalog-api` so CatalogAPI validates UsersAPI's tokens.
- In-network names: services use `kafka:9092` and `postgres:5432` (never `localhost`).
- No container healthchecks on the .NET services (the `aspnet` runtime image has no
  curl); startup order is handled by `depends_on` (postgres healthy + kafka-init
  completed) and `restart: unless-stopped`, plus the services' own retry/resilience.

---

## Repository layout

```
fiap-cloud-games-orchestration/
├── docker-compose.yml          # postgres + kafka + kafka-init + 4 services
├── .env.example                # config template (placeholders only)
├── .gitignore · README.md
├── db/init/01-create-databases.sql   # creates fcg_users + fcg_catalog
├── contracts/README.md         # canonical event-contract reference (docs only)
└── docs/                        # reserved for diagrams (later milestones)
```

---

## Next milestone

**M7 — Kubernetes:** per-service `/k8s` (Deployment + Service + ConfigMap + Secret)
in each repo, plus shared infra (namespace, Kafka, Postgres, shared Secret/ConfigMap)
and an apply script here; validated on local Kubernetes.
