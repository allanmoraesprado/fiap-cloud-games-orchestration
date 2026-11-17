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

## P4-M2/M3/M4 — validações locais (2026-11-17)

### Terraform (`infra/terraform`, azurerm 5.14.0, Terraform 1.17.2)

```
terraform fmt -check -recursive   -> sem diferenças
terraform validate                -> Success! The configuration is valid.
```
Primeira validação reprovou (`Insufficient node_provisioning_profile blocks`, bloco obrigatório no azurerm 5.x) e
foi corrigida com `node_provisioning_profile { mode = "Manual" }`. `terraform plan/apply`: **BLOQUEADO** (K01).

### Manifests (kubeconform 0.8.0, Kubernetes 1.33 + CRD SecretProviderClass)

```
bash scripts/azure/validate-manifests.sh
Summary: 55 resources found in 25 files - Valid: 55, Invalid: 0, Errors: 0, Skipped: 0
```

### Workflows (actionlint 1.7.12)

`dotnet-service.yml`, `ci.yml` (orquestração) e os 4 `ci-cd.yml` dos serviços: 0 problemas.

### Testes dos serviços (após KeyPerFile, seed configurável, `X-App-Version`, `USER $APP_UID`)

| Repositório | Resultado |
|---|---|
| users-api | 26 aprovados (21 + 5 de `RuntimeConfiguration`) |
| catalog-api | 75 aprovados (70 + 5) — inclui 16 de integração com Elasticsearch real |
| payments-api | 20 aprovados (15 + 5) |
| notifications-function | 13 aprovados |
| **Total** | **134 / 134** |

### Ensaio dos manifests do AKS no Kubernetes local (`scripts/azure/simulate-local.sh`, namespace `fcg-sim`)

Mesmos arquivos de `k8s/azure` (plataforma) e `k8s/azure` dos 4 serviços, com apenas CSI→Secret local,
`managed-csi`→`hostpath`, LoadBalancer→NodePort 30180 e imagens locais `:sim`.

| Verificação | Resultado |
|---|---|
| Plataforma | Postgres/Kafka/Mongo (StatefulSet + PVC), Redis com `requirepass` do arquivo, Kafka topics Job `Completed`, Kong (init container renderizou `kong.yml` com a chave do segredo), Prometheus, Loki, Alloy, Grafana: todos `Running` |
| Aplicações | users-api ×2, catalog-api ×2, payments-api, notifications-function `Running`, usuário UID 1654, credenciais lidas por `KeyPerFile` |
| Smoke completo pelo Kong (`smoke-compose.ps1 -GatewayUrl http://localhost:30180 -AdminPassword <segredo>`) | **SMOKE PASSED (0 failures)**: 401 sem token, registro/login, cache MISS→HIT (Redis com senha), compra aprovada + MongoDB, biblioteca, compra rejeitada criada pelo admin semeado com a senha do "Key Vault", busca exata/fuzzy/vazia/validação, sincronização create/update/delete, reindex 200/403 |
| Smoke do CD (`scripts/ci/smoke-service.sh`) | users-api, catalog-api, payments-api: PASS com `X-App-Version` correto; notifications-function: PASS (host iniciado) |
| Prometheus | targets `users-api` ×2, `catalog-api` ×2, `payments-api`, `kong`, `prometheus` — todos `up`, rótulo `version` presente |
| Loki/Alloy | 15 serviços com logs (`compose_service`); `[WELCOME EMAIL]` encontrado com rótulos `platform="fcg"`, `cluster="aks"` |
| **Rolling update sob carga** (catalog-api 2 réplicas, `kubectl set image` para `sim2`, ~1,5 req/s pelo Kong) | **219 requisições, 219 × HTTP 200, 0 falhas**; `X-App-Version` 61× antiga → 158× nova; rollout em 28 s; `rollout history` com `change-cause` |

