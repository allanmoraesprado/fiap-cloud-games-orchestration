# Guia — Azure Key Vault, Workload Identity e segredos em runtime

## Fluxo

```mermaid
sequenceDiagram
  participant TF as Terraform (operador)
  participant KV as Azure Key Vault (RBAC)
  participant Pod as Pod (ServiceAccount <workload>)
  participant CSI as Secrets Store CSI driver + provider Azure
  participant Entra as Microsoft Entra ID
  TF->>KV: segredos gerados (ephemeral random_password -> value_wo)
  TF->>Entra: UAMI por workload + credencial federada (system:serviceaccount:fcg:<workload>)
  TF->>KV: Key Vault Secrets User no escopo de CADA segredo
  Pod->>CSI: monta volume (SecretProviderClass <workload>-secrets)
  CSI->>Entra: token da ServiceAccount -> token Entra (Workload Identity)
  CSI->>KV: GET somente dos segredos listados
  CSI-->>Pod: arquivos em /mnt/secrets-store (um por chave)
  Pod->>Pod: APIs .NET: KeyPerFile (Jwt__SecretKey -> Jwt:SecretKey); Postgres/Mongo/Grafana: *_FILE; Redis: requirepass; Kong: init container renderiza kong.yml
```

## Decisões de segurança

- **Sem segredos no Git**: manifests de produção (`k8s/azure`) só contêm identificadores (client ids,
  nome do cofre) inseridos na renderização. Placeholders continuam apenas nos artefatos locais
  (`.env.example`, `k8s/shared-secret.yaml`, `appsettings*.json`).
- **Sem segredos no state do Terraform**: senhas geradas por recursos *ephemeral* e gravadas pelo argumento
  *write-only* `value_wo`; a API key do Elastic Cloud entra por variável *ephemeral* (`TF_VAR_elasticsearch_api_key`).
- **Sem objetos `Secret` do Kubernetes no AKS**: os arquivos montados pelo CSI ficam apenas no pod
  (tmpfs); nada é sincronizado para o etcd.
- **Privilégio mínimo**: cada identidade lê apenas seus segredos (role assignment no escopo do segredo);
  o Kong só lê `jwt-signing-key`; a Notifications Function não tem identidade (não precisa de segredo).
- **Falha rápida**: se `SecretsPath` estiver configurado e o diretório não existir, a API não sobe.
- **JWT**: chave HS256 aleatória de 64 caracteres, compartilhada entre UsersAPI (emissão), Kong (borda) e
  APIs (validação), a partir de um único segredo.
- **Kong em produção**: Admin API apenas em `127.0.0.1` (no modo DB-less, `POST /config` poderia trocar as
  rotas); somente o proxy é público; `externalTrafficPolicy: Local` preserva o IP do cliente para o rate
  limit sem confiar em `X-Forwarded-For`.

## Mapeamento segredo → arquivo

| Workload | Segredo no Key Vault | Arquivo (`objectAlias`) | Consumo |
|---|---|---|---|
| users-api | `jwt-signing-key`, `users-api-postgres-connection`, `users-admin-seed-password` | `Jwt__SecretKey`, `ConnectionStrings__Postgres`, `Seed__AdminPassword` | `KeyPerFile` |
| catalog-api | `jwt-signing-key`, `catalog-api-postgres-connection`, `catalog-api-redis-connection`, `catalog-elasticsearch-url`, `catalog-elasticsearch-api-key` | `Jwt__SecretKey`, `ConnectionStrings__Postgres`, `Redis__ConnectionString`, `Elasticsearch__Url`, `Elasticsearch__ApiKey` | `KeyPerFile` |
| payments-api | `jwt-signing-key`, `payments-api-mongo-connection` | `Jwt__SecretKey`, `Mongo__ConnectionString` | `KeyPerFile` |
| kong | `jwt-signing-key` | `jwt-signing-key` | init container (`sed` no `kong.yml`) |
| postgres / mongo / grafana | `postgres-admin-password` / `mongo-root-password` / `grafana-admin-password` | idem | `POSTGRES_PASSWORD_FILE` / `MONGO_INITDB_ROOT_PASSWORD_FILE` / `GF_SECURITY_ADMIN_PASSWORD__FILE` |
| redis | `redis-password` | idem | `--requirepass "$(cat …)"` |

## Execução local preservada

Sem `SecretsPath`, as APIs leem `appsettings*.json`/variáveis como na Fase 3 (Compose e k8s local
inalterados). O ensaio `scripts/azure/simulate-local.sh` reproduz o modelo de arquivos com um Secret local.

## Verificação no AKS (sem expor valores)

```bash
kubectl -n fcg exec deploy/catalog-api -- ls /mnt/secrets-store     # nomes dos arquivos
kubectl -n fcg get secrets                                          # nenhum segredo de aplicação
kubectl -n fcg get sa catalog-api -o jsonpath='{.metadata.annotations}'
az role assignment list --assignee <client-id-catalog> --all -o table   # escopos: segredos individuais
```
