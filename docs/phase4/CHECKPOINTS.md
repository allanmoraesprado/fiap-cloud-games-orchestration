# Checkpoints — Fase 4

## CP-01 — 2026-11-17 — P4-M0 Auditoria inicial e planejamento

- **Objetivo**: compreender o estado real da Fase 3 e planejar a Fase 4.
- **Status**: APROVADO.
- **Alterações**: criação de `docs/phase4/` (PLAN, STATUS, REQUIREMENTS, DEPENDENCIES, ARCHITECTURE, COSTS,
  DECISIONS, RISKS, TEST-EVIDENCE, CHECKPOINTS, HANDOFF, FINAL-REPORT).
- **Repositórios afetados**: `fiap-cloud-games-orchestration`.
- **HEADs auditados**: orchestration `a069dde`, users-api `3681486`, catalog-api `e3d03b3`,
  payments-api `72bde0f`, notifications-function `0e7e956`.
- **Comandos executados**: `git status/log/fetch` em todos os repositórios; `dotnet test` nos 4 serviços;
  `az account show`, `az account list --all`, `az group list`, `az rest GET /subscriptions` (somente leitura);
  consulta à API pública de preços da Azure; consulta de versões no NuGet e Docker Hub.
- **Testes aprovados**: 71/71 (21 + 22 + 15 + 13).
- **Testes reprovados**: nenhum.
- **Smoke tests**: não aplicável (nenhuma alteração de código).
- **Evidências**: [TEST-EVIDENCE.md](TEST-EVIDENCE.md).
- **Pendências**: assinatura Azure inutilizável (K01); Terraform/gh/kubelogin ausentes na estação.
- **Próxima ação**: P4-M1 (Elasticsearch no CatalogAPI).

## CP-02 — 2026-11-17 — P4-M1 Elasticsearch e busca avançada

- **Objetivo**: busca textual independente do relacional, fuzzy, relevância, sincronização do índice.
- **Status**: APROVADO (critério local); validação no Elastic Cloud PENDENTE (M6).
- **Alterações**:
  - catalog-api: endpoint `GET /api/games/search`, `POST /api/games/search/reindex`, indexador com
    mapeamento explícito, serviço de consulta, `GameSearchSync`, `SearchIndexReconciler`, 503 com
    `Retry-After`, métricas, `ListUpdatedSinceAsync`, configuração `Elasticsearch:*`, 48 testes novos
    (32 unitários + 16 integração), README.
  - orchestration: serviço `elasticsearch` no Compose, variáveis da CatalogAPI, `ELASTICSEARCH_HOST_PORT`,
    `k8s/elasticsearch.yaml` + `apply-all`, smoke com busca e queda/recuperação, `docs/phase4/ELASTICSEARCH.md`.
- **Commits**: catalog-api `b2a66b5`; orchestration (este checkpoint).
- **Comandos**: `dotnet test` (70/70), `docker compose -p fcg-p4 up -d --build`, `smoke-compose.ps1 -SearchOutage`,
  `kubectl apply --dry-run=server` (manifests locais do ES/configmap).
- **Testes reprovados**: nenhum (1ª execução do smoke: falso negativo do script, corrigido).
- **Pendências**: Elastic Cloud (depende de conta do proprietário); painel de busca no Grafana (M6/M7).
- **Ambiente local**: stack `fcg-p4` criada para o smoke (removida ao final do marco; ver HANDOFF).
- **Próxima ação**: P4-M2 (Terraform + manifests do AKS).

## CP-03 — 2026-11-17 — P4-M2, P4-M3 e P4-M4 (preparação local)

- **Objetivo**: infraestrutura declarativa, segurança (Key Vault/Workload Identity) e pipelines prontos e
  validados sem a assinatura Azure.
- **Status**: M2 APROVADO (critério: declarativo + validado; provisionamento no M5); M3 PENDENTE (código e
  manifests validados localmente, validação real no AKS); M4 EM EXECUÇÃO (workflows prontos; CI real a seguir).
- **Alterações**:
  - orchestration: `infra/terraform` (RG, VNet, AKS, ACR, Key Vault, identidades, OIDC GitHub, budget, outputs),
    `k8s/azure` (plataforma), `observability/*-aks*`, `scripts/azure/*` (preflight, deploy, render, ensaio,
    validação, variáveis GitHub, destruição), `scripts/ci/smoke-service.sh`, workflows `dotnet-service.yml` e
    `ci.yml`, guias PROVISIONING, DESTROY, CICD, KEYVAULT.
  - users-api / catalog-api / payments-api: `RuntimeConfiguration` (KeyPerFile + `X-App-Version`), seed do admin
    configurável (users), Dockerfile (`APP_VERSION`, labels OCI, `USER $APP_UID`), `k8s/azure`, `ci-cd.yml`, testes.
  - notifications-function: Dockerfile (`APP_VERSION`, labels), `k8s/azure`, `ci-cd.yml`.
- **Testes**: 134/134; terraform validate OK; kubeconform 55/55; actionlint OK; ensaio local com smoke 0 falhas e
  rolling update 219/219 HTTP 200.
- **Bloqueios**: K01 (assinatura Azure).
- **Próxima ação**: commit/push; observar o CI real no GitHub; corrigir o que falhar.

## CP-04 — 2026-11-17 — CI real, correções e documentação de entrega

- **Status**: M4 — CI executado de verdade no GitHub (3 serviços aprovados de primeira; 2 falhas analisadas e
  corrigidas); CD real PENDENTE (M5). M7 — documentação central em pt-BR redigida (atualizar com evidências de nuvem).
- **Alterações**: notifications-function `6c1198f` (imagem base corrigida); orchestration: diretiva shellcheck no
  workflow, papel `Reader` no ACR para a identidade de deploy (`az acr login` precisa de `registries/read`),
  painéis de busca no dashboard FCG Overview, `scripts/measure-cache.sh`, README central pt-BR (README da Fase 3
  preservado em `docs/README-phase3.md`), guias DATA, OBSERVABILITY, VIDEO-SCRIPT, CHECKLIST, FINAL-REPORT.
- **Evidências**: runs do GitHub Actions e medição local do cache em [TEST-EVIDENCE.md](TEST-EVIDENCE.md).
- **Próxima ação**: confirmar o novo CI (function + orchestration) verde.
