# Delivery Checklist — FIAP Cloud Games (Phase 2)

Requirement → where it is satisfied.

## Architecture & services
- [x] Four independent microservices — `users-api`, `catalog-api`, `payments-api`, `notifications-api`
- [x] Event-driven communication (asynchronous) — Kafka topics
- [x] Independent Git repositories (5 total, incl. orchestration)
- [x] Each service has its own solution/project and **multi-stage Dockerfile**

## Messaging
- [x] **Apache Kafka**, single broker, KRaft (no Zookeeper) — `k8s/kafka.yaml`, compose
- [x] **`Confluent.Kafka`** .NET client — service `.csproj`
- [x] No Confluent Cloud / Schema Registry / Kafka Connect
- [x] Event contracts: `UserCreatedEvent`, `OrderPlacedEvent`, `PaymentProcessedEvent` — [`../contracts/README.md`](../contracts/README.md)
- [x] Registration flow and purchase flow — [`event-flows.md`](event-flows.md)

## Payments
- [x] **Simulated** payments only (deterministic rule); no Mercado Pago / Stripe / PayPal / SDKs / webhooks

## Persistence
- [x] Database-per-service: `fcg_users` (UsersAPI), `fcg_catalog` (CatalogAPI); Payments/Notifications stateless
- [x] No cross-service foreign keys

## Security
- [x] Shared **JWT** secret/issuer/audience between UsersAPI and CatalogAPI via env / k8s Secret
- [x] CatalogAPI validates UsersAPI tokens (no synchronous call)
- [x] **Placeholder secrets only**; no real secrets committed
- [x] Azure Key Vault mentioned **only** as a future improvement

## Docker Compose
- [x] `docker compose up` runs the complete system — orchestration `docker-compose.yml`
- [x] In-network names `kafka:9092`, `postgres:5432`

## Kubernetes (local only)
- [x] **Deployments** (no bare Pods), **Services**, **ConfigMaps**, **Secret**
- [x] Communication via Service names — `k8s/` manifests
- [x] `/k8s` in each service repo + shared infra + apply scripts in orchestration (hybrid)
- [x] Validated on Docker Desktop Kubernetes; no cloud / Ingress / mesh / Rancher / managed k8s

## Quality & docs
- [x] Unit tests (37) + validated E2E flows — [`testing.md`](testing.md)
- [x] READMEs for all five repositories
- [x] Architecture + event-flow documentation with Mermaid diagrams

## Out of scope (by design)
- [x] No cloud infrastructure, no real payment/e-mail providers, no Key Vault implementation, Phase 1 monolith untouched
