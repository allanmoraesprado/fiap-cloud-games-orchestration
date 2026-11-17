# Evidências de Testes — Fase 4

Somente resultados efetivamente executados. Itens não executados aparecem como `PENDENTE`/`BLOQUEADO`.

## Baseline (P4-M0, 2026-11-17)

`dotnet test` em cada repositório, estação local (SDK 10.0.102, runtime 8.0.20):

| Repositório | Commit | Resultado |
|---|---|---|
| users-api | `3681486` | 21 aprovados, 0 falhas |
| catalog-api | `e3d03b3` | 22 aprovados, 0 falhas |
| payments-api | `72bde0f` | 15 aprovados, 0 falhas |
| notifications-function | `0e7e956` | 13 aprovados, 0 falhas |
| **Total** | | **71 / 71** |

Verificação de acesso Azure (somente leitura):

```
az account show            -> state: "Warned"
az group list              -> ERROR (SubscriptionNotFound)
GET /subscriptions (ARM)   -> []
```
