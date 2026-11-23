# Handoff — Fase 4

> Leia este arquivo primeiro ao retomar o trabalho em uma nova sessão.

## Estado consolidado

Ver [STATUS.md](STATUS.md). Resumo (2026-11-23): M0–M6 **APROVADOS** com evidências reais na Azure; M7 em execução
(faltam dados do grupo, gravação e link do vídeo). **O ambiente Azure está ativo e gerando custo**
(≈ US$ 5,7/dia) — mantido para a gravação.

## Workspace

- Raiz: `C:\Users\Allan\source\repos\FCG-Phase4` (pasta agregadora **sem** Git; arquivo `FCG-Phase4.code-workspace`).
- Cada repositório é uma subpasta com `.git` próprio, branch `main`, remoto `origin` (GitHub, públicos).
- HEADs: ver o último checkpoint em [CHECKPOINTS.md](CHECKPOINTS.md).

## Ambiente Azure ativo

| Item | Valor |
|---|---|
| Assinatura | `FCG-Phase4` (pay-as-you-go, `Enabled`); operador Owner |
| Gateway | `http://fcg-demo-kwsfp.eastus2.cloudapp.azure.com` (IP `4.152.230.114`) |
| Recursos | `rg-fcg-demo` (AKS `aks-fcg-demo`, ACR `acrfcgdemokwsfp`, Key Vault `kv-fcg-demo-kwsfp`, identidades), `rg-fcg-demo-aks-nodes` |
| Terraform | state **local** em `infra/terraform/terraform.tfstate` (fora do Git; sem segredos — `value_wo`); `terraform.tfvars` local com o endpoint do Elastic Cloud |
| Elastic Cloud | deployment 9.5.6; API key do proprietário em arquivo local fora dos repositórios (lida só no comando do `terraform apply`) |
| GitHub | `gh` autenticado; variáveis de CD aplicadas nos 4 serviços (`AZURE_DEPLOY_ENABLED=true`) |
| kubectl | `export KUBECONFIG="$HOME/.kube/fcg-aks-demo"` (kubeconfig separado; o contexto `docker-desktop` não foi alterado) |

Atenção: com `AZURE_DEPLOY_ENABLED=true`, **todo push na `main` de um serviço faz deploy no AKS**.
`bash scripts/azure/github-variables.sh --disable` desliga o CD.

## Ambiente da estação

- Instalados via winget nesta fase: GitHub CLI 2.105, Terraform 1.17.2, kubelogin 0.2.22 (abrir terminal novo para o PATH).
- Ferramentas portáteis de validação (kubeconform, actionlint, shellcheck) no diretório temporário da sessão.
- Pré-existentes (não alterar): projeto Compose `fcg-orchestration` (Fase 3), namespace `fcg` no Kubernetes do
  Docker Desktop, containers `lurkly-*`.
- PowerShell 5.1: `PSCustomObject` único não tem `.Count` — envolver em `@()`. Git Bash: caminhos iniciados por `/`
  são convertidos (ver PROVISIONING §5).

## Convenções

- Commits em inglês, sem referências a marcos/sessões; documentação de entrega em pt-BR.
- Não usar force-push; não reescrever histórico.
- Nenhum segredo real no Git; placeholders apenas para execução local.

## Próximos passos

1. Proprietário: preencher grupo/participantes/Discord no [FINAL-REPORT.md](FINAL-REPORT.md).
2. Gravar o vídeo seguindo [VIDEO-SCRIPT.md](VIDEO-SCRIPT.md); registrar o link no FINAL-REPORT.
3. Opcional para economizar entre sessões de gravação: `az aks stop -g rg-fcg-demo -n aks-fcg-demo` / `az aks start ...`.
4. Após a gravação e **somente com confirmação do proprietário**: [DESTROY.md](DESTROY.md) (inclui Elastic Cloud e
   `github-variables.sh --disable`).
