# Guia — Observabilidade no AKS (Prometheus, Grafana, Loki, Alloy)

Mesmo conjunto da Fase 3 ([../observability.md](../observability.md)), adaptado ao Kubernetes gerenciado.

| Componente | Manifesto | Configuração (fonte única) | Acesso |
|---|---|---|---|
| Prometheus v3.5 | `k8s/azure/30-prometheus.yaml` | `observability/prometheus/prometheus-aks.yml` | `kubectl -n fcg port-forward svc/prometheus 9090` |
| Loki 3.5 | `k8s/azure/31-loki.yaml` | `observability/loki/loki.yml` (igual ao Compose) | via Grafana |
| Alloy v1.11 | `k8s/azure/32-alloy.yaml` | `observability/alloy/config-aks.alloy` | — |
| Grafana 12.1 | `k8s/azure/33-grafana.yaml` | datasources + dashboards de `observability/grafana` | `kubectl -n fcg port-forward svc/grafana 3000` (admin / senha do Key Vault `grafana-admin-password`) |

Nenhum desses serviços é exposto publicamente (somente o proxy do Kong é público).

## Métricas

- **Descoberta de pods** no namespace `fcg` (Role de leitura, sem permissões de cluster): todo pod com
  `prometheus.io/scrape: "true"` é coletado — inclusive cada réplica durante um rolling update.
- Rótulos: `job` = rótulo `app` do pod (mesmos nomes do Compose: `users-api`, `catalog-api`, `payments-api`,
  `kong`), `pod`, `version` (= SHA da imagem) → é possível ver a troca de versão no Grafana.
- Métricas de negócio da Fase 3 e, na Fase 4, as da busca: `fcg_search_requests_total`,
  `fcg_search_duration_seconds`, `fcg_search_index_operations_total`.

## Logs

- O Alloy lê os logs de todos os pods do namespace pela API do Kubernetes (`loki.source.kubernetes`).
- Rótulos compatíveis com o Compose: `platform="fcg"`, `compose_service=<app>`, `job="fcg/<app>"`, mais
  `pod`, `container`, `namespace`, `cluster="aks"`. O dashboard **FCG Logs** funciona sem alteração.

LogQL úteis:

```logql
{platform="fcg", compose_service="notifications-function"} |= "[WELCOME EMAIL]"
{platform="fcg", compose_service="notifications-function"} |= "[PURCHASE CONFIRMATION]"
{platform="fcg"} |= "<orderId>"                      # rastreia o pedido: catalog -> payments -> function
{platform="fcg", compose_service="catalog-api"} |= "Search index"
{platform="fcg", compose_service="kong"} |= " 401 "
```

## Rastreamento de requisições e pedidos

- `X-Correlation-ID` gerado pelo Kong (plugin `correlation-id`) e devolvido ao cliente.
- `OrderId`/`UserId` nos logs estruturados dos serviços (Fase 3) permitem seguir um pedido entre serviços.
- `X-App-Version` identifica qual versão atendeu a requisição.

Validação local (ensaio dos manifests): ver [TEST-EVIDENCE.md](TEST-EVIDENCE.md) — targets `up` por réplica
com rótulo `version`, 15 serviços com logs no Loki, `[WELCOME EMAIL]` encontrado com os rótulos acima.
