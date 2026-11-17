# Handoff — Fase 4

> Leia este arquivo primeiro ao retomar o trabalho em uma nova sessão.

## Estado consolidado

Ver [STATUS.md](STATUS.md). Resumo: M0 aprovado; M1 aprovado localmente (Elastic Cloud pendente); M2 aprovado (declarativo); M3 implementado (validação real pendente); M4 em execução (CI real); M5 bloqueado pela assinatura Azure.

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
- Projeto Compose `fcg-p4` (smoke do M1): já removido (`down -v`).
- Ensaio do AKS: namespace `fcg-sim` (criado por mim; `bash scripts/azure/simulate-local.sh down` remove). Imagens locais `fcg-*:sim`.
- Ferramentas portáteis (não instaladas no sistema) no diretório temporário da sessão: terraform 1.17.2, kubeconform 0.8.0, actionlint 1.7.12.
- PowerShell 5.1: `PSCustomObject` único não tem `.Count` — sempre envolver resultados em `@()` nos scripts.

## Erros / bloqueios conhecidos

- **Assinatura Azure**: `state: Warned`; `az group list` → `SubscriptionNotFound`; ARM lista 0 assinaturas.
  Desbloqueio: proprietário reativar a assinatura (ou indicar outra) e refazer `az login`.

## Convenções

- Commits em inglês, sem referências a marcos/sessões; documentação de entrega em pt-BR.
- Não usar force-push; não reescrever histórico.
- Nenhum segredo real no Git; placeholders apenas para execução local.

## Tarefas elegíveis

1. P4-M4 — acompanhar o CI real no GitHub (API pública: `https://api.github.com/repos/allanmoraesprado/<repo>/actions/runs`).
2. P4-M7 — documentação (README central, roteiro do vídeo) com o que já está validado.
3. Quando a assinatura for liberada: `scripts/azure/preflight.sh` → PROVISIONING.md.

## Próximo passo exato

Verificar o resultado dos workflows de CI recém-publicados e corrigir falhas; depois avançar documentação (M7).
