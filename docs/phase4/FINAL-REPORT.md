# Relatório de Entrega — Tech Challenge Fase 4 (FIAP Cloud Games)

> Campos **A PREENCHER** dependem de informações do proprietário ou de evidências ainda não produzidas.
> Nenhum link, número ou resultado é inventado; o estado de cada item está em [STATUS.md](STATUS.md).

## Identificação

| Campo | Valor |
|---|---|
| Grupo | **A PREENCHER** |
| Participante(s) | **A PREENCHER** |
| Usuário(s) Discord | **A PREENCHER** |
| Link do vídeo (até 25 min) | **A PREENCHER** |

## Repositórios

| Repositório | URL |
|---|---|
| Orquestração (documentação central) | https://github.com/allanmoraesprado/fiap-cloud-games-orchestration |
| UsersAPI | https://github.com/allanmoraesprado/fiap-cloud-games-users-api |
| CatalogAPI | https://github.com/allanmoraesprado/fiap-cloud-games-catalog-api |
| PaymentsAPI | https://github.com/allanmoraesprado/fiap-cloud-games-payments-api |
| Notifications Function | https://github.com/allanmoraesprado/fiap-cloud-games-notifications-function |
| NotificationsAPI (legado Fase 2) | https://github.com/allanmoraesprado/fiap-cloud-games-notifications-api |

## Ambiente de demonstração (Azure)

| Item | Valor |
|---|---|
| Gateway público (Kong) | http://fcg-demo-kwsfp.eastus2.cloudapp.azure.com |
| Região / resource groups | `eastus2` / `rg-fcg-demo`, `rg-fcg-demo-aks-nodes` |
| Cluster / registry / cofre | `aks-fcg-demo` (Kubernetes 1.36.5) / `acrfcgdemokwsfp` / `kv-fcg-demo-kwsfp` |
| Busca | Elastic Cloud 9.5.6, índice `fcg-games` |

## Documentação

Ponto de entrada: [README](../../README.md) do repositório de orquestração; guias em [docs/phase4/](.).

## O que foi entregue

| Tema | Entrega | Onde |
|---|---|---|
| Kubernetes gerenciado | AKS (Free tier, Workload Identity, Entra ID + Azure RBAC, CSI Key Vault) via Terraform | `infra/terraform`, [PROVISIONING.md](PROVISIONING.md) |
| Registry privado | ACR Basic sem admin/pull anônimo; push por OIDC, pull pelo kubelet | `acr.tf`, [CICD.md](CICD.md) |
| CI/CD | Workflow reutilizável: testes, Trivy, imagem por SHA, rolling update com rollback, smoke | `.github/workflows/dotnet-service.yml`, [CICD.md](CICD.md) |
| Busca avançada | Elasticsearch: fuzzy, relevância, paginação, validação, sincronização pós-commit + reconciliação + reindex, 503 em indisponibilidade | CatalogAPI, [ELASTICSEARCH.md](ELASTICSEARCH.md) |
| Persistência poliglota | PostgreSQL, MongoDB, Redis, Elasticsearch | [DATA.md](DATA.md) |
| Segredos | Key Vault RBAC, identidades por workload com acesso por segredo, arquivos montados, nada no Git/state/etcd | [KEYVAULT.md](KEYVAULT.md) |
| Observabilidade | Prometheus (descoberta de pods), Grafana, Loki + Alloy no AKS; painéis de busca | [OBSERVABILITY.md](OBSERVABILITY.md) |
| Custos | Estimativa por API de preços, orçamento com alertas, guia de destruição | [COSTS.md](COSTS.md), [DESTROY.md](DESTROY.md) |

## Requisitos × evidências

Matriz completa: [REQUIREMENTS.md](REQUIREMENTS.md). Evidências executadas: [TEST-EVIDENCE.md](TEST-EVIDENCE.md).
Checklist dos critérios finais: [CHECKLIST.md](CHECKLIST.md).

## Resultados validados na nuvem (2026-11-22/23)

| Critério | Resultado |
|---|---|
| Provisionamento | Terraform: 66 recursos (+3 atualizações); nenhum segredo no state |
| CI/CD | CI+CD reais nos 4 serviços; push na `main` da CatalogAPI → deploy automático (run 45103663258) |
| Rolling update | 194/194 requisições HTTP 200 durante o rollout (`maxUnavailable: 0`) |
| Smoke pelo gateway público | 0 falhas (fluxo de compra, cache, MongoDB, busca, Prometheus, Loki) |
| Elasticsearch | Elastic Cloud 9.5.6: exata, fuzzy (`Cosmik Odisey` → *Cosmic Odyssey*), validação, sincronização, reindex |
| Redis | MISS→HIT; dentro do cluster a mediana cai de 5,3 para 3,4 ms (−34,7 %) |
| MongoDB | Pagamentos aprovados/rejeitados; dados preservados após recriar o pod; 403 para outro usuário |
| Segredos | Key Vault + CSI + Workload Identity; 0 Secrets no Kubernetes; 0 segredos no GitHub (OIDC) |

Detalhes: [TEST-EVIDENCE.md](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks).

## Pendências conhecidas

- Dados do grupo, participante(s), Discord e link do vídeo (proprietário).
- Gravação do vídeo ([VIDEO-SCRIPT.md](VIDEO-SCRIPT.md)); depois, destruição confirmada do ambiente
  ([DESTROY.md](DESTROY.md)), incluindo o deployment do Elastic Cloud.
