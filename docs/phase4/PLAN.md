# Plano de Implementação — Fase 4 (Cloud-Native na Azure)

> Documento vivo. Status consolidado em [STATUS.md](STATUS.md); decisões em [DECISIONS.md](DECISIONS.md);
> matriz de requisitos em [REQUIREMENTS.md](REQUIREMENTS.md); dependências em [DEPENDENCIES.md](DEPENDENCIES.md).

## 1. Objetivo

Evoluir a plataforma FIAP Cloud Games (Fase 3: microsserviços .NET 8 + Kafka + Kong + Redis + MongoDB +
Azure Functions + Prometheus/Grafana + Loki/Alloy, executando em Docker Compose e Kubernetes local) para uma
solução **Cloud-Native na Microsoft Azure**, com:

- AKS + ACR privado + Azure Key Vault provisionados por **Terraform**;
- **CI/CD** em GitHub Actions com autenticação **OIDC** e deploy com **Rolling Update** no AKS;
- **Busca avançada** com Elasticsearch (local em desenvolvimento, **Elastic Cloud** na nuvem);
- **Persistência poliglota** (PostgreSQL, MongoDB, Redis, Elasticsearch);
- **Gerenciamento seguro de credenciais** (Key Vault + AKS Workload Identity + Secrets Store CSI Driver).

## 2. Estratégia geral

1. **Local primeiro**: tudo que não depende de assinatura Azure é implementado e validado localmente
   (Elasticsearch, Terraform `validate`, manifests renderizados, workflows de CI executados de verdade no GitHub).
2. **Infraestrutura preparada, não provisionada**: nenhum recurso pago é criado antes de (a) assinatura
   utilizável, (b) orçamento estimado ([COSTS.md](COSTS.md)) e (c) autorização explícita do proprietário.
3. **Ambiente temporário**: um único Resource Group, um nó AKS, serviços de dados no cluster com PVC,
   destruição documentada e controlada pelo proprietário.
4. **Ciclo por marco**: ANÁLISE → PLANO → IMPLEMENTAÇÃO → BUILD/TESTES → SMOKE REAL → CORREÇÃO →
   CHECKPOINT → COMMIT/PUSH → PRÓXIMO MARCO.

## 3. Marcos, tarefas e critérios de aprovação

### P4-M0 — Auditoria inicial e planejamento
| Tarefa | Status |
|---|---|
| Auditar os 5 repositórios (branches, HEADs, testes, configs) | APROVADO |
| Inventário da arquitetura atual ([ARCHITECTURE.md](ARCHITECTURE.md)) | APROVADO |
| Identificar credenciais de desenvolvimento e configurações inadequadas para produção | APROVADO |
| Matriz de requisitos, dependências, riscos, custos | APROVADO |
| Executar build e testes de baseline | APROVADO (71/71) |
| Verificar acesso Azure | BLOQUEIO identificado (assinatura `Warned`) |

**Critério**: todos os requisitos mapeados para implementação, teste e evidência.

### P4-M1 — Elasticsearch e busca avançada (CatalogAPI)
Tarefas:
1. Adicionar `Elastic.Clients.Elasticsearch` 9.5.x; configuração `Elasticsearch:*` (URL, API key opcional, índice, habilitado).
2. Abstrações `IGameSearchService` (consulta) e `IGameSearchIndexer` (escrita), implementação Elasticsearch e no-op.
3. Índice `fcg-games` com mapeamento explícito (analisador com `asciifolding`, `title.keyword`, `genre.keyword`).
4. `GET /api/games/search?q=&genre=&page=&pageSize=`: `multi_match` com `fuzziness: AUTO` + boost de frase exata,
   filtro `isActive`, ordenação por `_score`, paginação; validação → 400; indisponibilidade → 503 + `Retry-After`.
5. Sincronização: indexação após commit em create/update/delete (best-effort), **reconciliação periódica**
   por marca d'água `UpdatedAt` (recupera falhas e faz a indexação inicial), reindexação completa sob demanda
   (`POST /api/games/search/reindex`, Admin).
6. Métricas Prometheus de busca/indexação; logs estruturados.
7. Testes unitários (validação, sincronização, fallback) + **testes de integração com Elasticsearch real**
   (Testcontainers): busca exata, erro de digitação, relevância, nenhum resultado, criação→indexação,
   edição→atualização, reindexação, indisponibilidade.
