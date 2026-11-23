# Matriz de Requisitos — Fase 4

Fonte: enunciado da Fase 4 (requisitos explicitados no plano de execução; o PDF oficial
`TC NETT - Fase 4.pdf` não está disponível no workspace). Status conforme [STATUS.md](STATUS.md).

Legenda de status: `NÃO INICIADO`, `EM EXECUÇÃO`, `PENDENTE`, `BLOQUEADO`, `APROVADO`, `REPROVADO`, `NÃO APLICÁVEL`.

## Critérios finais de conclusão

| ID | Requisito | Marco | Implementação prevista | Teste / evidência | Status |
|---|---|---|---|---|---|
| R01 | AKS real provisionado e validado | M2, M5 | `infra/terraform` (`azurerm_kubernetes_cluster`) | `kubectl get nodes,pods -n fcg`, Portal | APROVADO — `aks-fcg-demo` (1.36.5, 1 nó `Standard_D4as_v6`) com 15 pods prontos + Job concluído (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R02 | Containers publicados no ACR privado | M2, M4, M5 | ACR Basic, admin desabilitado, `AcrPull` para o kubelet, `AcrPush` para o deploy | `az acr repository show-tags`; log do pipeline | APROVADO — ACR Basic privado (sem admin/pull anônimo); 4 repositórios com tags = SHA (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R03 | Aplicação acessível externamente | M5 | Kong `Service type: LoadBalancer` (IP público) | `curl http://<ip>/api/...` | APROVADO — `http://fcg-demo-kwsfp.eastus2.cloudapp.azure.com` (401 sem token; smoke 0 falhas) (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R04 | CI/CD real para UsersAPI e CatalogAPI | M4 | Workflows reutilizáveis + chamadores | Execuções do GitHub Actions | APROVADO — CD real nos 4 serviços (UsersAPI e CatalogAPI incluídos) (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R05 | Push em `main` atualiza automaticamente a aplicação | M4, M6 | Job de CD em `push` na `main` | Run + imagem nova no pod | APROVADO — push `ee2d0dd` na CatalogAPI → run 45103663258 (CI+CD) → pods com a nova imagem (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R06 | Rolling Update validado | M4, M6 | `RollingUpdate` (`maxUnavailable: 0`, `maxSurge: 1`), readiness | `kubectl rollout status/history`, sonda de disponibilidade durante o deploy | APROVADO — rollout sob carga: 194/194 HTTP 200; ensaio local 219/219 (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R07 | MongoDB integrado | M5, M6 | Já implementado (Fase 3); StatefulSet com PVC no AKS | Pagamento → documento → `GET /api/payments/order/{id}` | APROVADO — pagamentos Approved/Rejected via API; dados preservados após recriar `mongo-0`; 403 para outro usuário (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R08 | Redis integrado e impacto medido | M5, M6 | Já implementado (Fase 3); script de medição de latência | MISS/HIT/invalidação + amostras numéricas | APROVADO — MISS→HIT; mediana 5,3 → 3,4 ms dentro do cluster (−34,7 %) (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R09 | Elasticsearch gerenciado com fuzzy search e relevância | M1, M5, M6 | CatalogAPI + Elastic Cloud | Testes de integração + smoke contra Elastic Cloud | APROVADO — Elastic Cloud 9.5.6: exata, fuzzy, relevância, validação no smoke real (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R10 | Sincronização do índice implementada e validada | M1 | Indexação pós-commit + reconciliação + reindexação | Testes de integração e smoke | APROVADO — local e nuvem (carga inicial, reconciliação, criação/edição/exclusão, reindex) (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R11 | Key Vault integrado às aplicações | M3, M5 | CSI Driver + Workload Identity | Segredo lido em runtime no pod; nenhum `Secret` k8s com credenciais | APROVADO — CSI + Workload Identity; arquivos montados por workload; 0 `Secret` no namespace (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R12 | Testes e smoke tests aprovados | todos | `dotnet test`, scripts de smoke | [TEST-EVIDENCE.md](TEST-EVIDENCE.md) | APROVADO — 134 testes (CI); smoke real 0 falhas; smoke por serviço no CD (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R13 | Relatórios e documentação completos | M7 | `docs/phase4/*`, README | Revisão final | EM EXECUÇÃO — documentação atualizada com evidências de nuvem; faltam dados do grupo e link do vídeo |
| R14 | Repositórios atualizados (commits/pushes) | todos | Commits organizados por repositório | Hashes em [CHECKPOINTS.md](CHECKPOINTS.md) | APROVADO — hashes em [CHECKPOINTS.md](CHECKPOINTS.md) (CP-06) |
| R15 | Demonstração final preparada | M7 | Roteiro de vídeo ≤ 25 min | `docs/phase4/VIDEO-SCRIPT.md` | APROVADO (roteiro com URLs e comandos reais); gravação PENDENTE (proprietário) |

## Busca avançada (P4-M1)

| ID | Requisito | Implementação prevista | Teste | Status |
|---|---|---|---|---|
| R16 | Endpoint `GET /api/games/search` | `GamesController.Search` | Integração + smoke | APROVADO (local) |
| R17 | Pesquisa textual por nome e demais campos | `multi_match` em `title^3`, `genre^2`, `description` | Integração | APROVADO (local) |
| R18 | Fuzzy Search | `fuzziness: AUTO`, `prefix_length: 1` | "Cosmik Odysey" → "Cosmic Odyssey" | APROVADO (local) |
| R19 | Ordenação por relevância | `_score` desc + boost de frase exata no título; desempate por título | Integração (ordem) | APROVADO (local) |
| R20 | Tratamento de entradas inválidas | `q` 2–100 caracteres, `page ≥ 1`, `pageSize 1–50`, janela ≤ 10.000 → 400 | Unitário + smoke | APROVADO (local) |
| R21 | Paginação | `from/size`, resposta com `total`, `page`, `pageSize` | Integração | APROVADO (local) |
| R22 | Indexação inicial dos jogos existentes | Reconciliação na inicialização (marca d'água vazia ⇒ carga completa) | Integração + smoke | APROVADO (local) |
| R23 | Indexação de jogos recém-criados | `GameService.CreateAsync` → indexador após commit | Unitário + integração + smoke | APROVADO (local) |
| R24 | Atualização após edição / desativação | `UpdateAsync`/`DeleteAsync` → upsert (desativado = `isActive:false`) | Unitário + integração + smoke | APROVADO (local) |
| R25 | Recuperação / reindexação | Reconciliação periódica + `POST /api/games/search/reindex` (Admin) | Integração | APROVADO (local) |
| R26 | Indisponibilidade do mecanismo de busca | Busca → 503 + `Retry-After`; escrita continua 2xx; reconciliação recupera | Integração + smoke (parar ES) | APROVADO (local) |
| R27 | Consistência eventual documentada | [ELASTICSEARCH.md](ELASTICSEARCH.md) | Revisão | APROVADO |

## Infraestrutura (P4-M2)

| ID | Requisito | Implementação prevista | Teste | Status |
|---|---|---|---|---|
| R28 | Infra declarativa | Terraform `azurerm` em `infra/terraform` | `fmt`, `validate` | APROVADO — provisionado com Terraform em 2026-11-22 (66 recursos + 3 atualizações) (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R29 | Resource Group dedicado, nomes e tags consistentes | `rg-fcg-<env>`; tags `project`, `environment`, `managed-by`, `phase` | `validate` + plan | APROVADO — provisionado com Terraform em 2026-11-22 (66 recursos + 3 atualizações) (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R30 | Rede e regras de acesso | VNet/subnet, Azure CNI Overlay, Kong como único LoadBalancer público, Admin API do Kong interna | Revisão + smoke | APROVADO — provisionado com Terraform em 2026-11-22 (66 recursos + 3 atualizações) (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R31 | Storage/volumes persistentes | PVC `managed-csi` para Postgres, MongoDB, Kafka | `kubectl get pvc` | APROVADO — provisionado com Terraform em 2026-11-22 (66 recursos + 3 atualizações) (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R32 | Configurações separadas por ambiente | `environments/*.tfvars.example`; manifests `k8s/azure` vs `k8s` local | Revisão | APROVADO — provisionado com Terraform em 2026-11-22 (66 recursos + 3 atualizações) (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R33 | Procedimentos de criação, validação e destruição | Scripts + `docs/phase4/PROVISIONING.md` / `DESTROY.md` | Execução no M5 | APROVADO — provisionado com Terraform em 2026-11-22 (66 recursos + 3 atualizações) (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R34 | Orçamento/alerta de custos | `azurerm_consumption_budget_resource_group` | Portal | APROVADO — provisionado com Terraform em 2026-11-22 (66 recursos + 3 atualizações) (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R35 | Integração prevista com Elastic Cloud | Variáveis + segredo no Key Vault | M5 | APROVADO — provisionado com Terraform em 2026-11-22 (66 recursos + 3 atualizações) (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |

## Segurança (P4-M3)

| ID | Requisito | Implementação prevista | Teste | Status |
|---|---|---|---|---|
| R36 | Key Vault para credenciais reais | Key Vault (RBAC), segredos gerados pelo Terraform | Portal + leitura em runtime | APROVADO — validado no AKS (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R37 | GitHub Actions com OIDC | UAMI com credenciais federadas (`repo:<owner>/<repo>:ref:refs/heads/main`) | Run do CD sem segredo de cliente | APROVADO — validado no AKS (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R38 | AKS Workload Identity | UAMI por workload + ServiceAccount anotada | Pod autenticado no Key Vault | APROVADO — validado no AKS (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R39 | Injeção de segredos em runtime | Secrets Store CSI Driver (arquivos) + `KeyPerFile` / `*_FILE` / init container do Kong | Pod em execução | APROVADO — validado no AKS (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R40 | JWT seguro e Kong de produção | Segredo aleatório de 64 bytes no Key Vault; `kong.yml` renderizado no pod; Admin API sem exposição | Smoke 401/200 | APROVADO — validado no AKS (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R41 | Sem segredos fixos em manifests produtivos | Manifests `k8s/azure` sem `Secret`/literais | Varredura (`git grep`) | APROVADO — validado no AKS (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R42 | Separação local × produção | Placeholders só em `.env.example`, `k8s/` local, `appsettings.Development.json` | Revisão | APROVADO — validado no AKS (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R43 | Permissões mínimas | `Key Vault Secrets User` por segredo; `AcrPush`; AKS RBAC Writer no namespace | Revisão de role assignments | APROVADO — validado no AKS (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |

## CI/CD (P4-M4)

| ID | Requisito | Implementação prevista | Teste | Status |
|---|---|---|---|---|
| R44 | Etapas 1–14 do pipeline | Workflows reutilizáveis | Logs de execução | APROVADO — execução real no GitHub Actions (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R45 | CI e CD separados | `ci` (PR/push) e `cd` (push na `main`) | Execuções | APROVADO — execução real no GitHub Actions (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R46 | Sem deploy em PR não confiável | CD condicionado a `push` na `main`; OIDC só confia na `main` | Run de PR sem job de CD | APROVADO (configuração verificada na nuvem: credenciais federadas só `ref:refs/heads/main`; job `cd` só em push/dispatch na `main`; nenhum PR executado) |
| R47 | Rastreabilidade commit → imagem → versão | Tag = SHA completo; `X-App-Version`; anotação `change-cause` | Header + `rollout history` | APROVADO — execução real no GitHub Actions (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R48 | Não usar `latest` como única referência | Somente tags SHA | Revisão | APROVADO — execução real no GitHub Actions (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R49 | Security scan | Trivy (imagem) | Log do pipeline | APROVADO — execução real no GitHub Actions (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |

## Nuvem e observabilidade (P4-M5/M6)

| ID | Requisito | Implementação prevista | Teste | Status |
|---|---|---|---|---|
| R50 | Kafka no ambiente cloud | StatefulSet KRaft com PVC no AKS | Fluxo de compra | APROVADO — `kafka-0` com PVC; tópicos criados pelo Job; fluxo de compra no smoke real (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R51 | Notifications Function na nuvem | Container do host Azure Functions no AKS | Logs `[WELCOME EMAIL]`/`[PURCHASE CONFIRMATION]` | APROVADO — `[WELCOME EMAIL]`/`[PURCHASE CONFIRMATION]` encontrados no Loki (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R52 | Métricas Prometheus + dashboards Grafana | Prometheus com `kubernetes_sd`, Grafana provisionado | Targets `up`, dashboards | APROVADO — 7 alvos `up` (rótulo `version` = SHA); Grafana 12.1 com FCG Overview/FCG Logs (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R53 | Logs centralizados (aplicação e função) | Loki + Alloy (`loki.source.kubernetes`) no AKS | LogQL por serviço/OrderId | APROVADO — logs da Function consultados no Loki pelo e-mail e pelo `orderId` (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |
| R54 | Smoke tests reais no Azure | `scripts/smoke-compose.ps1 -GatewayUrl` + `scripts/ci/smoke-service.sh` | Saída do script | APROVADO — `smoke-compose.ps1 -GatewayUrl <gateway público>`: 0 falhas; `smoke-service.sh` no CD (nuvem, 2026-11-22/23 — [TEST-EVIDENCE](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)) |

## Entrega (P4-M7)

| ID | Requisito | Implementação prevista | Status |
|---|---|---|---|
| R55 | Documentação em pt-BR (README, guias) | `README.md`, `docs/phase4/*` | APROVADO — README central e guias em pt-BR |
| R56 | Relatório com grupo, participante(s), Discord, links e vídeo | `FINAL-REPORT.md` (dados pessoais fornecidos pelo proprietário) | PENDENTE — grupo, participante(s), Discord e link do vídeo (dados do proprietário) |
| R57 | Roteiro do vídeo (≤ 25 min) | `VIDEO-SCRIPT.md` | APROVADO — [VIDEO-SCRIPT.md](VIDEO-SCRIPT.md) com URLs e comandos do ambiente real |
| R58 | Guia de destruição de recursos (incl. Elastic Cloud) | `DESTROY.md` | APROVADO (guia + script; execução no fim) |
