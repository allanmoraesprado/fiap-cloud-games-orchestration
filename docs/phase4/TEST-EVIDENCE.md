# Evidências de Testes — Fase 4

Somente resultados efetivamente executados. Itens não executados aparecem como `PENDENTE`/`BLOQUEADO`.

## Baseline (P4-M0, 2026-11-17)

`dotnet test` em cada repositório, estação local (SDK 10.0.102, runtime 8.0.20):

| Repositório | Commit | Resultado |
|---|---|---|
| users-api | `3681486` | 21 aprovados, 0 falhas |
| catalog-api | `e3d03b3` | 22 aprovados, 0 falhas |
| payments-api | `72bde0f` | 15 aprovados, 0 falhas |
| notifications-function | `0e7e956` | 13 aprovados, 0 falhas |
| **Total** | | **71 / 71** |

Verificação de acesso Azure (somente leitura):

```
az account show            -> state: "Warned"
az group list              -> ERROR (SubscriptionNotFound)
GET /subscriptions (ARM)   -> []
```

## P4-M1 — Elasticsearch (2026-11-17)

### CatalogAPI — `dotnet test` (commit `b2a66b5`)

| Conjunto | Resultado |
|---|---|
| Unitários (`Category!=Integration`) | **54 aprovados**, 0 falhas (22 anteriores + 32 novos: validação, sincronização, reconciliação, 503) |
| Integração (`Category=Integration`, Elasticsearch 9.5.5 real via Testcontainers) | **16 aprovados**, 0 falhas |
| **Total** | **70 / 70** (build sem warnings) |

Testes de integração (Elasticsearch real):

| Requisito | Teste | Resultado |
|---|---|---|
| Busca exata | `Exact_title_is_the_top_result` | aprovado |
| Erro de digitação | `Misspelled_query_still_finds_the_intended_game` ("Cosmik Odisey", "shadw realms", "Pixl Racer", "mythik") | aprovado (4 casos) |
| Relevância | `Results_are_ordered_by_relevance`, `Exact_match_outranks_partial_matches` | aprovado |
| Nenhum resultado | `Unknown_terms_return_an_empty_page` | aprovado |
| Paginação / filtro | `Results_are_paginated_without_overlap`, `Genre_filter_is_case_insensitive` | aprovado |
| Criação → indexação | `Created_game_is_searchable_right_after_creation` | aprovado |
| Edição → atualização | `Edited_game_is_found_by_its_new_values_only` | aprovado |
| Remoção | `Deleted_game_disappears_from_search` | aprovado |
| Reindexação | `Full_reindex_rebuilds_the_index_from_the_database`, `Lost_index_is_recreated_and_fully_reloaded_by_the_reconciler` | aprovado |
| Indisponibilidade | `Engine_outage_answers_unavailable_keeps_writes_working_and_recovers` | aprovado |

### Smoke real — Docker Compose, através do Kong

Stack isolada (`docker compose -p fcg-p4`, portas remapeadas para não interferir em ambientes já em
execução na estação), imagens construídas do código commitado. Comando:

```powershell
$env:COMPOSE_PROJECT_NAME = "fcg-p4"
.\scripts\smoke-compose.ps1 -GatewayUrl http://localhost:18000 -PrometheusUrl http://localhost:19090 -SearchOutage -SkipLoki
```

Saída (resumo fiel): **`== SMOKE PASSED (0 failures)`** — fluxo da Fase 3 (registro, login, cache MISS→HIT,
compra aprovada, pagamento no MongoDB, biblioteca, compra rejeitada, 5 targets Prometheus `up`) e:

```
[12] Search (Elasticsearch) through Kong
  PASS  GET /api/games/search without token -> 401 from Kong
  PASS  exact 'Cosmic Odyssey' -> top hit 'Cosmic Odyssey' (score 54.545956, total 1)
  PASS  fuzzy 'Cosmik Odisey' -> top hit 'Cosmic Odyssey'
  PASS  unknown terms -> 200 with total 0
  PASS  q='a' -> 400 (validation)
  PASS  pageSize=500 -> 400 (validation)
  PASS  created 'Nebula Smoke 20261117192007' -> found right away by the misspelled 'Nebla Smoke 20261117192007'
  PASS  updated to 'Quasar Smoke 20261117192007' -> index returns the new title and price
  PASS  deleted game -> no longer returned by search
  PASS  POST /api/games/search/reindex (Admin) -> 200, indexed 9 games
  PASS  reindex as a regular user -> 403
[12b] Search engine outage (docker compose stop/start elasticsearch)
  PASS  search with Elasticsearch stopped -> 503 (Retry-After: 10)
  PASS  create game during the outage -> 201 (database first, index deferred)
  PASS  engine back: reconciliation indexed the game created during the outage (35s)
```

Logs da CatalogAPI na subida (Elasticsearch ainda iniciando):

```
[22:14:28 WRN] Search index reconciliation failed; retrying in 15s.  (Connection refused (elasticsearch:9200))
[22:14:46 INF] Search index fcg-games created.
[22:14:46 INF] Search index fcg-games full load: 4 games indexed.
```

Métricas (`GET :18082/metrics`) após o smoke:

```
fcg_search_requests_total{outcome="results"} 59
fcg_search_requests_total{outcome="empty"} 3
fcg_search_requests_total{outcome="invalid"} 6
fcg_search_requests_total{outcome="unavailable"} 6
fcg_search_index_operations_total{operation="upsert",result="failure"} 2
fcg_search_index_operations_total{operation="reconcile",result="failure"} 5
fcg_search_index_operations_total{operation="reindex",result="success"} 3
```

Observações:
- Primeira execução do smoke reprovou 2 checagens por **falso negativo do script** (PowerShell 5.1 não
  expõe `.Count` em `PSCustomObject` único); a API havia respondido 200 corretamente. Script corrigido
  e reexecutado com 0 falhas.
- Checagem do Loki pulada nesta stack isolada: o Alloy filtra o projeto `fcg-orchestration` (comportamento
  da Fase 3, inalterado).
- Validação contra o **Elastic Cloud**: PENDENTE (P4-M5/M6).
