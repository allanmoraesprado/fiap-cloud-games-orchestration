# Guia de CI/CD — GitHub Actions → ACR → AKS

## Estrutura

| Repositório | Workflow | Papel |
|---|---|---|
| orchestration | `.github/workflows/dotnet-service.yml` | **Workflow reutilizável** (`workflow_call`) com os jobs `ci` e `cd` |
| orchestration | `.github/workflows/ci.yml` | Valida Terraform (`fmt`/`validate`), manifests do AKS (kubeconform, incluindo os `k8s/azure` dos serviços), Compose, scripts (shellcheck) e workflows (actionlint) |
| users-api, catalog-api, payments-api, notifications-function | `.github/workflows/ci-cd.yml` | Chamador fino: `uses: allanmoraesprado/fiap-cloud-games-orchestration/.github/workflows/dotnet-service.yml@main` |

## Etapas

| # | Etapa | Job | Detalhe |
|---|---|---|---|
| 1 | Checkout | ci | `actions/checkout` |
| 2 | Setup .NET | ci | 8.0.x |
| 3 | Restore | ci | `dotnet restore` |
| 4 | Build | ci | `--configuration Release` |
| 5 | Testes | ci | unitários + integração (Testcontainers/Elasticsearch no CatalogAPI); resultados `.trx` como artefato |
| 6 | Build Docker | ci | `--build-arg APP_VERSION=<sha>` |
| 7 | Tag = SHA | ci | `fcg-<serviço>:<sha completo>`; **nenhuma tag `latest`** |
| 8 | Security scan | ci | `dotnet list package --vulnerable` (relatório) + **Trivy** (relatório CRITICAL/HIGH; **falha** em CRITICAL com correção disponível) |
| — | Handoff | ci | a imagem escaneada é salva (`docker save`) e passada ao CD como artefato — **a mesma imagem é publicada** |
| 9 | Login Azure via OIDC | cd | `azure/login` com `client-id`/`tenant-id`/`subscription-id` (variáveis, sem segredo) |
| 10 | Push para o ACR | cd | `az acr login` + `docker push <acr>.azurecr.io/<imagem>:<sha>` |
| 11 | Deploy no AKS | cd | `kubelogin` (Entra ID) + `envsubst` dos `k8s/azure/*.yaml` + `kubectl apply` |
| 12 | Rolling Update | cd | `maxUnavailable: 0`, `maxSurge: 1`, readiness probe, `preStop` de 5 s |
| 13 | Verificação do rollout | cd | `kubectl rollout status` (300 s); falha ⇒ `kubectl rollout undo` automático |
| 14 | Smoke pós-deploy | cd | `scripts/ci/smoke-service.sh` pelo Kong público: 401 sem token, registro/login, endpoint do serviço e **`X-App-Version` = SHA** |

Actions de terceiros fixadas por SHA de commit (comentário com a tag).

## Segurança do pipeline

- **CI e CD separados**: `cd` depende de `ci` e só roda em `refs/heads/main` com evento `push` ou
  `workflow_dispatch`, e somente se a variável `AZURE_DEPLOY_ENABLED == 'true'`.
- **Pull requests nunca implantam**: o job `cd` é ignorado e, além disso, a credencial federada no Azure
  confia apenas no sujeito `repo:<owner>/<repo>:ref:refs/heads/main` — um PR (`…:pull_request`) não obtém token.
- Permissões mínimas: `ci` só `contents: read`; `cd` acrescenta `id-token: write`. A identidade de deploy
  tem `AcrPush`, `AKS Cluster User Role` e `AKS RBAC Writer` **somente no namespace `fcg`**
  (não cria Roles, não altera a plataforma).
- `concurrency: deploy-<serviço>` evita deploys simultâneos do mesmo serviço.

## Rastreabilidade commit → imagem → pod

| Onde | Como |
|---|---|
| Imagem | tag = SHA; label OCI `org.opencontainers.image.revision` = SHA |
| Deployment | label `app.kubernetes.io/version` = SHA; anotação `kubernetes.io/change-cause` = `<repo>@<sha> run <id>` (`kubectl rollout history`) |
| Prometheus | rótulo `version` em cada série (pod discovery) |
| Resposta HTTP | cabeçalho `X-App-Version: <sha>` (UsersAPI, CatalogAPI, PaymentsAPI) |
| Run | resumo do job (`$GITHUB_STEP_SUMMARY`) com commit e imagem |

## Variáveis de repositório (Settings → Secrets and variables → Actions → Variables)

`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `ACR_NAME`, `AKS_NAME`, `AKS_RESOURCE_GROUP`,
`GATEWAY_URL`, `AZURE_DEPLOY_ENABLED`. Geradas a partir do Terraform por `bash scripts/azure/github-variables.sh`.
Nenhum *secret* do GitHub é necessário.

## Demonstração do live deploy (roteiro)

1. Alterar algo controlado na CatalogAPI (ex.: uma linha do README ou uma mensagem de log): qualquer commit gera
   uma imagem nova com o SHA, visível no `X-App-Version`.
2. `git commit` + `git push origin main`.
3. Acompanhar o run em *Actions*: CI (testes, Trivy) → CD (OIDC, push, rollout, smoke).
4. Durante o rollout: `kubectl -n fcg get pods -l app=catalog-api -w` e
   `PACE_SECONDS=1 bash scripts/rolling-probe.sh $GW 600` (200 contínuo e troca do `X-App-Version`; abaixo do
   rate limit do Kong de 120 req/min por IP).
5. `az acr repository show-tags -n <acr> --repository fcg-catalog-api` e `kubectl -n fcg rollout history deploy/catalog-api`.

## Lições da primeira execução real (2026-11-22)

- `azure/use-kubelogin` com `kubelogin-version: latest` consulta a API do GitHub e falha sem `GITHUB_TOKEN`:
  versão fixada (`v0.2.22`).
- Repositórios GitHub recentes usam *immutable subject claims* no token OIDC
  (`repo:<owner>@<id>/<repo>@<id>:ref:refs/heads/main`): o prefixo é configurado por repositório em
  `github_oidc_subject_prefixes` (D24). Conferir com
  `gh api repos/<owner>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix`.
- No primeiro deploy, a UsersAPI deve subir antes das demais: o smoke de cada serviço registra e autentica um
  usuário pelo gateway.
- Sondas de disponibilidade precisam respeitar o rate limit do Kong (120 req/min por IP); acima disso as
  respostas 429 mascaram o resultado do rollout.

Execuções reais e análise: [TEST-EVIDENCE.md](TEST-EVIDENCE.md#cicd-real-github-actions--acr--aks).