8. Elasticsearch no Docker Compose (single-node, 9.5.x) e smoke test real através do Kong.

**Critério**: busca, indexação e atualização funcionando com testes de integração e smoke reais.

### P4-M2 — Infraestrutura Azure (Terraform)
Tarefas: módulo `infra/terraform` (RG, VNet/subnet, AKS com OIDC issuer + Workload Identity + CSI Key Vault
add-on + Entra ID/Azure RBAC, ACR Basic sem admin, Key Vault RBAC, identidades gerenciadas por workload com
credenciais federadas, identidade de deploy do GitHub (OIDC), role assignments mínimos, orçamento com alerta,
tags), `environments/demo.tfvars.example`, scripts de criação/validação/destruição, manifests de plataforma
para AKS (dados com PVC, Kong LoadBalancer, observabilidade).

**Critério**: `terraform fmt -check`, `terraform validate` e renderização dos manifests aprovados localmente;
provisionamento real confirmado no P4-M5.

### P4-M3 — Segurança, identidades e Key Vault
Tarefas: segredos no Key Vault gerados pelo Terraform (`random_password`) ou informados pelo proprietário
(API key do Elastic Cloud); `SecretProviderClass` por workload; .NET lê segredos montados via
`KeyPerFile`; Postgres/Mongo/Grafana via `*_FILE`; Kong com `kong.yml` renderizado no init container a partir do
segredo montado; seed de usuários com senha configurável; remoção de segredos fixos dos manifests de produção.

**Critério**: integração implementada e validada localmente (abstrações/renderização) e, após o M5, segredos
efetivamente recuperados em runtime no AKS.

### P4-M4 — GitHub Actions (CI/CD)
Tarefas: workflows reutilizáveis no repositório de orquestração (`dotnet-service-ci`, `dotnet-service-cd`),
chamadores em cada serviço; CI em PR/push (restore, build, testes, build Docker, Trivy); CD apenas em push na
`main` e habilitado por variável (`AZURE_DEPLOY_ENABLED`), login OIDC, push no ACR com tag = SHA, deploy com
`envsubst` + `kubectl apply`, `rollout status`, smoke pós-deploy pelo Kong.

**Critério**: CI executado de verdade no GitHub (logs); CD aprovado somente após execução real no AKS.

### P4-M5 — Provisionamento real (ativa custos)
Pré-requisitos: assinatura utilizável, autorização de custo, conta Elastic Cloud, variáveis do GitHub.
Tarefas: `terraform apply`, deploy da plataforma, segredos, deploy das aplicações via pipeline, smoke real.

### P4-M6 — Validação final na nuvem
CI/CD com alteração controlada; Elasticsearch gerenciado; Redis (MISS/HIT/invalidação/latência medida);
MongoDB; segurança; observabilidade.

### P4-M7 — Documentação e entrega
README central, guias, evidências, checklist, relatório final, roteiro do vídeo (≤ 25 min).

## 4. Sequência de execução

```
M0 ──► M1 (local, independente de Azure) ──┐
   ├─► M2 (Terraform + manifests, local) ───┼─► M5 (BLOQUEADO: assinatura/custo) ─► M6 ─► M7
   ├─► M3 (código + manifests, local) ──────┤
   └─► M4 (CI real no GitHub; CD preparado) ┘
```

Trabalho elegível imediatamente (sem Azure): M1 completo; M2/M3/M4 até a validação local; CI real no GitHub.

## 5. Ferramentas necessárias

| Ferramenta | Situação na estação | Uso |
|---|---|---|
| .NET SDK 8+ (runtime 8) | instalado (SDK 9/10, runtime 8.0.20) | build/testes |
| Docker Desktop | instalado | Compose, Testcontainers, imagens |
| Azure CLI | 2.87.0, logado | provisionamento |
| Terraform ≥ 1.9 | **ausente** — binário portátil usado para validação; proprietário: `winget install Hashicorp.Terraform` | IaC |
| kubelogin | **ausente** — `az aks install-cli` no momento do M5 | AKS com Entra ID |
| GitHub CLI | **ausente** — necessário para configurar variáveis/secrets dos repositórios | CD |
| actionlint | binário portátil para validação de workflows | M4 |
