# Status da Fase 4

Última atualização: 2026-11-23 (ambiente Azure provisionado, validado e **mantido ativo** para o vídeo)

| Marco | Status | Dependências | Testes | Commit | Observações |
|---|---|---|---|---|---|
| P4-M0 | APROVADO | — | baseline 71/71 | orchestration (ver CHECKPOINTS) | Auditoria, plano, matriz, custos, riscos |
| P4-M1 | APROVADO | M0 | 70/70 (54 unit + 16 integração ES real); smoke Compose 0 falhas; **smoke na nuvem 0 falhas com Elastic Cloud 9.5.6** | catalog-api `b2a66b5`, `47b920a` | Busca, fuzzy, relevância, sincronização, reindexação; índice `fcg-games` green no Elastic Cloud |
| P4-M2 | APROVADO | M0 | terraform validate; kubeconform 55/55; **apply real: 66 recursos (+3 atualizações)** | orchestration `fd52e0a` | AKS, ACR, Key Vault, identidades, rede, orçamento provisionados em `eastus2` |
| P4-M3 | APROVADO | M0, M2 | CSI montado em 8 workloads; 0 `Secret` k8s; identidades com acesso por segredo; 0 segredos no GitHub | orchestration `fd52e0a` | Key Vault + Workload Identity + OIDC validados no AKS real |
| P4-M4 | APROVADO | M0, M2/M3 | CI+CD reais nos 4 serviços; **push → deploy automático** (run 45103663258); rollout sob carga 194/194 HTTP 200 | orchestration `cfe202a`; catalog-api `ee2d0dd` | kubelogin fixado (`v0.2.22`); rastreabilidade SHA → imagem → pod → `X-App-Version` |
| P4-M5 | APROVADO | M2, M3, M4 | preflight OK; apply; plataforma; variáveis do GitHub; CD dos 4 serviços | orchestration `fd52e0a`, `cfe202a` | Gateway público `http://fcg-demo-kwsfp.eastus2.cloudapp.azure.com`; nó `Standard_D4as_v6` (D23) |
| P4-M6 | APROVADO | M1, M5, CD operacional | smoke real 0 falhas; Redis MISS/HIT medido (nuvem e in-cluster); MongoDB persistente após recriar o pod; Prometheus/Grafana/Loki | orchestration (CP-06) | Evidências em [TEST-EVIDENCE.md](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks) |
| P4-M7 | EM EXECUÇÃO | Evidências dos marcos anteriores | — | orchestration (CP-06) | Documentação e roteiro do vídeo atualizados com o ambiente real. **Faltam**: dados do grupo/Discord, gravação e link do vídeo; depois, destruição (DESTROY.md) |

## Ambiente ativo (custo em andamento)

| Item | Valor |
|---|---|
| Gateway público | `http://fcg-demo-kwsfp.eastus2.cloudapp.azure.com` (IP `4.152.230.114`) |
| Resource groups | `rg-fcg-demo`, `rg-fcg-demo-aks-nodes` (`eastus2`) |
| AKS / ACR / Key Vault | `aks-fcg-demo` / `acrfcgdemokwsfp` / `kv-fcg-demo-kwsfp` |
| Elastic Cloud | deployment 9.5.6 (`eastus2`), índice `fcg-games` |
| Custo estimado | ≈ US$ 5,7/dia ligado (COSTS.md, D23); `az aks stop` reduz para ≈ US$ 1,4/dia |

## Bloqueios ativos

Nenhum bloqueio técnico. Pendências do proprietário: dados do relatório (grupo, participantes, Discord), gravação
do vídeo e, depois, a destruição confirmada do ambiente ([DESTROY.md](DESTROY.md)), incluindo o Elastic Cloud.
