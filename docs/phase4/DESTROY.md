# Guia de Destruição dos Recursos

> Ação **separada, controlada e confirmada pelo proprietário**. Execute somente depois de gravar o vídeo e
> preservar as evidências (prints do Portal, logs dos pipelines, saídas dos smoke tests em
> [TEST-EVIDENCE.md](TEST-EVIDENCE.md)).

## 1. Azure

```bash
az login
bash scripts/azure/destroy.sh        # pede para digitar o nome do resource group; executa terraform destroy
```

O script remove, via Terraform: AKS (e o resource group de nós com VM, discos, IPs e Load Balancer), ACR
(com todas as imagens), Key Vault (fica em *soft delete* por 7 dias, sem custo), identidades gerenciadas,
credenciais federadas, role assignments, VNet e orçamento. Ao final ele confere se os resource groups ainda
existem.

Verificações finais no Portal (Cost Management → recursos):

- [ ] `rg-fcg-demo` e `rg-fcg-demo-aks-nodes` não existem mais (`az group exists -n <nome>`).
- [ ] Nenhum disco gerenciado órfão (`az disk list --query "[?contains(name,'pvc')]" -o table`).
- [ ] Nenhum IP público órfão (`az network public-ip list -o table`).
- [ ] Key Vault em soft delete (opcional: `az keyvault purge -n <kv>` para liberar o nome).
- [ ] Custos do dia seguinte zerados no Cost Management.

Se o state local tiver se perdido, a remoção manual equivalente é `az group delete -n rg-fcg-demo --yes`
(o resource group de nós é removido junto com o cluster).

## 2. Elastic Cloud

- [ ] Console `cloud.elastic.co` → Deployments → deployment da demonstração → **Delete deployment**.
- [ ] Revogar a API key criada para a CatalogAPI (se o deployment não for excluído).
- [ ] Confirmar que nenhum faturamento ficou ativo após o término do trial.

## 3. GitHub

- [ ] `bash scripts/azure/github-variables.sh --disable` (define `AZURE_DEPLOY_ENABLED=false` nos 4 serviços) **antes**
      do destroy, para que pushes na `main` não tentem implantar em um ambiente inexistente. Alternativa manual:
      definir `AZURE_DEPLOY_ENABLED=false` (ou remover) nas variáveis dos repositórios para que pushes na
      `main` não tentem implantar em um ambiente inexistente. Os identificadores (client id, nomes) não são
      segredos, mas deixam de ter utilidade.

## 4. Estação local

- [ ] Apagar `infra/terraform/terraform.tfstate*`, `tfplan` e `terraform.tfvars` quando não forem mais necessários.
- [ ] `bash scripts/azure/simulate-local.sh down` (namespace `fcg-sim`, se usado).
- [ ] Apagar o kubeconfig dedicado `~/.kube/fcg-aks-demo`.
- [ ] A API key do Elastic Cloud em arquivo local é do proprietário: excluir o arquivo só por decisão dele.
