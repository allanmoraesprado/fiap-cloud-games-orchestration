# Handoff — Fase 4

> Leia este arquivo primeiro ao retomar o trabalho em uma nova sessão.

## Estado consolidado

Ver [STATUS.md](STATUS.md). Resumo: M0 aprovado; M1 em execução; M5 bloqueado pela assinatura Azure.

## Workspace

- Raiz: `C:\Users\Allan\source\repos\FCG-Phase4` (pasta agregadora **sem** Git; arquivo `FCG-Phase4.code-workspace`).
- Cada repositório é uma subpasta com `.git` próprio, branch `main`, remoto `origin` (GitHub, públicos).

| Repositório | HEAD |
|---|---|
| orchestration | ver CHECKPOINTS (último CP) |
| users-api | `3681486` |
| catalog-api | `e3d03b3` |
| payments-api | `72bde0f` |
| notifications-function | `0e7e956` |

## Ambiente da estação

- .NET SDK 9/10 com runtime 8.0.20; Docker Desktop (iniciar antes de testes de integração/Compose);
  Azure CLI 2.87.0 logado no tenant `Diretório Padrão`.
- Ausentes: `terraform`, `gh`, `kubelogin`, `helm`, `trivy`. Para validação local foram usados binários
  portáteis baixados no diretório temporário da sessão (não versionados).

## Erros / bloqueios conhecidos

- **Assinatura Azure**: `state: Warned`; `az group list` → `SubscriptionNotFound`; ARM lista 0 assinaturas.
  Desbloqueio: proprietário reativar a assinatura (ou indicar outra) e refazer `az login`.

## Convenções

- Commits em inglês, sem referências a marcos/sessões; documentação de entrega em pt-BR.
- Não usar force-push; não reescrever histórico.
- Nenhum segredo real no Git; placeholders apenas para execução local.

## Tarefas elegíveis

1. P4-M1 — Elasticsearch no CatalogAPI (em execução).
2. P4-M2 — Terraform + manifests do AKS (validação local).
3. P4-M3 — Key Vault/Workload Identity (código + manifests).
4. P4-M4 — Workflows GitHub Actions (CI real no GitHub).

## Próximo passo exato

Implementar a busca no CatalogAPI conforme [PLAN.md](PLAN.md) §P4-M1 e [DECISIONS.md](DECISIONS.md) D03–D05.
