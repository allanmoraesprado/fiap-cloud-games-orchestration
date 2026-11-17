# Roteiro do Vídeo — Fase 4 (até 25 minutos)

> Pré-requisitos: ambiente Azure provisionado e validado (PROVISIONING.md), Elastic Cloud ativo, variáveis do
> GitHub configuradas, um terminal com `kubectl` autenticado, Portal Azure aberto, Grafana em port-forward.
> **Não exibir valores de segredos** (usar `ls /mnt/secrets-store`, nunca `cat`).

Preparação (fora da gravação): `GW=http://<label>.eastus2.cloudapp.azure.com`, um token de usuário e um de admin
(senha do admin lida do Key Vault), `kubectl -n fcg port-forward svc/grafana 3000` e `svc/prometheus 9090`.

| Tempo | Bloco | O que mostrar | Comando / tela |
|---|---|---|---|
| 0:00–1:30 | Abertura | Grupo, objetivo da fase, o que mudou desde a Fase 3 | `docs/phase4/ARCHITECTURE.md` (diagrama) |
| 1:30–4:00 | Portal Azure e recursos | Resource groups `rg-fcg-demo` e `-aks-nodes`, AKS, ACR, Key Vault (RBAC, lista de segredos sem valores), identidades gerenciadas e credenciais federadas, orçamento | Portal |
| 4:00–5:30 | Infra como código | Terraform: AKS (Workload Identity, CSI, Entra ID), segredos `ephemeral` + `value_wo` (nada no state), identidades por workload com acesso por segredo, OIDC do GitHub | `infra/terraform/*.tf` |
| 5:30–7:00 | Pods no AKS | `kubectl get nodes`; `kubectl -n fcg get pods,svc,pvc`; serviço `kong-proxy` com IP/DNS públicos | terminal |
| 7:00–8:30 | Key Vault em runtime | `kubectl -n fcg exec deploy/catalog-api -- ls /mnt/secrets-store`; `kubectl -n fcg get secrets` (sem credenciais); anotação da ServiceAccount; role assignments no escopo do segredo | terminal + Portal |
| 8:30–10:00 | Aplicação externa + JWT | `curl -i $GW/api/games` → 401; registro/login → 200; `GET /api/games` com token → 200 e `X-App-Version` | terminal |
| 10:00–14:30 | **Live deploy** | Alterar algo visível na CatalogAPI → `git push` → Actions: CI (testes, Trivy) → CD (OIDC, push ACR com SHA, rollout, smoke). Em paralelo: `kubectl -n fcg get pods -l app=catalog-api -w` e laço de requisições mostrando 200 contínuo e troca do `X-App-Version` | GitHub Actions + terminal |
| 14:30–15:30 | Rastreabilidade | `az acr repository show-tags`; `kubectl rollout history`; label `version` no Prometheus | terminal |
| 15:30–18:00 | **Busca com fuzzy** | `GET /api/games/search?q=Cosmic%20Odyssey` (exata), `?q=Cosmik%20Odisey` (erro de digitação), relevância (`score`), sem resultados, 400; admin cria jogo → busca imediata; edita → índice atualizado; Elastic Cloud (console) mostrando o índice `fcg-games` | terminal + console Elastic |
| 18:00–20:00 | **Impacto do cache** | `X-FCG-Cache` MISS→HIT; `bash scripts/measure-cache.sh $GW admin@fcg.com <senha> 30` com a tabela de latências; métrica `fcg_cache_requests_total` | terminal + Grafana |
| 20:00–21:30 | **MongoDB** | Compra → `GET /api/payments/order/{orderId}` (200 dono, 403 outro usuário); documento no MongoDB; idempotência | terminal |
| 21:30–23:30 | Observabilidade | Grafana **FCG Overview** (requisições, Kong 401/429, cache, pagamentos, busca); **FCG Logs** filtrando o `orderId` e os e-mails da Notifications Function | Grafana |
| 23:30–25:00 | Arquitetura final e encerramento | Diagrama, custos (COSTS.md), destruição planejada (DESTROY.md), links | docs |

Checklist pós-gravação: salvar o link do vídeo no [FINAL-REPORT.md](FINAL-REPORT.md); só então executar
[DESTROY.md](DESTROY.md).