Falhas encontradas e corrigidas pelo ensaio: Kong com 16 workers excedendo o limite de memória (D21);
`runAsNonRoot` incompatível com `USER app` (D20); transformação do script com CRLF (Git Bash). Durante o
ensaio a VM do Docker Desktop caiu (distro `docker-desktop` parada) e foi reiniciada.

**Não validado localmente (exige Azure, M5/M6)**: Secrets Store CSI + Workload Identity reais, ACR privado,
LoadBalancer público/DNS, Entra ID/kubelogin, OIDC do GitHub, Elastic Cloud.

### Medição do cache Redis (ensaio local, 2026-11-17)

`bash scripts/measure-cache.sh http://localhost:30180 admin@fcg.com <senha-do-segredo> 30` — Kubernetes local
(Docker Desktop), manifests do AKS, Redis com senha, requisições pelo Kong, 30 rodadas (PUT invalida → GET MISS → GET HIT):

```
outcome  n    min    median   mean     p95     max   (ms)
MISS     30     5.4      6.5      8.4    25.4    28.9
HIT      30     4.0      5.0      5.9     8.4    25.3
median MISS - HIT = 1.5 ms (23.2% of the MISS median)
```

Leitura: consulta por chave primária em catálogo pequeno — ganho de 1,5 ms (23 %) na mediana e redução da
cauda (p95 25,4 → 8,4 ms). Medição **local**; a medição no AKS é item do P4-M6 (PENDENTE).

## P4-M4 — CI real no GitHub Actions (2026-11-17)

Primeira execução após o push (runners `ubuntu-latest`; CD **ignorado** porque `AZURE_DEPLOY_ENABLED` não existe):

| Repositório | Run | Commit | Resultado |
|---|---|---|---|
| users-api | [44198758496](https://github.com/allanmoraesprado/fiap-cloud-games-users-api/actions/runs/44198758496) | `6d76552` | **success** (build, testes, Docker, Trivy) |
| catalog-api | [44198763257](https://github.com/allanmoraesprado/fiap-cloud-games-catalog-api/actions/runs/44198763257) | `47b920a` | **success** (inclui testes de integração com Elasticsearch via Testcontainers no runner) |
| payments-api | [44198774020](https://github.com/allanmoraesprado/fiap-cloud-games-payments-api/actions/runs/44198774020) | `3cd02a0` | **success** |
| notifications-function | [44198777505](https://github.com/allanmoraesprado/fiap-cloud-games-notifications-function/actions/runs/44198777505) | `e240af4` | **failure** no *Security gate (CRITICAL)* |
| orchestration | [44198650915](https://github.com/allanmoraesprado/fiap-cloud-games-orchestration/actions/runs/44198650915) | `456f124` | **failure** no *actionlint* (Terraform e kubeconform: success) |

Análise e correção:

- **Function / Trivy**: reproduzido localmente (`aquasec/trivy image --severity CRITICAL --ignore-unfixed`): a
  imagem base `azure-functions/dotnet-isolated:4-dotnet-isolated8.0` trazia pacotes Debian com CVEs CRITICAL
  corrigíveis e o runtime ASP.NET Core 8.0.31 (correção em 8.0.32). O gate funcionou como projetado. Correção no
  Dockerfile: `apt-get upgrade` e troca do runtime .NET 8 do worker pelo 8.0.34 da imagem oficial `aspnet:8.0`.
  Novo scan local: **0 CRITICAL corrigíveis**. Validação funcional no ensaio: worker carregando
  `Microsoft.NETCore.App/8.0.34`, `[WELCOME EMAIL]` processado; durante a troca de pods nenhum evento foi
  perdido (Loki mostra o evento anterior no pod antigo e o seguinte no novo).
- **actionlint**: no runner o actionlint executa o shellcheck nos blocos `run`; avisos SC2016 (lista de
  variáveis do `envsubst` em aspas simples, intencional) e SC2094 (falso positivo). Diretiva
  `shellcheck disable` com justificativa; actionlint + shellcheck 0.11.0 locais sem apontamentos.
