# Roteiro do Vídeo — Fase 4 (até 25 minutos)

> Ambiente real ativo (validado em 2026-11-22/23 — [TEST-EVIDENCE.md](TEST-EVIDENCE.md#validação-na-nuvem-azure-aks)).
> **Não exibir valores de segredos**: listar arquivos com `ls`, nunca `cat`; senhas vão direto do Key Vault para
> variáveis, sem aparecer na tela.

## Dados do ambiente

| Item | Valor |
|---|---|
| Gateway público (Kong) | `http://fcg-demo-kwsfp.eastus2.cloudapp.azure.com` (IP `4.152.230.114`) |
| Resource groups | `rg-fcg-demo` e `rg-fcg-demo-aks-nodes` (`eastus2`) |
| AKS / ACR / Key Vault | `aks-fcg-demo` / `acrfcgdemokwsfp` / `kv-fcg-demo-kwsfp` |
| Elastic Cloud | deployment 9.5.6 (`eastus2`), índice `fcg-games` |
| GitHub Actions | `https://github.com/allanmoraesprado/fiap-cloud-games-catalog-api/actions` (e os demais serviços) |

## Preparação (antes de gravar, ~10 min)

Terminal **Git Bash** novo (o `winget` acrescentou `terraform`, `kubelogin` e `gh` ao PATH), na pasta do
repositório de orquestração:

```bash
az account show --query "{name:name,state:state}" -o table      # FCG-Phase4 / Enabled
export KUBECONFIG="$HOME/.kube/fcg-aks-demo"                     # kubeconfig separado (não mexe no docker-desktop)
az aks get-credentials -g rg-fcg-demo -n aks-fcg-demo --file "$KUBECONFIG" --overwrite-existing
kubelogin convert-kubeconfig -l azurecli --kubeconfig "$KUBECONFIG"
kubectl get nodes                                                  # 1 nó Ready
export GW=http://fcg-demo-kwsfp.eastus2.cloudapp.azure.com

# Tokens (usuário de demonstração e admin semeado; senha do admin lida do Key Vault, sem exibir)
login() { curl -s -X POST "$GW/api/auth/login" -H 'Content-Type: application/json' --data-binary @- | sed -n 's/.*"token":"\([^"]*\)".*/\1/p'; }
curl -s -o /dev/null -w "%{http_code}\n" -X POST "$GW/api/auth/register" -H 'Content-Type: application/json' \
  -d '{"name":"Demo Video","email":"demo.video@fcg.com","password":"Demo#2026a"}'   # 201 (ou 409 se já existir)
TOKEN=$(printf '{"email":"demo.video@fcg.com","password":"Demo#2026a"}' | login)
ADMIN_TOKEN=$(az keyvault secret show --vault-name kv-fcg-demo-kwsfp -n users-admin-seed-password --query value -o tsv \
  | tr -d '\r' | node -e 'const p=require("fs").readFileSync(0,"utf8").trim();process.stdout.write(JSON.stringify({email:"admin@fcg.com",password:p}))' | login)

# Grafana e Prometheus (deixar rodando em outro terminal; portas livres na estação)
kubectl -n fcg port-forward svc/grafana 13000:3000 &
kubectl -n fcg port-forward svc/prometheus 19090:9090 &
# Login do Grafana: usuário admin; senha = segredo grafana-admin-password (copiar fora da gravação)
```

Abas abertas: Portal Azure (`rg-fcg-demo`), GitHub Actions da CatalogAPI, console do Elastic Cloud,
Grafana (`http://localhost:13000`).

> Git Bash converte caminhos que começam com `/`: em `kubectl exec ... ls` use `//mnt/secrets-store`.
> Rate limit do Kong: 120 req/min por IP. Na sonda do live deploy use `PACE_SECONDS=1` (60 req/min) para
> sobrar margem às chamadas manuais.

## Roteiro

| Tempo | Bloco | O que mostrar | Comando / tela |
|---|---|---|---|
| 0:00–1:30 | Abertura | Grupo, objetivo da fase, o que mudou desde a Fase 3 | [ARCHITECTURE.md](ARCHITECTURE.md) (diagrama) |
| 1:30–4:00 | Portal Azure | `rg-fcg-demo` e `rg-fcg-demo-aks-nodes`; AKS (Free, 1.36.5, Workload Identity); ACR (admin desabilitado); Key Vault (RBAC, **lista de nomes** dos 12 segredos); identidades gerenciadas e credenciais federadas (`id-fcg-demo-github-deploy` → `ref:refs/heads/main`); orçamento | Portal |
| 4:00–5:30 | Infra como código | `infra/terraform`: AKS, segredos `ephemeral` + `value_wo` (nada no state), identidades por workload com acesso por segredo, OIDC do GitHub | editor |
| 5:30–7:00 | Cluster | `kubectl get nodes -o wide`; `kubectl -n fcg get pods,svc,pvc`; `kong-proxy` com IP público | terminal |
| 7:00–8:30 | Key Vault em runtime | `kubectl -n fcg exec deploy/redis -- ls //mnt/secrets-store`; `kubectl get secretproviderclasspodstatuses -n fcg`; `kubectl -n fcg get secrets` (nenhum); `kubectl -n fcg get sa catalog-api -o yaml` (anotação `client-id`) | terminal |
| 8:30–10:00 | Acesso externo + JWT | `curl -i $GW/api/games` → **401**; `curl -si $GW/api/games -H "Authorization: Bearer $TOKEN" \| head -20` → 200, `X-App-Version`, `X-FCG-Cache` | terminal |
| 10:00–14:30 | **Live deploy** | 1) Terminal A: `PACE_SECONDS=1 bash scripts/rolling-probe.sh $GW 600`. 2) Terminal B: `kubectl -n fcg get pods -l app=catalog-api -w`. 3) Alterar a CatalogAPI (ex.: uma linha do `README.md` ou uma mensagem de log), `git commit` + `git push origin main`. 4) Actions: CI (testes, Trivy) → CD (OIDC, push no ACR com o SHA, rollout, smoke). 5) Mostrar a sonda trocando de `X-App-Version` só com HTTP 200 e o resumo final | GitHub Actions + terminais |
| 14:30–15:30 | Rastreabilidade | `az acr repository show-tags -n acrfcgdemokwsfp --repository fcg-catalog-api -o table`; `kubectl -n fcg rollout history deploy/catalog-api` (commit + run id); Prometheus: `up{job="catalog-api"}` com rótulo `version` | terminal + Prometheus |
| 15:30–18:00 | **Busca com fuzzy** | `curl -s "$GW/api/games/search?q=Cosmic%20Odyssey" -H "Authorization: Bearer $TOKEN"` (exata, `score`); `?q=Cosmik%20Odisey` (erro de digitação); `?q=zzzz` (vazia); `?q=a` → 400; admin cria jogo (`POST $GW/api/games` com `$ADMIN_TOKEN`) e busca na hora; console do Elastic Cloud com o índice `fcg-games` | terminal + console Elastic |
| 18:00–20:00 | **Impacto do cache** | Duas chamadas a `GET $GW/api/games` mostrando `X-FCG-Cache` MISS → HIT; `export FCG_ADMIN_PASSWORD=$(az keyvault secret show --vault-name kv-fcg-demo-kwsfp -n users-admin-seed-password --query value -o tsv \| tr -d '\r')` e `bash scripts/measure-cache.sh $GW admin@fcg.com 30`; explicar que pela internet a rede domina e mostrar a medição dentro do cluster registrada (mediana 5,3 → 3,4 ms); `fcg_cache_requests_total` no Grafana | terminal + Grafana |
| 20:00–21:30 | **MongoDB** | `curl -s $GW/api/games -H "Authorization: Bearer $TOKEN"` (pegar um `id`); `curl -s -X POST $GW/api/library/acquire/<gameId> -H "Authorization: Bearer $TOKEN"` → 202 + `orderId`; `curl -s $GW/api/payments/order/<orderId> -H "Authorization: Bearer $TOKEN"` → `Approved`; mesmo `orderId` com outro usuário → 403; persistência após recriar o pod (evidência registrada) | terminal |
| 21:30–23:30 | Observabilidade | Grafana **FCG Overview** (requisições, Kong 401/429, cache, pagamentos, busca); **FCG Logs** filtrando o `orderId` e o `[WELCOME EMAIL]` da Notifications Function | Grafana |
| 23:30–25:00 | Encerramento | Arquitetura final, custos ([COSTS.md](COSTS.md)), destruição planejada ([DESTROY.md](DESTROY.md)), links | docs |

## Depois da gravação

1. Registrar o link do vídeo e os dados do grupo no [FINAL-REPORT.md](FINAL-REPORT.md).
2. Encerrar os port-forwards (`kill %1 %2` no Git Bash).
3. Para economizar sem destruir: `az aks stop -g rg-fcg-demo -n aks-fcg-demo` (≈ US$ 1,4/dia; `az aks start` religa).
4. Destruição definitiva somente com confirmação do proprietário: [DESTROY.md](DESTROY.md) (inclui o Elastic Cloud).
