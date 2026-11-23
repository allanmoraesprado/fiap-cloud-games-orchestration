# Checklist Final — Fase 4

Marque somente com evidência registrada em [TEST-EVIDENCE.md](TEST-EVIDENCE.md).

| # | Critério de conclusão | Implementação | Evidência local | Evidência na nuvem |
|---|---|---|---|---|
| 1 | AKS real provisionado e validado | `infra/terraform/aks.tf` | `terraform validate` ✔ | ✔ `aks-fcg-demo` 1.36.5, 15 pods prontos + Job concluído |
| 2 | Containers publicados no ACR | `acr.tf`, job `cd` | — | ✔ 4 repositórios no ACR, tags = SHA |
| 3 | Aplicação acessível externamente | Kong `LoadBalancer` + DNS | ensaio NodePort ✔ | ✔ `http://fcg-demo-kwsfp.eastus2.cloudapp.azure.com` |
| 4 | CI/CD real para UsersAPI e CatalogAPI | `dotnet-service.yml` + chamadores | CI no GitHub (ver evidências) | ✔ CD real nos 4 serviços |
| 5 | Push na `main` atualiza a aplicação | job `cd` | — | ✔ push `ee2d0dd` → run 45103663258 |
| 6 | Rolling Update validado | `RollingUpdate` 0/1 + readiness + preStop | ensaio: 219/219 HTTP 200 ✔ | ✔ 194/194 HTTP 200 no rollout |
| 7 | MongoDB integrado | Fase 3 + StatefulSet/PVC | smoke Compose e ensaio ✔ | ✔ pagamentos + persistência após recriar o pod |
| 8 | Redis integrado e impacto medido | Fase 3 + senha + `measure-cache.sh` | medição local ✔ | ✔ in-cluster 5,3 → 3,4 ms (mediana) |
| 9 | Elasticsearch gerenciado com fuzzy e relevância | CatalogAPI + Elastic Cloud | 16 testes de integração + smoke ✔ | ✔ Elastic Cloud 9.5.6 (fuzzy/relevância) |
| 10 | Sincronização do índice | pós-commit + reconciliação + reindex | testes + queda/recuperação ✔ | ✔ create/update/delete/reindex no smoke real |
| 11 | Key Vault integrado às aplicações | CSI + Workload Identity + KeyPerFile | ensaio com Secret local ✔ | ✔ CSI + Workload Identity, 0 Secrets k8s |
| 12 | Testes e smoke aprovados | 134 testes; smokes | ✔ | ✔ smoke real 0 falhas |
| 13 | Relatórios e documentação | `docs/phase4/`, README | ✔ | ✔ evidências de nuvem incluídas |
| 14 | Repositórios atualizados | commits/pushes por repositório | ✔ (hashes em CHECKPOINTS) | — |
| 15 | Demonstração preparada | [VIDEO-SCRIPT.md](VIDEO-SCRIPT.md) | roteiro ✔ | roteiro com URLs reais ✔; ☐ gravação PENDENTE |

Entrega:

- [ ] Grupo, participante(s) e Discord preenchidos no [FINAL-REPORT.md](FINAL-REPORT.md) (dados do proprietário).
- [ ] Link do vídeo (≤ 25 min) no FINAL-REPORT.
- [x] Evidências de nuvem registradas ([TEST-EVIDENCE.md](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) e STATUS atualizado.
- [ ] Recursos destruídos após a gravação ([DESTROY.md](DESTROY.md)), incluindo Elastic Cloud.
