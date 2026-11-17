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
| users-api | `6d76552` |
| catalog-api | `47b920a` |
| payments-api | `3cd02a0` |
| notifications-function | `6c1198f` |

## Ambiente da estação

- .NET SDK 9/10 com runtime 8.0.20; Docker Desktop (iniciar antes de testes de integração/Compose);
  Azure CLI 2.87.0 logado no tenant `Diretório Padrão`.
- Ausentes: `terraform`, `gh`, `kubelogin`, `helm`, `trivy`. Para validação local foram usados binários
  portáteis baixados no diretório temporário da sessão (não versionados).

## Ambientes locais em execução na estação

- Pré-existentes (não criados nesta fase, não alterar): projeto Compose `fcg-orchestration` (portas 5433/6380/27018…),
  namespace `fcg` no Kubernetes do Docker Desktop, containers `lurkly-*` de outro projeto.
- Projeto Compose `fcg-p4` (smoke do M1): já removido (`down -v`).
- Ensaio do AKS (`fcg-sim`): removido ao fim da sessão; recriar com `bash scripts/azure/simulate-local.sh up --apps` (antes, construir as imagens `fcg-<serviço>:sim`).
- Ferramentas portáteis (não instaladas no sistema) no diretório temporário da sessão: terraform 1.17.2, kubeconform 0.8.0, actionlint 1.7.12.
- PowerShell 5.1: `PSCustomObject` único não tem `.Count` — sempre envolver resultados em `@()` nos scripts.

## Erros / bloqueios conhecidos

- **Assinatura Azure**: `state: Warned`; `az group list` → `SubscriptionNotFound`; ARM lista 0 assinaturas.
  Desbloqueio: proprietário reativar a assinatura (ou indicar outra) e refazer `az login`.
  Reverificado no fim da sessão: `az account list --all --refresh` não encontrou assinatura acessível e o CLI
  passou a exigir `az login` (sessão local sem contas).

## Convenções

- Commits em inglês, sem referências a marcos/sessões; documentação de entrega em pt-BR.
- Não usar force-push; não reescrever histórico.
- Nenhum segredo real no Git; placeholders apenas para execução local.

## Tarefas elegíveis

Todo o trabalho executável sem Azure está concluído (M0, M1 local, M2, M3/M4 até o limite local, M7 redigido).
Restante depende de ações do proprietário:

1. Reativar a assinatura Azure (estado `Warned`) e fazer `az login`; autorizar o custo de [COSTS.md](COSTS.md).
2. Criar a conta/deployment no Elastic Cloud e a API key.
3. Seguir [PROVISIONING.md](PROVISIONING.md): preflight → terraform apply → deploy-platform → github-variables (requer `gh auth login` ou configuração manual).
4. M5/M6: push na `main` dos serviços (CD real), smoke no gateway público, `measure-cache.sh` na nuvem, evidências.
5. M7: dados do grupo/Discord/vídeo no FINAL-REPORT; gravação seguindo VIDEO-SCRIPT; depois DESTROY.

## Próximo passo exato

Aguardar o desbloqueio da assinatura Azure; então executar `bash scripts/azure/preflight.sh <subscription-id>`.
