# NoSQL persistence (MongoDB) — FIAP Cloud Games (Phase 3)

Phase 3 adds **MongoDB 7** as the **NoSQL database of PaymentsAPI**. PaymentsAPI was stateless
in Phase 2; it now owns its own store (`fcg_payments`) and keeps the **payment history**,
one document per order, queryable through the gateway. The implementation lives in
`fiap-cloud-games-payments-api` (`Payments/`, `Infrastructure/Mongo/`); this page documents
the design and how to observe it locally.

## Why MongoDB satisfies the NoSQL requirement

- **Document model fits the data:** a payment record is a self-contained document keyed by
  `orderId`, read by key, never joined with other tables. There is no relational structure to
  normalize.
- **Schema flexibility:** the document can grow (provider payloads, retries, refunds) without
  migrations — the natural evolution path for a payments history.
- **Database-per-service, different engine:** PaymentsAPI stays **independent from
  PostgreSQL** (UsersAPI/CatalogAPI keep PostgreSQL), which is the polyglot-persistence
  point of the exercise.
- **Idempotency at the database:** a unique index on `orderId` plus an upsert makes the
  at-least-once Kafka delivery safe: replaying an `OrderPlacedEvent` updates the same document.

## Design

| Item | Value |
|---|---|
| Image | `mongo:7` (Compose service `mongo`, volume `mongo_data`, healthcheck `mongosh ping`) |
| Database / collection | `fcg_payments` / `payments` |
| Key | `orderId` (unique index `ux_orderId`); `_id` is a separate Guid |
| Write | Idempotent upsert per `orderId` (`$setOnInsert` `_id`/`createdAt`, `$set` the rest, `updatedAt` refreshed) |
| Credentials | Root user `MONGO_USER`/`MONGO_PASSWORD` (dev placeholders `fcg`/`fcg`), `authSource=admin` |
| Host port | `MONGO_HOST_PORT` (default 27017) — only the host side; containers use `mongo:27017` |

### Payment document

```json
{
  "_id": "…", "orderId": "…", "userId": "…", "gameId": "…",
  "price": NumberDecimal("49.90"), "status": "Approved",
  "reason": "Approved by the payment simulation.",
  "orderPlacedEventId": "…", "paymentProcessedEventId": "…",
  "orderOccurredAt": ISODate("…"), "processedAt": ISODate("…"),
  "createdAt": ISODate("…"), "updatedAt": ISODate("…")
}
```

Guids are stored as strings (readable in `mongosh`), `price` as `Decimal128`, dates in UTC.
`status` is `Approved` or `Rejected` and `reason` explains the simulated decision.

## Flow

1. CatalogAPI publishes `OrderPlacedEvent` (`POST /api/library/acquire/{gameId}` → 202 `{ orderId }`).
2. PaymentsAPI consumes it, decides, **upserts** the document, publishes `PaymentProcessedEvent`
   and commits the offset. If MongoDB is unavailable the error is logged and the event is still
   published (no outbox in this MVP).
3. The client queries **`GET /api/payments/order/{orderId}`** through Kong.

## Payment status query through the gateway

| Caller | Result |
|---|---|
| No token / invalid token | **401** from Kong (`jwt` plugin on `/api/payments`) |
| Buyer (token user id = `userId`) | **200** `PaymentResponse` |
| Another regular user | **403** from PaymentsAPI (ownership rule) |
| Admin | **200** for any order |
| Unknown order | **404** from PaymentsAPI |

PaymentsAPI validates the JWT again (same shared secret as UsersAPI/CatalogAPI) and applies
the ownership/role rule itself — Kong only checks signature and expiry.

```bash
TOKEN=...   # buyer login through Kong (see docs/gateway.md)
ORDER=$(curl -s -X POST http://localhost:8000/api/library/acquire/<gameId> -H "Authorization: Bearer $TOKEN" | sed -n 's/.*"orderId":"\([^"]*\)".*/\1/p')
sleep 3
curl -i http://localhost:8000/api/payments/order/$ORDER -H "Authorization: Bearer $TOKEN"     # 200, status Approved/Rejected
curl -i http://localhost:8000/api/payments/order/$ORDER                                       # 401 (Kong)
```

## Inspecting MongoDB

```bash
docker compose exec mongo mongosh -u fcg -p fcg --authenticationDatabase admin fcg_payments --eval 'db.payments.find().pretty()'
docker compose exec mongo mongosh -u fcg -p fcg --authenticationDatabase admin fcg_payments --eval 'db.payments.countDocuments({orderId:"<orderId>"})'
docker compose exec mongo mongosh -u fcg -p fcg --authenticationDatabase admin fcg_payments --eval 'db.payments.getIndexes()'
```

Replay demo (idempotency): re-publish the same `OrderPlacedEvent` on `fcg.orders.placed` with
the console producer → PaymentsAPI logs `duplicate event handled idempotently`, `countDocuments`
for that `orderId` stays **1**, `updatedAt` moves, `createdAt` does not.

## Out of scope (by design)

No replica set, no transactions, no outbox, no MongoDB exporter for Prometheus (PaymentsAPI
exports `fcg_payments_history_writes_total` and `fcg_payments_queries_total` instead). On
Kubernetes MongoDB runs from `k8s/mongo.yaml` (emptyDir, root password from `fcg-secret`).
A cloud deployment would use a managed MongoDB (Azure Cosmos DB for MongoDB or Atlas) with
the connection string in a secret store — documented only.
