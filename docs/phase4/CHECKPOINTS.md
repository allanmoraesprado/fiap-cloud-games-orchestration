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
