# Handoff — Fase 4

> Leia este arquivo primeiro ao retomar o trabalho em uma nova sessão.

## Estado consolidado

Ver [STATUS.md](STATUS.md). Resumo: M0 aprovado; M1 aprovado localmente (Elastic Cloud pendente); M2 em execução; M5 bloqueado pela assinatura Azure.

## Workspace

- Raiz: `C:\Users\Allan\source\repos\FCG-Phase4` (pasta agregadora **sem** Git; arquivo `FCG-Phase4.code-workspace`).
- Cada repositório é uma subpasta com `.git` próprio, branch `main`, remoto `origin` (GitHub, públicos).

| Repositório | HEAD |
|---|---|
| orchestration | ver CHECKPOINTS (último CP) |
| users-api | `3681486` |
| catalog-api | `b2a66b5` |
| payments-api | `72bde0f` |
| notifications-function | `0e7e956` |

## Ambiente da estação

- .NET SDK 9/10 com runtime 8.0.20; Docker Desktop (iniciar antes de testes de integração/Compose);
  Azure CLI 2.87.0 logado no tenant `Diretório Padrão`.
- Ausentes: `terraform`, `gh`, `kubelogin`, `helm`, `trivy`. Para validação local foram usados binários
  portáteis baixados no diretório temporário da sessão (não versionados).

## Ambientes locais em execução na estação

- Pré-existentes (não criados nesta fase, não alterar): projeto Compose `fcg-orchestration` (portas 5433/6380/27018…),
  namespace `fcg` no Kubernetes do Docker Desktop, containers `lurkly-*` de outro projeto.
- Criado para smoke da Fase 4: projeto Compose `fcg-p4` (portas 18000/18082/19090/19200…, env file no diretório
  temporário da sessão). Remover com `docker compose -p fcg-p4 down -v` quando não for mais necessário.
- PowerShell 5.1: `PSCustomObject` único não tem `.Count` — sempre envolver resultados em `@()` nos scripts.

## Erros / bloqueios conhecidos

- **Assinatura Azure**: `state: Warned`; `az group list` → `SubscriptionNotFound`; ARM lista 0 assinaturas.
  Desbloqueio: proprietário reativar a assinatura (ou indicar outra) e refazer `az login`.

## Convenções

- Commits em inglês, sem referências a marcos/sessões; documentação de entrega em pt-BR.
- Não usar force-push; não reescrever histórico.
- Nenhum segredo real no Git; placeholders apenas para execução local.

## Tarefas elegíveis

1. P4-M2 — Terraform + manifests do AKS (validação local).
3. P4-M3 — Key Vault/Workload Identity (código + manifests).
4. P4-M4 — Workflows GitHub Actions (CI real no GitHub).

## Próximo passo exato

Criar `infra/terraform` (Azure) e manifests do AKS conforme [PLAN.md](PLAN.md) §P4-M2 e [DECISIONS.md](DECISIONS.md) D06–D15.
