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

`bash scripts/measure-cache.sh http://localhost:30180 admin@fcg.com 30` (senha em `FCG_ADMIN_PASSWORD`) — Kubernetes local
(Docker Desktop), manifests do AKS, Redis com senha, requisições pelo Kong, 30 rodadas (PUT invalida → GET MISS → GET HIT):

```
outcome  n    min    median   mean     p95     max   (ms)
MISS     30     5.4      6.5      8.4    25.4    28.9
HIT      30     4.0      5.0      5.9     8.4    25.3
median MISS - HIT = 1.5 ms (23.2% of the MISS median)
```

Leitura: consulta por chave primária em catálogo pequeno — ganho de 1,5 ms (23 %) na mediana e redução da
cauda (p95 25,4 → 8,4 ms). Medição **local**; a medição no AKS está na seção [Validação na nuvem](#validação-na-nuvem-azure-aks).

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

Reexecução após as correções:

| Repositório | Run | Commit | Resultado |
|---|---|---|---|
| notifications-function | [44200953091](https://github.com/allanmoraesprado/fiap-cloud-games-notifications-function/actions/runs/44200953091) | `6c1198f` | **success** (gate do Trivy aprovado) |
| orchestration | [44200994619](https://github.com/allanmoraesprado/fiap-cloud-games-orchestration/actions/runs/44200994619) | `b026a28` | **success** (Terraform, kubeconform com os `k8s/azure` dos 4 serviços, Compose, shellcheck, actionlint) |

Estado: **CI verde nos 5 repositórios**. Job de CD: ignorado por desenho até `AZURE_DEPLOY_ENABLED=true` (M5).


## Validação na nuvem (Azure AKS)

Ambiente real provisionado em **2026-11-22** (horários em UTC; parte das execuções já em 2026-11-23 UTC) na
assinatura `FCG-Phase4` (pay-as-you-go, `Enabled`, operador Owner), região `eastus2`.

### Preflight e provisionamento (Terraform)

- `scripts/azure/preflight.sh`: ferramentas OK, assinatura `Enabled`, ARM acessível, papel **Owner**,
  7 resource providers registrados (6 registrados nesta execução), cota `standardDav6Family` 0/10 vCPU.
  Cota `standardDASv5Family` = **0** ⇒ nó `Standard_D4as_v6` (D23).
- `terraform plan`: **66 to add, 0 to change, 0 to destroy**; `terraform apply`: **66 added**. Segundo apply
  (endpoint do Elastic Cloud e prefixo OIDC da Function, D24): **0 added, 3 changed, 0 destroyed**.
- Nenhum segredo no state: os 12 `azurerm_key_vault_secret` têm `value_wo = null`; busca do valor da API key
  do Elastic no `terraform.tfstate` e na saída do plan: **0 ocorrências**.
- Key Vault `kv-fcg-demo-kwsfp`: 12 segredos (10 gerados, 2 externos do Elastic Cloud), listados só por nome.
- AKS `aks-fcg-demo`: Kubernetes **1.36.5**, tier Free, 1 nó `Standard_D4as_v6` (Ubuntu 24.04), OIDC issuer +
  Workload Identity, Entra ID + Azure RBAC, contas locais desabilitadas, add-on Key Vault Secrets Provider.
- ACR `acrfcgdemokwsfp`: Basic, `adminUserEnabled=false`, `anonymousPullEnabled=false`.

### Plataforma (`scripts/azure/deploy-platform.sh`)

Namespace, 8 ServiceAccounts com Workload Identity, 8 SecretProviderClasses, PostgreSQL/Kafka/MongoDB
(StatefulSets com PVC `managed-csi` de 8 GiB), Redis, Job de tópicos do Kafka, Kong (`LoadBalancer`
**4.152.230.114**, DNS `fcg-demo-kwsfp.eastus2.cloudapp.azure.com`), Prometheus, Loki, Alloy e Grafana.

Ocorrências na primeira execução (sem alteração de código de aplicação):

- `Forbidden` logo após o apply: o papel *AKS RBAC Cluster Admin* do operador levou alguns minutos para
  propagar; a reexecução passou.
- O primeiro *attach* dos discos no nó levou ~10 min (`FailedAttachVolume` por timeout, depois
  `SuccessfulAttachVolume`); a reexecução do script (idempotente) concluiu a plataforma.

Segredos montados (somente nomes, `ls /mnt/secrets-store`) e status do CSI:

| Workload | Segredos acessíveis | `SecretProviderClassPodStatus` |
|---|---|---|
| redis | `redis-password` | mounted |
| grafana | `grafana-admin-password` | mounted |
| postgres | `postgres-admin-password` | mounted |
| mongo | `mongo-root-password` | mounted |
| kong | `jwt-signing-key`, montado só no init container que gera o `kong.yml` | mounted |
| catalog-api | **5** (role assignments por segredo): `jwt-signing-key`, `catalog-api-postgres-connection`, `catalog-api-redis-connection`, `catalog-elasticsearch-url`, `catalog-elasticsearch-api-key` | mounted |

`kubectl -n fcg get secrets` → **No resources found** (nenhum Secret do Kubernetes com credenciais).

### CI/CD real (GitHub Actions → ACR → AKS)

Variáveis aplicadas nos 4 repositórios por `scripts/azure/github-variables.sh` (identificadores; **0 segredos**
nos 5 repositórios). Credenciais federadas da identidade de deploy: somente `ref:refs/heads/main` dos 4
serviços. Papéis: `AcrPush` + `Reader` (ACR), *AKS Cluster User*, *AKS RBAC Writer* no namespace `fcg`.

| Execução | Resultado | Análise / correção |
|---|---|---|
| 1ª rodada (dispatch dos 4 serviços) | OIDC ✔, push no ACR ✔; **falha** em *Setup kubelogin* | `azure/use-kubelogin` com `latest` exige `GITHUB_TOKEN` → versão fixada `v0.2.22` (orchestration `cfe202a`) |
| users-api [45102427739](https://github.com/allanmoraesprado/fiap-cloud-games-users-api/actions/runs/45102427739) | **success** (CI + CD + smoke) | — |
| catalog-api [45102431677](https://github.com/allanmoraesprado/fiap-cloud-games-catalog-api/actions/runs/45102431677) | **success** (smoke inclui a busca no Elastic Cloud) | — |
| notifications-function [45102440575](https://github.com/allanmoraesprado/fiap-cloud-games-notifications-function/actions/runs/45102440575) | **success** | valida o `sub` OIDC imutável (D24) |
| payments-api [45102435758](https://github.com/allanmoraesprado/fiap-cloud-games-payments-api/actions/runs/45102435758) | rollout ✔; smoke **falhou** (`register` 502) | a UsersAPI ainda subia em paralelo; nova execução depois dela |
| payments-api [45102758346](https://github.com/allanmoraesprado/fiap-cloud-games-payments-api/actions/runs/45102758346) | **success** | — |
| **catalog-api [45103663258](https://github.com/allanmoraesprado/fiap-cloud-games-catalog-api/actions/runs/45103663258) — evento `push`** | **success** | deploy automático do commit `ee2d0dd` |

Run disparado pelo push (`ee2d0ddd7645d56bc96e9aa859deb68d71f878b0`): CI 03:03:21–03:05:48 (testes, Trivy,
gate CRITICAL), push no ACR 03:06:09–03:06:23 (digest
`sha256:c7b2fb7f60b0804544a5876d6b8e88f7d6451da526a704e4c154b859587d979b`), deploy 03:06:29, rollout verificado
03:06:32–03:06:59, smoke 03:06:59–03:07:05 (`GET /api/games -> 200, X-App-Version ee2d0ddd…`, busca
`q=cosmic` → 200).

`kubectl -n fcg rollout history deployment/catalog-api`:

```
REVISION  CHANGE-CAUSE
1         allanmoraesprado/fiap-cloud-games-catalog-api@47b920a9bb087a66261674c9308bcd5736c6642a run 45102431677
2         allanmoraesprado/fiap-cloud-games-catalog-api@ee2d0ddd7645d56bc96e9aa859deb68d71f878b0 run 45103663258
3         allanmoraesprado/fiap-cloud-games-catalog-api@ee2d0ddd7645d56bc96e9aa859deb68d71f878b0 run 45103663258
```

(revisão 3 = `kubectl rollout restart` do teste de disponibilidade abaixo; a anotação é herdada.)

Tags no ACR (somente SHA completo, nenhuma `latest`): `fcg-users-api:6d76552…`, `fcg-catalog-api:47b920a…` e
`ee2d0dd…`, `fcg-payments-api:3cd02a0…`, `fcg-notifications-function:6c1198f…`.

### Rolling Update sob carga

- Durante o deploy do push, uma primeira sonda a ~3 req/s passou do limite do Kong (120 req/min por IP):
  166 respostas **429** do rate limiting, sem `X-App-Version`. A troca `47b920a` → `ee2d0dd` foi observada,
  mas essa medição **não** é usada como prova de disponibilidade.
- Medição válida com `scripts/rolling-probe.sh` (0,6 s entre requisições = 100 req/min) durante
  `kubectl -n fcg rollout restart deployment/catalog-api` (rollout 03:08:53–03:09:19, `maxUnavailable: 0`,
  `maxSurge: 1`, 2 réplicas):

```
00:11:45  HTTP 200  X-App-Version ee2d0dd

requests: 194
  HTTP 200: 194
  version ee2d0dd: 194
RESULT: every request answered 200
```

As 32 requisições dentro da janela do rollout responderam 200.

### Smoke real pelo gateway público

`.\scripts\smoke-compose.ps1 -GatewayUrl http://fcg-demo-kwsfp.eastus2.cloudapp.azure.com -AdminPassword <Key Vault>
-PrometheusUrl http://localhost:19090 -LokiUrl http://localhost:13100` (Prometheus e Loki por `kubectl port-forward`):

```
== FCG smoke test (Docker Compose, through Kong at http://fcg-demo-kwsfp.eastus2.cloudapp.azure.com)
[0] Gateway
  PASS  GET /api/games without token -> 401 from Kong
[1] Register through Kong
  PASS  POST /api/auth/register -> 201 (smoke.20261122235608@fcg.com)
[2] Login through Kong
  PASS  POST /api/auth/login -> 200, JWT received
[3] GET /api/games twice (Redis cache)
  PASS  both calls 200
  PASS  X-FCG-Cache: first=MISS, second=HIT
        purchasing 'Pixel Racers' (49.90) id 9c6fc84c-6a6a-4ef4-8fc2-07d7040b400c
[5] Approved purchase
  PASS  POST /api/library/acquire -> 202, orderId 8a44f90d-f980-4479-9fcc-ca07f9fc2a66
[6] GET /api/payments/order/{orderId} (MongoDB payment history)
  PASS  payment status Approved (reason: Approved by the payment simulation.)
[8] GET /api/library/my-games
  PASS  library contains 'Pixel Racers' (X-FCG-Cache: MISS)
[9] Rejected purchase (price above the 1000 limit)
        created 'Smoke Expensive Game' (1500) as admin
  PASS  payment status Rejected for orderId 71045fdc-5d4d-4af1-b788-a25d63d87ba3
[12] Search (Elasticsearch) through Kong
  PASS  GET /api/games/search without token -> 401 from Kong
  PASS  exact 'Cosmic Odyssey' -> top hit 'Cosmic Odyssey' (score 30.92555, total 1)
  PASS  fuzzy 'Cosmik Odisey' -> top hit 'Cosmic Odyssey'
  PASS  unknown terms -> 200 with total 0
  PASS  q='a' -> 400 (validation)
  PASS  pageSize=500 -> 400 (validation)
  PASS  created 'Nebula Smoke 20261122235608' -> found right away by the misspelled 'Nebla Smoke 20261122235608'
  PASS  updated to 'Quasar Smoke 20261122235608' -> index returns the new title and price
  PASS  deleted game -> no longer returned by search
  PASS  POST /api/games/search/reindex (Admin) -> 200, indexed 6 games
  PASS  reindex as a regular user -> 403
[10] Prometheus targets (http://localhost:19090)
  PASS  7 targets up: kong, payments-api, users-api, users-api, catalog-api, catalog-api, prometheus
[11] Loki: Notifications Function logs (http://localhost:13100)
  PASS  [WELCOME EMAIL] for smoke.20261122235608@fcg.com: 1 line(s) in Loki
  PASS  [PURCHASE CONFIRMATION] for 8a44f90d-f980-4479-9fcc-ca07f9fc2a66: 1 line(s) in Loki

== SMOKE PASSED (0 failures)
```

### Elasticsearch gerenciado (Elastic Cloud 9.5.6)

- API key validada antes do uso (cabeçalho enviado por stdin, valor nunca exibido): `authentication_type=api_key`,
  privilégios `create_index`, `write`, `read`, `manage`, `view_index_metadata` no índice `fcg-games`.
- CatalogAPI no AKS (endpoint e API key lidos do Key Vault): `Search index fcg-games full load: 4 games indexed.` e
  reconciliações periódicas nos logs.
- `_cat/indices/fcg-games` ao final: `green open fcg-games 6 docs`.
- Busca exata, fuzzy (`Cosmik Odisey` → *Cosmic Odyssey*), sem resultados, validações 400, criação/edição/exclusão
  refletidas no índice e reindex (Admin 200, usuário 403): ver smoke acima.

### Redis — impacto medido

`bash scripts/measure-cache.sh <gateway> admin@fcg.com 30` (senha em `FCG_ADMIN_PASSWORD`, lida do Key Vault).

Pelo gateway público (estação no Brasil → `eastus2`; latência dominada pela rede):

```
outcome  n    min    median   mean     p95     max   (ms)
MISS     30   252.3    273.9    276.3   308.3   312.8
HIT      30   248.9    261.0    266.9   300.1   310.0
median MISS - HIT = 12.9 ms (4.7% of the MISS median)
```

Dentro do cluster (`http://kong:8000`, pod temporário `cache-probe`, removido após a medição):

```
outcome  n    min    median   mean     p95     max   (ms)
MISS     30     4.6      5.3      5.9     9.4     9.8
HIT      30     2.9      3.4      3.9     6.9     9.1
median MISS - HIT = 1.8 ms (34.7% of the MISS median)
```

Leitura: no servidor, o HIT reduz a mediana de 5,3 para 3,4 ms (−34,7 %) e o p95 de 9,4 para 6,9 ms; pela internet
o ganho absoluto (12,9 ms) fica pequeno diante dos ~250 ms de rede. Prometheus: `fcg_cache_requests_total`
hit=119, miss=66, bypass=0 após os testes.

### MongoDB — integração e persistência

- Smoke: compra aprovada → `GET /api/payments/order/{orderId}` = `Approved`; compra acima do limite = `Rejected`.
- Outro usuário consultando o mesmo `orderId` → **403**.
- Persistência: `kubectl -n fcg delete pod mongo-0` → pod recriado (UID `c04ff5d4…` → `e82a5d02…`) no mesmo PV
  `pvc-71a3f90f-e4d1-46fb-b98a-ab34ef6349cf`; o pagamento `8a44f90d-f980-4479-9fcc-ca07f9fc2a66` continuou
  retornando 200/`Approved` com os mesmos dados.

### Observabilidade

- Prometheus: 7 alvos `up` (kong, prometheus, payments-api, 2× users-api, 2× catalog-api), com rótulo `version`
  = SHA de cada réplica; métricas `fcg_search_requests_total`, `fcg_search_index_operations_total` e
  `fcg_cache_requests_total` coletadas.
- Grafana 12.1.0 (`/api/health` ok) com os dashboards **FCG Overview** e **FCG Logs** provisionados.
- Loki: logs `[WELCOME EMAIL]` e `[PURCHASE CONFIRMATION]` da Notifications Function encontrados por e-mail e
  `orderId` (smoke).

### Estado final do ambiente (2026-11-23 ~03:15 UTC)

16 pods no namespace `fcg` (15 em execução e prontos, Job de tópicos `Completed`; APIs com imagem do ACR por
SHA), 3 PVCs `Bound`, `kong-proxy` `LoadBalancer` `4.152.230.114`. Ambiente **mantido ativo** para a gravação do vídeo.
