# Guia — Busca Avançada com Elasticsearch

## Visão geral

A CatalogAPI expõe `GET /api/games/search`, respondida exclusivamente por um índice Elasticsearch
(`fcg-games`), independente das consultas relacionais. O PostgreSQL continua sendo a fonte da
verdade; o índice é uma cópia derivada, mantida com **consistência eventual**.

| Ambiente | Elasticsearch | Autenticação |
|---|---|---|
| Docker Compose / k8s local | `docker.elastic.co/elasticsearch/elasticsearch:9.5.5`, nó único, segurança desabilitada (somente desenvolvimento) | nenhuma |
| Testes de integração | mesma imagem via Testcontainers (container descartável) | nenhuma |
| Azure (AKS) | **Elastic Cloud** (deployment gerenciado 9.x) | API key (Key Vault) |

Cliente: `Elastic.Clients.Elasticsearch` 9.5.3 (suporte oficial a .NET 8).

## Endpoint

```
GET /api/games/search?q=<texto>&genre=<gênero>&page=<n>&pageSize=<n>     (JWT obrigatório, via Kong)
POST /api/games/search/reindex?recreate=<bool>                           (somente Admin)
```

| Parâmetro | Regra | Erro |
|---|---|---|
| `q` | obrigatório, 2–100 caracteres após `trim` | 400 |
| `genre` | opcional, até 100 caracteres, filtro exato sem diferenciar maiúsculas/acentos | 400 |
| `page` | ≥ 1 | 400 |
| `pageSize` | 1–50 (padrão 10) | 400 |
| janela | `page × pageSize ≤ 10.000` (`index.max_result_window`) | 400 |

Resposta (exemplo real do smoke local):

```json
{"query":"shadw realm","genre":null,"page":1,"pageSize":3,"total":1,"tookMs":6,
 "items":[{"id":"d23e4beb-…","title":"Shadow Realms","description":"Action adventure with dark fantasy.",
           "genre":"Action","price":149.90,"releaseDate":"2023-11-02T00:00:00","score":12.38581}]}
```

## Relevância e fuzzy search

- Consulta obrigatória: `multi_match` `best_fields` com `fuzziness: AUTO` (1 edição para termos de 3–5
  caracteres, 2 acima disso), `prefix_length: 1` (a primeira letra deve coincidir — reduz ruído) sobre
  `title^3`, `genre^2`, `description`.
- Reforços opcionais (`should`): frase exata no título (`boost 4`) e título exato via `title.keyword`
  normalizado (`boost 8`) ⇒ correspondências exatas ficam acima das aproximadas.
- Filtro: `isActive = true` (+ `genre.keyword` quando informado).
- Ordenação: `_score` decrescente, desempate por `title.keyword`.
- Análise: analisador `fcg_text` (`standard` + `lowercase` + `asciifolding`); normalizador
  `fcg_keyword` (`lowercase` + `asciifolding`) nos subcampos `keyword`.

## Sincronização do índice (sem transação distribuída)

```mermaid
sequenceDiagram
  participant Admin
  participant API as CatalogAPI
  participant PG as PostgreSQL
  participant ES as Elasticsearch
  participant Job as SearchIndexReconciler
  Admin->>API: POST/PUT/DELETE /api/games
  API->>PG: SaveChanges (commit)
  API->>ES: upsert documento (refresh=wait_for), best effort
  Note over API,ES: falha ⇒ log + métrica; a escrita já foi confirmada
  loop a cada ReconcileIntervalSeconds
    Job->>ES: índice existe? (cria se ausente ⇒ carga completa)
    Job->>PG: jogos com UpdatedAt ≥ última execução − sobreposição
    Job->>ES: bulk upsert
  end
```

| Situação | Comportamento |
|---|---|
| Inicialização (índice vazio/inexistente) | Reconciliação cria o índice com o mapeamento e faz **carga completa** |
| Criação/edição/remoção | Upsert logo após o commit; leitura imediata pelo próprio admin (`refresh=wait_for`) |
| Remoção | Lógica: documento atualizado com `isActive=false` e filtrado na busca |
| Elasticsearch fora do ar | Busca → **503** + `Retry-After: 10`; escritas → 2xx; reconciliação falha e **mantém** a marca d'água |
| Elasticsearch volta | Próxima reconciliação indexa tudo que mudou desde a última execução bem-sucedida |
| Índice perdido (dados apagados) | Reconciliação detecta, recria e recarrega tudo |
| Mudança de mapeamento | `POST /api/games/search/reindex?recreate=true` |
| Várias réplicas | Upserts idempotentes (id do documento = id do jogo); execução concorrente é segura |

**Janela de inconsistência**: no caso normal, zero (upsert síncrono após o commit). Em falha do
Elasticsearch, até `ReconcileIntervalSeconds` (30 s padrão; 15 s no Compose) após o retorno do serviço.

**Limitações conhecidas**: a reconciliação carrega em memória os jogos alterados (adequado ao tamanho do
catálogo; para catálogos grandes, paginar por `UpdatedAt`); sem *outbox* — uma mudança cujo upsert
falhou depende da reconciliação; `recreate=true` deixa a busca sem resultados durante a recarga
(segundos para o catálogo atual).

## Configuração

| Variável | Descrição | Compose | AKS |
|---|---|---|---|
| `Elasticsearch__Enabled` | habilita a busca | `true` | `true` |
| `Elasticsearch__Url` | endpoint | `http://elasticsearch:9200` | endpoint HTTPS do Elastic Cloud |
| `Elasticsearch__ApiKey` | API key (segredo) | — | Key Vault → arquivo montado |
| `Elasticsearch__IndexName` | índice | `fcg-games` | `fcg-games` |
| `Elasticsearch__ReconcileIntervalSeconds` | período da reconciliação | `15` | `30` |

## Observabilidade

| Métrica | Uso |
|---|---|
| `fcg_search_requests_total{outcome}` | `results`, `empty`, `invalid`, `unavailable` |
| `fcg_search_duration_seconds` | histograma do tempo de resposta do Elasticsearch |
| `fcg_search_index_operations_total{operation,result}` | `upsert`, `bulk`, `reconcile`, `reindex` × `success`/`failure` |

Logs: `Search index … created`, `full load: N games indexed`, `reconciled: N games changed since …`,
`Search index update deferred …` (falha de upsert), `Game search '…' returned N of M in X ms`.

## Como testar

```bash
# CatalogAPI — unitários e integração (Docker necessário para a integração)
dotnet test
dotnet test --filter "Category=Integration"

# Orquestração — stack completa + smoke pelo Kong (inclui queda e recuperação do Elasticsearch)
docker compose up -d --build
.\scripts\smoke-compose.ps1 -SearchOutage
```

## Elastic Cloud (nuvem)

1. Criar conta/trial em `cloud.elastic.co` e um deployment **Elasticsearch 9.x** hospedado na **Azure**
   (região próxima ao AKS, ex.: `eastus2`), tamanho mínimo.
2. Criar uma API key restrita ao índice `fcg-games` (privilégios `create_index`, `index`, `read`,
   `view_index_metadata`, `manage` no índice).
3. Gravar o endpoint (não sensível) na configuração do AKS e a API key no Key Vault
   (`catalog-elasticsearch-api-key`) — nunca no Git.
4. Validar com o smoke de nuvem (P4-M6). **Excluir o deployment ao final** (ver `DESTROY.md`).
