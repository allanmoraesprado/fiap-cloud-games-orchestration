# Status da Fase 4

Última atualização: 2026-11-17

| Marco | Status | Dependências | Testes | Commit | Observações |
|---|---|---|---|---|---|
| P4-M0 | APROVADO | — | baseline 71/71 | orchestration (ver CHECKPOINTS) | Auditoria, plano, matriz, custos, riscos. Bloqueio Azure identificado (K01) |
| P4-M1 | EM EXECUÇÃO | M0 | — | — | Independente de Azure; validação no Elastic Cloud no M6 |
| P4-M2 | NÃO INICIADO | M0 | — | — | Validação local (`terraform validate`); provisionamento no M5 |
| P4-M3 | NÃO INICIADO | M0, integração com M2 | — | — | Validação real depende do M5 |
| P4-M4 | NÃO INICIADO | M0, integração com M2/M3 | — | — | CI pode rodar de verdade no GitHub; CD depende do M5 |
| P4-M5 | BLOQUEADO | M2, M3, M4, X1–X4 | — | — | Assinatura Azure `Warned`/inacessível; autorização de custo; Elastic Cloud |
| P4-M6 | NÃO INICIADO | M1, M5, CD operacional | — | — | — |
| P4-M7 | NÃO INICIADO | Evidências dos marcos anteriores | — | — | — |

## Bloqueios ativos

| Bloqueio | Afeta | Desbloqueio necessário | Pode continuar |
|---|---|---|---|
| Assinatura Azure em estado `Warned` e não visível no ARM | M5, M6, aprovação final de M3/M4 | Proprietário reativar/converter a assinatura (Portal → Assinaturas) ou indicar outra; depois `az login` | M1, M2, M3, M4 (CI) |
