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

## Pendências conhecidas

- Assinatura Azure em estado `Warned` (inacessível) — provisionamento real, CD real e validações na nuvem
  aguardam a liberação e a autorização de custo ([RISKS.md](RISKS.md) K01).
- Conta/deployment no Elastic Cloud (cadastro do proprietário).
