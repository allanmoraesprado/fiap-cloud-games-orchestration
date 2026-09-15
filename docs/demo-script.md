# Demo Script (Roteiro) — FIAP Cloud Games (Phase 3)

A practical **12–15 minute** recording. Commands assume the service repos are cloned as
siblings of the orchestration repo and run from **PowerShell** on Windows
(`curl` = `curl.exe`; Git Bash also works). Keep ~1 s between gateway calls (rate limit 5 req/s).

## 0. Prep (before recording, off camera)
- Docker Desktop running with Kubernetes enabled; `cp .env.example .env` adjusted for local port clashes.
- Compose stack **already up and warm**: `docker compose up -d --build` (first boot takes ~1 min).
- Kubernetes stack **already applied** (`.\k8s\build-images.ps1` + `.\k8s\apply-all.ps1`) so the
  cluster section is a walkthrough, not a wait. Ports: Compose 8000/3000/9090, Kubernetes 30080/30300/30090.
- Grafana open on **FCG Overview** and **FCG Logs** in browser tabs; a terminal ready.
- Pick a purchase user e-mail you have not used before.

## 1. Repositories and architecture (~1.5 min)
- Show the six repositories and their roles (`README.md` table): three .NET APIs, the
  **Notifications Function** (serverless), the orchestration repo, and `notifications-api` as
  Phase 2 history.
- Show `docs/architecture.md` diagram: Kong at the edge, Kafka in the middle, PostgreSQL ×2,
  MongoDB, Redis, Prometheus/Loki/Grafana.

## 2. Docker Compose stack (~1 min)
```powershell
docker compose ps        # 14 containers: infra healthy, 3 APIs, notifications-function, kong, prometheus, grafana, loki, alloy
docker compose config --services
```
- Mention: host ports parameterized in `.env`, `notifications-api` only under `--profile phase2-legacy`.

## 3. Kong routes and JWT at the edge (~1.5 min)
```powershell
curl.exe http://127.0.0.1:8001/routes | ConvertFrom-Json | Select-Object -ExpandProperty data | Select-Object name, paths
curl.exe -i http://localhost:8000/api/games                 # 401 from Kong (no token)
```
- Show `gateway/kong.yml`: public `/api/auth`, protected routes with the `jwt` plugin,
  rate-limiting, correlation-id, prometheus. Explain defense in depth (services validate too).

## 4. Registration and login through Kong (~1 min)
```powershell
curl.exe -s -X POST http://localhost:8000/api/auth/register -H "Content-Type: application/json" -d '{"name":"Demo","email":"demo1@fcg.com","password":"Demo@1234"}'
$TOKEN = (curl.exe -s -X POST http://localhost:8000/api/auth/login -H "Content-Type: application/json" -d '{"email":"demo1@fcg.com","password":"Demo@1234"}' | ConvertFrom-Json).token
docker compose logs notifications-function | Select-String "WELCOME EMAIL"
```

## 5. Cache MISS / HIT (~1 min)
```powershell
curl.exe -si http://localhost:8000/api/games -H "Authorization: Bearer $TOKEN" | Select-String "X-FCG-Cache"   # MISS
curl.exe -si http://localhost:8000/api/games -H "Authorization: Bearer $TOKEN" | Select-String "X-FCG-Cache"   # HIT
docker compose exec redis redis-cli KEYS 'fcg:catalog:*'
```

## 6. Approved purchase → MongoDB → payment status → library (~2 min)
```powershell
$GAME = "<id of Pixel Racers from the list>"
$ORDER = (curl.exe -s -X POST http://localhost:8000/api/library/acquire/$GAME -H "Authorization: Bearer $TOKEN" | ConvertFrom-Json).orderId
Start-Sleep 3
curl.exe -s http://localhost:8000/api/payments/order/$ORDER -H "Authorization: Bearer $TOKEN"     # status Approved + reason
docker compose exec mongo mongosh -u fcg -p fcg --authenticationDatabase admin fcg_payments --quiet --eval "db.payments.findOne({orderId:'$ORDER'})"
curl.exe -si http://localhost:8000/api/library/my-games -H "Authorization: Bearer $TOKEN"        # MISS (invalidated), game listed
docker compose logs notifications-function | Select-String "PURCHASE CONFIRMATION"
```

## 7. Rejected purchase (~1 min)
- Acquire a game priced above 1000 (create one as `admin@fcg.com / Admin@123` if needed) →
  payment query shows **Rejected** with the reason; Mongo document stored; function logs
  "no confirmation e-mail sent"; library unchanged.

## 8. Centralized logs — Loki / Grafana (~1.5 min)
- Grafana → **FCG Logs**: paste `$ORDER` in the OrderId box → lines from CatalogAPI,
  PaymentsAPI, Kong and the Notifications Function for the same order.
- E-mail panel: `[WELCOME EMAIL]` and `[PURCHASE CONFIRMATION]`. Mention Alloy → Docker socket → Loki.

## 9. Metrics — Prometheus / Grafana (~1 min)
- Grafana → **FCG Overview**: request rate by service, Kong routes and 401/429, cache
  hit/miss, payment decisions/queries, Kafka events. Optionally `http://localhost:9090/targets`.
- Optional 429 demo: `1..12 | % { curl.exe -s -o NUL -w "%{http_code} " http://localhost:8000/api/games -H "Authorization: Bearer $TOKEN" }`.

## 10. Kubernetes (~2.5 min)
```powershell
kubectl get pods,svc,configmap,secret -n fcg      # 12 pods Running + kafka-topics Completed, NodePorts 30080/30090/30300
```
- Show `k8s/` layout and `docs/kubernetes.md` (ConfigMaps generated from the same Kong/Prometheus/Grafana files).
- Repeat the short flow on `http://localhost:30080`: register → login → games (MISS/HIT) →
  acquire → payment query → `kubectl -n fcg logs deploy/notifications-function | Select-String EMAIL`.
- `kubectl exec -n fcg deploy/kafka -- /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --all-groups` → LAG 0.
- Grafana on `http://localhost:30300` → FCG Overview (metrics); explain that logs on
  Kubernetes use `kubectl logs` (Loki/Alloy documented as a future improvement).

## 11. Wrap-up (~1 min)
- Recap the Phase 3 requirements: gateway with JWT at the edge, serverless notifications,
  NoSQL, cache, metrics + centralized logs, Compose + Kubernetes.
- Local-only and placeholders: dev secrets, PLAINTEXT Kafka, emptyDir, NodePorts.
- Future cloud evolution: Azure Function App + Event Hubs/SASL, Key Vault, managed Mongo/Redis,
  Kong on AKS, Loki on Kubernetes, outbox/DLQ, RS256/JWKS.

## Teardown (off camera)
```powershell
kubectl delete namespace fcg
docker compose down -v
```
