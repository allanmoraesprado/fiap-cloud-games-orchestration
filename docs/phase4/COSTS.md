# Custos Estimados e Política de Infraestrutura Temporária

> Estimativas — **não são valores faturados**. Preços unitários consultados em 2026-11-17 na API pública
> **Azure Retail Prices** (`https://prices.azure.com/api/retail/prices`), região `eastus2`, pay-as-you-go, USD,
> sem impostos. Confirmar no Azure Pricing Calculator antes do provisionamento.

## Preços unitários consultados

| Recurso | SKU | Preço unitário | Fonte |
|---|---|---|---|
| Nó AKS (VM Linux) | `Standard_D4as_v5` (4 vCPU / 16 GiB) | US$ 0,172 / hora | Retail Prices API |
| Alternativa | `Standard_D2as_v5` (2 vCPU / 8 GiB) | US$ 0,086 / hora | Retail Prices API |
| Alternativa | `Standard_B2ms` (2 vCPU / 8 GiB, burstable) | US$ 0,0832 / hora | Retail Prices API |
| Plano de controle AKS | tier Free | US$ 0 | (Standard/Uptime SLA = US$ 0,10/h, não usado) |
| Disco do SO do nó | Premium SSD P6 (64 GiB) | US$ 9,28 / mês | Retail Prices API |
| PVCs (Postgres, Mongo, Kafka) | Standard SSD E2 (8 GiB) | US$ 0,60 / mês cada | Retail Prices API |
| IP público | Standard IPv4 estático | US$ 0,005 / hora | Retail Prices API |
| Load Balancer Standard | primeiras 5 regras | ≈ US$ 0,025 / hora | preço público de referência (não retornado pela API na consulta) |
| ACR | Basic | US$ 0,1666 / dia | Retail Prices API |
| Key Vault | Standard | US$ 0,03 / 10 mil operações | Retail Prices API |
| Elastic Cloud | deployment hospedado | trial gratuito (14 dias, conforme política vigente da Elastic) | confirmar no cadastro |

## Estimativa diária (ambiente ligado)

| Item | Cálculo | US$/dia |
|---|---|---|
| 1 × `Standard_D4as_v5` | 0,172 × 24 | 4,13 |
| Disco do SO P6 | 9,28 / 30 | 0,31 |
| 3 PVCs E2 | 3 × 0,60 / 30 | 0,06 |
| Load Balancer | ≈ 0,025 × 24 | ≈ 0,60 |
| 2 IPs públicos (saída do AKS + Kong) | 2 × 0,005 × 24 | 0,24 |
| ACR Basic | | 0,17 |
| Key Vault | operações | < 0,01 |
| **Total estimado** | | **≈ 5,5 / dia** |

- Semana de demonstração ligada 24 h: **≈ US$ 38**.
- Cluster parado (`az aks stop`): VM deixa de ser cobrada; continuam disco do SO, PVCs, IPs, LB e ACR ⇒ **≈ US$ 1,4/dia**.
- Egress: primeiros 100 GB/mês gratuitos — irrelevante para a demonstração.
- **Não habilitados** (evitam custo variável): Container Insights / Log Analytics, Defender for Containers,
  AKS Standard tier, NAT Gateway, Application Gateway.

## Cobranças que podem continuar após desligar/excluir o cluster

| Recurso | Por que continua | Como encerrar |
|---|---|---|
| Resource group de nós `MC_*` (discos, IPs, LB) | criado pelo AKS | é removido junto com o cluster; conferir no Portal |
| PVCs com `reclaimPolicy: Retain` | discos persistem | os manifests usam `Delete`; conferir discos órfãos |
| ACR, Key Vault | fora do cluster | `terraform destroy` ou exclusão do Resource Group |
| Key Vault (soft delete) | nome reservado por 7 dias, sem custo | `az keyvault purge` (opcional) |
| Elastic Cloud | serviço externo | excluir o deployment no console da Elastic |
| Budget/alertas | sem custo | removidos com o Resource Group |

## Controles

- Orçamento do Resource Group via Terraform (`azurerm_consumption_budget_resource_group`), padrão US$ 50, alertas
  em 50 %, 80 % e 100 % (e-mail informado pelo proprietário em `terraform.tfvars`, não versionado).
- Nenhum recurso pago é criado sem autorização explícita do proprietário para os recursos concretos e o custo acima.
- Destruição final é ação separada, confirmada pelo proprietário, após preservar evidências.
