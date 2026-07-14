# Testing Evidence — FIAP Cloud Games (Phase 2)

## Unit tests

Run per repository with `dotnet test`.

| Service | Tests | Covers |
|---|---|---|
| UsersAPI | 21 | registration validation (name/e-mail/password), duplicate e-mail (409), invalid login (401), JWT issuance, publish-on-register |
| CatalogAPI | 9 | game admin policy (non-admin cannot create/delete), game validator, **purchase-completion idempotency** (approved+new → add; approved+owned → skip; rejected → skip) |
| PaymentsAPI | 5 | deterministic simulator: approves typical & boundary prices; rejects zero, negative, and above threshold |
| NotificationsAPI | 2 | welcome + purchase-confirmation message formatting |
| **Total** | **37** | |

## Integration evidence (validated end-to-end)

Both deployment targets were validated with the full register → purchase flow.

### Docker Compose (one command)

```bash
docker compose up -d --build
```
Observed: register → **welcome e-mail** (notifications-api log) → login → cross-service
`GET /api/games` (200, shared JWT) → acquire (202) → `OrderPlacedEvent` → payment
**Approved** → **library write** → **purchase confirmation** → `my-games` returns the
game. Rejected path (price > 1000) writes nothing and logs no confirmation.

### Local Kubernetes (namespace `fcg`)

```bash
.\k8s\build-images.ps1
.\k8s\apply-all.ps1
kubectl get pods -n fcg      # postgres, kafka, 4 services Running; kafka-topics Completed
kubectl get svc  -n fcg      # 6 ClusterIP services
```
Port-forward `users-api` (8080) + `catalog-api` (8082) and repeat the flow — same
result, entirely in-cluster.

### Kafka / consumer-group evidence

```bash
# Compose:
docker compose exec kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group <group>
# Kubernetes:
KPOD=$(kubectl get pod -n fcg -l app=kafka -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n fcg $KPOD -- /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group <group>
```
All three consumer groups (`payments-service`, `catalog-service`,
`notifications-service`) observed at **LAG 0**, with `fcg.payments.processed`
consumed by both `catalog-service` and `notifications-service` (fan-out).

## How to run all tests

```bash
# in each service repo
dotnet test
```
