# Guia de Provisionamento — Azure (AKS, ACR, Key Vault)

> **Gera custos.** Execute somente após aprovar a estimativa de [COSTS.md](COSTS.md). Tudo é criado em
> `eastus2` (padrão) em dois resource groups: `rg-fcg-<env>` e `rg-fcg-<env>-aks-nodes`.

## 1. O que é criado (infra/terraform)

| Arquivo | Recursos |
|---|---|
| `main.tf` | Resource Group, sufixo aleatório para nomes globais, tags padrão (`project`, `phase`, `environment`, `managed-by`, `cost-policy`) |
| `network.tf` | VNet `10.20.0.0/16` e subnet dos nós `10.20.0.0/22` (pods em Azure CNI Overlay `192.168.0.0/16`) |
| `aks.tf` | AKS tier Free, 1 nó `Standard_D4as_v5`, OIDC issuer + **Workload Identity**, **Entra ID + Azure RBAC** (contas locais desabilitadas), add-on **Key Vault Secrets Provider** (CSI), identidade de control plane com `Network Contributor` na subnet; o operador recebe `Azure Kubernetes Service RBAC Cluster Admin` |
| `acr.tf` | ACR **Basic privado** (sem admin user, sem pull anônimo); kubelet com `AcrPull` |
| `keyvault.tf` | Key Vault em modo **RBAC**, soft delete 7 dias; segredos gerados com `ephemeral "random_password"` e gravados via **`value_wo` (write-only)** — **nenhum segredo fica no state/plan do Terraform** |
| `identities.tf` | 8 identidades gerenciadas (uma por workload) com credencial federada para a ServiceAccount correspondente e `Key Vault Secrets User` **por segredo** |
| `github.tf` | Identidade de deploy para GitHub Actions (OIDC, somente branch `main` dos repositórios de serviço): `AcrPush`, `AKS Cluster User Role`, `AKS RBAC Writer` no namespace `fcg` |
| `budget.tf` | Orçamento mensal com alertas 50 % / 80 % (real) e 100 % (previsto), filtrado aos dois resource groups |

Segredos no Key Vault:

| Segredo | Origem | Consumidores |
|---|---|---|
| `jwt-signing-key` | gerado (64 caracteres) | UsersAPI, CatalogAPI, PaymentsAPI, Kong |
| `postgres-admin-password`, `mongo-root-password`, `redis-password`, `grafana-admin-password` | gerados | PostgreSQL, MongoDB, Redis, Grafana |
| `users-api-postgres-connection`, `catalog-api-postgres-connection`, `catalog-api-redis-connection`, `payments-api-mongo-connection` | derivados das senhas acima na mesma execução | APIs |
| `users-admin-seed-password` | gerado | UsersAPI (administrador semeado) |
| `catalog-elasticsearch-url`, `catalog-elasticsearch-api-key` | informados pelo proprietário (Elastic Cloud) | CatalogAPI |

Rotação: incremente `secrets_version` (todos os gerados juntos) ou `elasticsearch_secret_version` e rode
`terraform apply`; depois reinicie os pods (`kubectl -n fcg rollout restart deploy,statefulset`).

## 2. Pré-requisitos

1. Assinatura Azure **Enabled** (não `Warned`/`Disabled`) com papel **Owner** (ou Contributor + User Access
   Administrator) para o operador.
2. Ferramentas: Azure CLI, Terraform ≥ 1.11 (`winget install Hashicorp.Terraform`), kubectl + kubelogin
   (`az aks install-cli`), Node.js, Git Bash (Windows).
3. Elastic Cloud: deployment Elasticsearch 9.x criado (ver [ELASTICSEARCH.md](ELASTICSEARCH.md)), endpoint
   HTTPS e API key em mãos.
4. Autorização explícita do custo estimado.

## 3. Passo a passo

```bash
# 0) sessão e verificações somente leitura (estado da assinatura, permissões, providers, cota de vCPU)
az login
bash scripts/azure/preflight.sh <subscription-id> eastus2 Standard_D4as_v5

# 1) variáveis do ambiente (arquivo não versionado)
cp infra/terraform/environments/demo.tfvars.example infra/terraform/terraform.tfvars
#    edite subscription_id, budget_contact_emails, elasticsearch_url

# 2) plano e aplicação (a API key do Elastic Cloud só passa por variável de ambiente)
export TF_VAR_elasticsearch_api_key='<api-key-base64>'
terraform -chdir=infra/terraform init
terraform -chdir=infra/terraform plan -out tfplan
terraform -chdir=infra/terraform apply tfplan          # ~10-15 min (AKS)
unset TF_VAR_elasticsearch_api_key

# 3) camada de plataforma no AKS (namespace, identidades, SecretProviderClasses, dados, Kong, observabilidade)
bash scripts/azure/deploy-platform.sh

# 4) variáveis dos repositórios no GitHub (identificadores, não segredos) e primeiro deploy das aplicações
bash scripts/azure/github-variables.sh            # imprime/aplica AZURE_CLIENT_ID, ACR_NAME, ...
#    em seguida: push na main de cada serviço (CD) ou "Run workflow" manual

# 5) validação ponta a ponta pelo gateway público (PowerShell; senha do admin lida do Key Vault)
#    $admin = az keyvault secret show --vault-name <kv> -n users-admin-seed-password --query value -o tsv
#    .\scripts\smoke-compose.ps1 -GatewayUrl http://<label>.eastus2.cloudapp.azure.com -AdminPassword $admin -SkipPrometheus -SkipLoki
```

## 4. Validação

| Verificação | Comando |
|---|---|
| Nós e pods | `kubectl get nodes; kubectl -n fcg get pods,svc,pvc` |
| Segredos montados (sem exibir valores) | `kubectl -n fcg exec deploy/catalog-api -- ls /mnt/secrets-store` |
| Nenhum Secret Kubernetes com credenciais | `kubectl -n fcg get secrets` (somente tokens de sistema, se houver) |
| Gateway público | `curl -i http://<label>.eastus2.cloudapp.azure.com/api/games` → 401 |
| Imagens no ACR | `az acr repository show-tags -n <acr> --repository fcg-catalog-api -o table` |
| Senha do admin semeado (operador) | `az keyvault secret show --vault-name <kv> -n users-admin-seed-password --query value -o tsv` |

## 5. Ensaio local dos manifests (sem Azure)

`bash scripts/azure/simulate-local.sh up --apps` aplica os mesmos manifests de `k8s/azure` no Kubernetes do
Docker Desktop (namespace `fcg-sim`), trocando apenas o volume CSI do Key Vault por um Secret local,
`managed-csi` por `hostpath`, o LoadBalancer por NodePort 30180 e as imagens do ACR por imagens locais.
`bash scripts/azure/simulate-local.sh down` remove tudo. `bash scripts/azure/validate-manifests.sh` faz a
validação estática (kubeconform, incluindo o CRD `SecretProviderClass`).
