# Guia — Persistência poliglota: PostgreSQL, MongoDB, Redis e Elasticsearch

| Armazenamento | Serviço dono | Papel | No AKS |
|---|---|---|---|
| PostgreSQL 16 | UsersAPI (`fcg_users`), CatalogAPI (`fcg_catalog`) | Fonte da verdade transacional | StatefulSet + PVC `managed-csi` 8 GiB; senha do Key Vault |
| MongoDB 7 | PaymentsAPI (`fcg_payments.payments`) | Histórico de pagamentos, um documento por pedido | StatefulSet + PVC; senha do Key Vault |
| Redis 7 | CatalogAPI | Cache distribuído (cache-aside) | Deployment sem persistência, **com senha** (`requirepass`) do Key Vault |
| Elasticsearch 9 | CatalogAPI (`fcg-games`) | Índice de busca derivado | **Elastic Cloud** (gerenciado); ver [ELASTICSEARCH.md](ELASTICSEARCH.md) |

## MongoDB (PaymentsAPI)

Implementado na Fase 3 e preservado ([../nosql.md](../nosql.md)):

- `OrderPlacedEvent` → simulação de pagamento → **upsert idempotente por `orderId`** (índice único) →
  `PaymentProcessedEvent`.
- `GET /api/payments/order/{orderId}` (JWT): dono do pedido 200, outro usuário **403**, Admin 200, inexistente 404.
- Reprocessar o mesmo evento mantém **um** documento (atualiza `updatedAt`).

Demonstração na nuvem:

```bash
# pelo gateway: compra -> consulta do pagamento
curl -H "Authorization: Bearer $TOKEN" http://<gateway>/api/payments/order/<orderId>
# documento no MongoDB (senha lida do Key Vault pelo operador; não exibir em vídeo)
kubectl -n fcg exec -it mongo-0 -- mongosh -u fcg -p "$(az keyvault secret show --vault-name <kv> -n mongo-root-password --query value -o tsv)" \
  --authenticationDatabase admin fcg_payments --eval 'db.payments.find({orderId:"<orderId>"}).pretty()'
```

## Redis (CatalogAPI)

Implementado na Fase 3 ([../cache.md](../cache.md)): cache-aside em `GET /api/games`, `GET /api/games/{id}` e
bibliotecas; TTL 60 s; invalidação explícita em create/update/delete e na aprovação de pagamento; fallback
para o PostgreSQL (`X-FCG-Cache: BYPASS`) se o Redis cair. Na Fase 4 o Redis passou a exigir senha no AKS.

### Medição de impacto

`FCG_ADMIN_PASSWORD=<senha> bash scripts/measure-cache.sh <gateway> <admin-email> [rodadas]` (senha lida do ambiente, nunca na linha de comando) — a cada rodada: `PUT` do mesmo
jogo (invalida a entrada), `GET` (MISS, cronometrado), `GET` (HIT, cronometrado). Classificação pelo
cabeçalho `X-FCG-Cache`, estatísticas min/mediana/média/p95/máx.

Resultados reais registrados em [TEST-EVIDENCE.md](TEST-EVIDENCE.md). Interpretação honesta: com um catálogo
pequeno e consulta por chave primária, o PostgreSQL já responde em poucos milissegundos — o ganho na
**mediana** é pequeno; o efeito aparece mais na **cauda** (p95) e cresce com carga e com consultas mais caras.
Não se afirma ganho além do medido.

### Fallback

```bash
kubectl -n fcg scale deploy/redis --replicas=0     # GET /api/games continua 200, X-FCG-Cache: BYPASS
kubectl -n fcg scale deploy/redis --replicas=1     # volta a MISS -> HIT
```
