# Demo Script (Roteiro) — FIAP Cloud Games (Phase 2)

A practical ~8–12 minute walkthrough. Commands assume the four service repos are
cloned as siblings of the orchestration repo. Run `docker compose exec` / `kubectl`
commands from **PowerShell** on Windows.

## 0. Prep (before recording)
- Docker Desktop running; (for the k8s part) Kubernetes enabled.
- `cd fiap-cloud-games-orchestration`.

## 1. Intro (~1 min)
- The problem: evolve the Phase 1 monolith into event-driven microservices.
- Show `docs/architecture.md` diagram: four services, Kafka, two databases, shared JWT.

## 2. Start the system with Docker Compose (~1–2 min)
```powershell
docker compose up -d --build
docker compose ps        # postgres + kafka healthy, kafka-init Exited(0), 4 services Up
```

## 3. Registration flow → welcome e-mail (~1 min)
- `POST http://localhost:8080/api/auth/register` (Swagger or curl) → 201.
```powershell
docker compose logs notifications-api | Select-String "WELCOME EMAIL"
```

## 4. Purchase flow — approved (~2 min)
- `POST http://localhost:8080/api/auth/login` → copy token.
- `GET http://localhost:8082/api/games` with the token → 200 (cross-service JWT).
- `POST http://localhost:8082/api/library/acquire/{gameId}` → 202.
```powershell
docker compose logs users-api catalog-api payments-api notifications-api
# order placed -> payment Approved -> Added game to library -> PURCHASE CONFIRMATION
```
- `GET http://localhost:8082/api/library/my-games` → the game appears.

## 5. Purchase flow — rejected (~1 min)
- As admin, create a game priced `1500`; acquire it → payment **Rejected**; library
  not updated; no confirmation e-mail.

## 6. Kafka evidence (~1 min)
```powershell
docker compose exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
docker compose exec kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group catalog-service
docker compose exec kafka /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group notifications-service
```
- Show fan-out and **LAG 0**. Then `docker compose down`.

## 7. Kubernetes (~2–3 min)
```powershell
.\k8s\build-images.ps1
.\k8s\apply-all.ps1
kubectl get pods -n fcg
kubectl get svc  -n fcg
kubectl port-forward -n fcg svc/users-api   8080:8080   # terminal A
kubectl port-forward -n fcg svc/catalog-api 8082:8080   # terminal B
```
- Repeat register + purchase; show pod logs; then consumer groups:
```powershell
$KPOD = kubectl get pod -n fcg -l app=kafka -o jsonpath='{.items[0].metadata.name}'
kubectl exec -n fcg $KPOD -- /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group catalog-service
```

## 8. Wrap-up (~1 min)
- Recap: 4 services, 3 topics, database-per-service, shared JWT, Compose + Kubernetes.
- Design decisions (what was intentionally not built) and future improvements
  (RS256/JWKS, PVCs, retries/DLQ, observability, **Azure Key Vault** for secrets).

## Teardown
```powershell
kubectl delete namespace fcg      # kubernetes
docker compose down -v            # compose
```
