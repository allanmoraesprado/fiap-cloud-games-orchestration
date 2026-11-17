# Checklist Final — Fase 4

Marque somente com evidência registrada em [TEST-EVIDENCE.md](TEST-EVIDENCE.md).

| # | Critério de conclusão | Implementação | Evidência local | Evidência na nuvem |
|---|---|---|---|---|
| 1 | AKS real provisionado e validado | `infra/terraform/aks.tf` | `terraform validate` ✔ | ☐ PENDENTE (assinatura bloqueada) |
| 2 | Containers publicados no ACR | `acr.tf`, job `cd` | — | ☐ PENDENTE |
| 3 | Aplicação acessível externamente | Kong `LoadBalancer` + DNS | ensaio NodePort ✔ | ☐ PENDENTE |
| 4 | CI/CD real para UsersAPI e CatalogAPI | `dotnet-service.yml` + chamadores | CI no GitHub (ver evidências) | ☐ CD PENDENTE |
| 5 | Push na `main` atualiza a aplicação | job `cd` | — | ☐ PENDENTE |
| 6 | Rolling Update validado | `RollingUpdate` 0/1 + readiness + preStop | ensaio: 219/219 HTTP 200 ✔ | ☐ PENDENTE |
| 7 | MongoDB integrado | Fase 3 + StatefulSet/PVC | smoke Compose e ensaio ✔ | ☐ PENDENTE |
| 8 | Redis integrado e impacto medido | Fase 3 + senha + `measure-cache.sh` | medição local ✔ | ☐ PENDENTE |
| 9 | Elasticsearch gerenciado com fuzzy e relevância | CatalogAPI + Elastic Cloud | 16 testes de integração + smoke ✔ | ☐ PENDENTE (conta Elastic Cloud) |
| 10 | Sincronização do índice | pós-commit + reconciliação + reindex | testes + queda/recuperação ✔ | ☐ PENDENTE |
| 11 | Key Vault integrado às aplicações | CSI + Workload Identity + KeyPerFile | ensaio com Secret local ✔ | ☐ PENDENTE |
| 12 | Testes e smoke aprovados | 134 testes; smokes | ✔ | ☐ PENDENTE |
| 13 | Relatórios e documentação | `docs/phase4/`, README | ✔ (atualizar com evidências de nuvem) | — |
| 14 | Repositórios atualizados | commits/pushes por repositório | ✔ (hashes em CHECKPOINTS) | — |
| 15 | Demonstração preparada | [VIDEO-SCRIPT.md](VIDEO-SCRIPT.md) | roteiro ✔ | ☐ gravação PENDENTE |

Entrega:

- [ ] Grupo, participante(s) e Discord preenchidos no [FINAL-REPORT.md](FINAL-REPORT.md) (dados do proprietário).
- [ ] Link do vídeo (≤ 25 min) no FINAL-REPORT.
- [ ] Evidências de nuvem anexadas (prints/logs) e STATUS atualizado.
- [ ] Recursos destruídos após a gravação ([DESTROY.md](DESTROY.md)), incluindo Elastic Cloud.
