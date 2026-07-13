# FCG Event Contracts (Canonical Reference)

> **Documentation only.** This folder is the single source of truth for the
> event shapes exchanged over Kafka. It contains **no compiled code**. Each
> microservice keeps its **own** local `Contracts/` folder with the C# `record`
> types it produces or consumes, mirrored from the definitions below.
>
> **Evolution rule:** contracts are **additive-only** — never rename or remove a
> field once published. Add new optional fields if needed.
>
> Serialization: **JSON** (UTF-8). All timestamps are **UTC**.

---

## Topic & flow map

| Topic | Key | Producer | Consumer group(s) |
|---|---|---|---|
| `fcg.users.created` | `UserId` | UsersAPI | `notifications-service` |
| `fcg.orders.placed` | `OrderId` | CatalogAPI | `payments-service` |
| `fcg.payments.processed` | `OrderId` | PaymentsAPI | `catalog-service`, `notifications-service` |

> The two consumers of `fcg.payments.processed` use **different** consumer group
> ids, so **both** receive every message (fan-out).

---

## UserCreatedEvent

Produced by **UsersAPI** after a user is successfully registered.
Consumed by **NotificationsAPI** to log a simulated welcome e-mail.

| Field | Type | Notes |
|---|---|---|
| `EventId` | `Guid` | Unique id of this event instance |
| `UserId` | `Guid` | Newly created user id |
| `Name` | `string` | User display name |
| `Email` | `string` | User e-mail (lowercased) |
| `OccurredAt` | `DateTime` | UTC timestamp |

```csharp
public record UserCreatedEvent(
    Guid EventId,
    Guid UserId,
    string Name,
    string Email,
    DateTime OccurredAt);
```

---

## OrderPlacedEvent

Produced by **CatalogAPI** when a user starts a purchase
(`POST /library/acquire/{gameId}`). Consumed by **PaymentsAPI**.

| Field | Type | Notes |
|---|---|---|
| `EventId` | `Guid` | Unique id of this event instance |
| `OrderId` | `Guid` | Correlation id (Order → Payment → Library) |
| `UserId` | `Guid` | Taken from the JWT, never from the request body |
| `GameId` | `Guid` | Game being purchased |
| `Price` | `decimal` | Price read from the Game aggregate at order time |
| `OccurredAt` | `DateTime` | UTC timestamp |

```csharp
public record OrderPlacedEvent(
    Guid EventId,
    Guid OrderId,
    Guid UserId,
    Guid GameId,
    decimal Price,
    DateTime OccurredAt);
```

---

## PaymentProcessedEvent

Produced by **PaymentsAPI** after the simulated payment decision.
Consumed by **CatalogAPI** (adds the game to the library if approved) **and**
**NotificationsAPI** (logs a simulated purchase-confirmation e-mail if approved).

| Field | Type | Notes |
|---|---|---|
| `EventId` | `Guid` | Unique id of this event instance |
| `OrderId` | `Guid` | Echoes `OrderPlacedEvent.OrderId` |
| `UserId` | `Guid` | Same user |
| `GameId` | `Guid` | Same game |
| `Price` | `decimal` | Same price |
| `Status` | `string` | `"Approved"` or `"Rejected"` (string, not enum) |
| `OccurredAt` | `DateTime` | UTC timestamp |

```csharp
public record PaymentProcessedEvent(
    Guid EventId,
    Guid OrderId,
    Guid UserId,
    Guid GameId,
    decimal Price,
    string Status,
    DateTime OccurredAt);
```
