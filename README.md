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

The complete system runs on **Docker Compose** and on **local Kubernetes**
(Docker Desktop). This README is the **master entry point** for evaluators — start here.

---

## Documentation

| Doc | Contents |
|---|---|
| [docs/architecture.md](docs/architecture.md) | System overview, responsibilities, architecture diagram, design decisions, future improvements |
| [docs/event-flows.md](docs/event-flows.md) | Registration & purchase sequence diagrams, topics, consumer groups, idempotency |
| [contracts/README.md](contracts/README.md) | Canonical event contracts (`UserCreatedEvent`, `OrderPlacedEvent`, `PaymentProcessedEvent`) |
| [docs/testing.md](docs/testing.md) | Unit tests (37) + validated Compose/Kubernetes evidence |
| [docs/delivery-checklist.md](docs/delivery-checklist.md) | Requirement → where satisfied |
| [docs/demo-script.md](docs/demo-script.md) | Video/demo roteiro |

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

## Kubernetes (local)

Run the same system on **local Kubernetes** (Docker Desktop Kubernetes recommended).
Manifests use the **hybrid** layout: each service repo has its own `/k8s`
(Deployment + Service + ConfigMap); this repo's `/k8s` holds shared infrastructure
(namespace, Kafka, PostgreSQL, shared ConfigMap/Secret) and the apply scripts. All
resources live in the `fcg` namespace.

> Enable Kubernetes in Docker Desktop (Settings → Kubernetes → Enable) first, and
> stop the compose stack (`docker compose down`) so ports 8080/8082 are free for
> port-forwarding. The four service repos must be cloned as siblings of this repo.

```powershell
# PowerShell is the primary path on Windows
.\k8s\build-images.ps1     # build the 4 images (Docker Desktop shares the image store; no load step)
.\k8s\apply-all.ps1        # namespace -> shared config/secret -> postgres+kafka -> topics Job -> services
```
Shell equivalents: `k8s/build-images.sh`, `k8s/apply-all.sh`.

Validate:
```powershell
kubectl get pods -n fcg
kubectl get svc  -n fcg
kubectl get configmap,secret -n fcg

# access UsersAPI + CatalogAPI (each in its own terminal)
kubectl port-forward -n fcg svc/users-api   8080:8080
kubectl port-forward -n fcg svc/catalog-api 8082:8080

# Kafka / consumer-group evidence
$KPOD = kubectl get pod -n fcg -l app=kafka -o jsonpath='{.items[0].metadata.name}'
kubectl exec -n fcg $KPOD -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
kubectl exec -n fcg $KPOD -- /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group catalog-service
```

Tear down: `kubectl delete namespace fcg`.

Secrets in `k8s/shared-secret.yaml` are **local/development placeholders only**. In
production they would come from a secret manager (e.g. **Azure Key Vault**) — a
documented future improvement, not integrated in this MVP.

---

## Configuration reference

Values come from environment variables (see [`.env.example`](.env.example)); only
**local/development placeholders** are committed. Compose supplies fallback defaults,
so it runs with or without a `.env`. The same .NET config keys are provided two ways:
Compose `environment:` and Kubernetes ConfigMaps/Secret.

| Service | Config keys |
|---|---|
| `users-api` | `ConnectionStrings__Postgres` → `fcg_users` · `Jwt__SecretKey/Issuer/Audience` · `Kafka__BootstrapServers` · `Kafka__UserCreatedTopic` |
| `catalog-api` | `ConnectionStrings__Postgres` → `fcg_catalog` · `Jwt__SecretKey/Issuer/Audience` · `Kafka__BootstrapServers` · `Kafka__OrderPlacedTopic` · `Kafka__PaymentProcessedTopic` · `Kafka__PaymentsConsumerGroup` |
| `payments-api` | `Kafka__BootstrapServers` · `Kafka__OrderPlacedTopic` · `Kafka__PaymentProcessedTopic` · `Kafka__ConsumerGroup` · `Payment__RejectAboveAmount` |
| `notifications-api` | `Kafka__BootstrapServers` · `Kafka__UserCreatedTopic` · `Kafka__PaymentProcessedTopic` · `Kafka__ConsumerGroup` |

- **In-network names:** services use `kafka:9092` and `postgres:5432` (never `localhost`).
- **Kubernetes:** a shared `fcg-config` (JWT issuer/audience, Kafka bootstrap) + a shared `fcg-secret` (JWT key, Postgres password) + a per-service ConfigMap; the DB password is injected from the Secret and never duplicated.
- No container healthchecks on the .NET services (the `aspnet` image lacks curl); startup order is handled by `depends_on` (Compose) / `readinessProbe` (k8s) plus the services' retry/resilience.

## Security & secrets

- **Authentication:** shared symmetric **JWT** (HMAC-SHA256). UsersAPI issues tokens; CatalogAPI validates them locally with the **same** `SecretKey`/`Issuer`/`Audience` — no call to UsersAPI. Passwords are stored as **PBKDF2** hashes.
- **Placeholders only:** `JWT__SECRETKEY` and the Postgres credentials are development placeholders in `.env.example` and `k8s/shared-secret.yaml`. `.gitignore` excludes `.env`/secrets; **no real secrets are committed**.
- Local Kafka is **PLAINTEXT** (local-only); containers run as **non-root**.
- **Future production improvement:** replace the placeholder Kubernetes Secret with a managed secret store such as **Azure Key Vault** — documented only, **not implemented** in this MVP.

---

## Repository layout

```
fiap-cloud-games-orchestration/
├── docker-compose.yml          # postgres + kafka + kafka-init + 4 services
├── .env.example                # config template (placeholders only)
├── .gitignore · README.md
├── db/init/01-create-databases.sql   # creates fcg_users + fcg_catalog
├── k8s/                        # shared infra manifests + build/apply scripts
│   ├── namespace.yaml · shared-config.yaml · shared-secret.yaml
│   ├── postgres.yaml · kafka.yaml · kafka-topics-job.yaml
│   └── build-images.ps1/.sh · apply-all.ps1/.sh
├── contracts/README.md         # canonical event-contract reference
└── docs/                        # architecture · event-flows · testing · delivery-checklist · demo-script
```

---

## Status

Phase 2 is **delivery-ready**: four event-driven microservices over Kafka, running via
Docker Compose and on local Kubernetes, with per-service databases, a shared JWT, unit
tests, and full documentation. See [docs/delivery-checklist.md](docs/delivery-checklist.md).
