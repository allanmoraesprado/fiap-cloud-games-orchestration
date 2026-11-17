# Status da Fase 4

Última atualização: 2026-11-17

| Marco | Status | Dependências | Testes | Commit | Observações |
|---|---|---|---|---|---|
| P4-M0 | APROVADO | — | baseline 71/71 | orchestration (ver CHECKPOINTS) | Auditoria, plano, matriz, custos, riscos. Bloqueio Azure identificado (K01) |
| P4-M1 | APROVADO (local) | M0 | 70/70 (54 unit + 16 integração ES real); smoke Compose 0 falhas | catalog-api `b2a66b5`; orchestration (CP-02) | Busca, fuzzy, relevância, sincronização, reindexação e queda/recuperação validados. Elastic Cloud: PENDENTE (M6) |
| P4-M2 | APROVADO (declarativo/validado) | M0 | terraform validate OK; kubeconform 55/55; ensaio local OK | orchestration (CP-03) | Terraform azurerm 5.14 + manifests k8s/azure. Provisionamento real é critério do M5 |
| P4-M3 | PENDENTE (validação real) | M0, M2 | 134/134; KeyPerFile/seed testados; ensaio local OK | serviços + orchestration (CP-03) | Key Vault + CSI + Workload Identity implementados; leitura real de segredos depende do AKS (M5) |
| P4-M4 | EM EXECUÇÃO | M0, M2/M3 | actionlint OK; CI real a executar | serviços + orchestration (CP-03) | Workflow reutilizável CI+CD; CD condicionado a AZURE_DEPLOY_ENABLED; CD real depende do M5 |
| P4-M5 | BLOQUEADO | M2, M3, M4, X1–X4 | — | — | Assinatura Azure `Warned`/inacessível; autorização de custo; Elastic Cloud |
| P4-M6 | NÃO INICIADO | M1, M5, CD operacional | — | — | — |
| P4-M7 | NÃO INICIADO | Evidências dos marcos anteriores | — | — | — |

## Bloqueios ativos

| Bloqueio | Afeta | Desbloqueio necessário | Pode continuar |
|---|---|---|---|
| Assinatura Azure em estado `Warned` e não visível no ARM | M5, M6, aprovação final de M3/M4 | Proprietário reativar/converter a assinatura (Portal → Assinaturas) ou indicar outra; depois `az login` | M1, M2, M3, M4 (CI) |
