# Registro de Decisões Técnicas — Fase 4

Formato: contexto → decisão → consequências. Decisões podem ser revistas; a revisão fica registrada.

## D01 — Região Azure: `eastus2`
- **Contexto**: ambiente temporário de demonstração; custo é prioritário. Preços da API pública Azure Retail
  Prices (2026-11-17): `Standard_D4as_v5` US$ 0,172/h em `eastus2` × US$ 0,276/h em `brazilsouth`.
- **Decisão**: `eastus2` como padrão (variável `location`). Elastic Cloud na mesma região Azure quando disponível.
- **Consequências**: latência maior a partir do Brasil, irrelevante para a demonstração.

## D02 — Serviços de dados no cluster (PostgreSQL, Kafka, Redis, MongoDB)
- **Contexto**: o enunciado exige AKS, ACR, Key Vault e Elasticsearch gerenciado (Elastic Cloud); não exige
  PostgreSQL/Kafka/Redis/MongoDB gerenciados. Serviços gerenciados equivalentes (Azure Database for PostgreSQL,
  Event Hubs Standard, Azure Cache for Redis, Cosmos DB) somariam custo fixo e tempo de integração.
- **Decisão**: reutilizar as imagens da Fase 3 como StatefulSets com PVC (`managed-csi`) no AKS.
- **Consequências**: sem HA/backup gerenciado (aceitável para ambiente temporário); contratos e código preservados.

## D03 — Elasticsearch: 9.5.x local e Elastic Cloud na nuvem
- **Decisão**: cliente oficial `Elastic.Clients.Elasticsearch` 9.5.x (suporta `net8.0`); imagem
  `docker.elastic.co/elasticsearch/elasticsearch:9.5.x` single-node, sem segurança, heap 512 MB **somente** no
  Compose; Elastic Cloud (deployment hospedado na Azure, autenticação por **API key**) na nuvem.
- **Consequências**: mesma versão maior em dev e cloud; API key fica no Key Vault.

## D04 — Sincronização PostgreSQL → Elasticsearch sem transação distribuída
- **Decisão**:
  1. PostgreSQL é a fonte da verdade; a escrita é confirmada no banco primeiro.
  2. Após o commit, o documento é indexado de forma **best-effort** (falha ⇒ log + métrica, a requisição de escrita não falha).
  3. Um **serviço de reconciliação** em segundo plano reindexa jogos com `UpdatedAt` posterior à última marca
     d'água bem-sucedida (com sobreposição de segurança). Na inicialização a marca é vazia ⇒ **indexação inicial completa**.
  4. **Reindexação completa** sob demanda: `POST /api/games/search/reindex` (Admin), opcionalmente recriando o índice.
  5. Exclusão é lógica (`IsActive=false`): o documento é atualizado e filtrado na busca.
- **Consequências**: consistência eventual limitada pelo intervalo de reconciliação; upserts idempotentes
  (id do documento = id do jogo) tornam seguras múltiplas réplicas e reprocessamentos.

## D05 — Indisponibilidade do Elasticsearch
- **Decisão**: busca responde **503** com `Retry-After` e corpo JSON padrão; `/health` não depende do
  Elasticsearch (uma falha do serviço de busca não derruba o catálogo); escritas seguem funcionando e são
  recuperadas pela reconciliação. Sem fallback para SQL (a busca deve ser independente do relacional).

## D06 — Terraform com estado local
- **Decisão**: Terraform (`azurerm` ~> 4.x, `random`) em `infra/terraform`, estado **local** no computador do
  proprietário, ignorado pelo Git; todos os recursos em um único Resource Group.
- **Consequências**: o estado contém segredos gerados ⇒ não versionar, apagar após `destroy`. Backend remoto
  `azurerm` documentado como opção.

## D07 — AKS
- **Decisão**: tier Free; 1 nó `Standard_D4as_v5` (variável); Azure CNI Overlay; OIDC issuer + Workload Identity;
  add-on Key Vault Secrets Provider; Entra ID gerenciado com **Azure RBAC para Kubernetes**; contas locais
  desabilitadas; sem Container Insights (observabilidade própria com Prometheus/Loki).
- **Consequências**: acesso via `kubelogin`; permissões de deploy restritas ao namespace `fcg`.

## D08 — Injeção de segredos: Key Vault + Secrets Store CSI Driver (arquivos)
- **Decisão**: cada workload monta seus segredos como arquivos via `SecretProviderClass` autenticada por
  Workload Identity. APIs .NET leem com o provedor `KeyPerFile` (`Jwt__SecretKey` ⇒ `Jwt:SecretKey`);
  PostgreSQL/MongoDB/Grafana usam variáveis `*_FILE`; Redis lê a senha do arquivo; Kong renderiza `kong.yml`
  em um init container. **Nenhum objeto `Secret` do Kubernetes com credenciais no ambiente Azure.**
- **Consequências**: rotação exige reinício (ou `reloadOnChange`); execução local continua com placeholders.

## D09 — Identidades por workload e privilégio mínimo
- **Decisão**: uma identidade gerenciada (UAMI) por workload com credencial federada para sua ServiceAccount;
  papel `Key Vault Secrets User` atribuído **por segredo** (escopo do segredo, não do cofre).

## D10 — GitHub OIDC
- **Decisão**: UAMI `id-fcg-<env>-github` com credenciais federadas `repo:<owner>/<repo>:ref:refs/heads/main`
  para os repositórios com deploy; papéis `AcrPush` (ACR), `Azure Kubernetes Service Cluster User Role` e
  `Azure Kubernetes Service RBAC Writer` no namespace `fcg`. Sem segredos de cliente no GitHub.
- **Consequências**: pull requests não obtêm token Azure (sujeito diferente), reforçando "sem deploy em PR".

## D11 — CI/CD com workflows reutilizáveis
- **Decisão**: workflows `workflow_call` no repositório de orquestração; cada serviço tem um chamador fino.
  CI em PR e push; CD só em push na `main` **e** quando a variável de repositório `AZURE_DEPLOY_ENABLED == 'true'`
  (evita falhas enquanto o ambiente não existe). Tag de imagem = SHA completo; nenhuma tag `latest`.
  Manifests de workload renderizados com `envsubst` (lista explícita de variáveis).
- **Consequências**: mudanças no workflow reutilizável afetam todos os serviços (referência `@main`).

## D12 — Security scan
- **Decisão**: Trivy na imagem construída, falhando em vulnerabilidades `CRITICAL` com correção disponível.

## D13 — Exposição de rede
- **Decisão**: somente o proxy do Kong é público (Service `LoadBalancer`). Admin API do Kong, Prometheus,
  Grafana e bancos ficam internos (acesso por `kubectl port-forward`).

## D14 — Observabilidade no AKS
- **Decisão**: Prometheus com descoberta de pods (`kubernetes_sd_configs`, RBAC mínimo de leitura); Loki
  single-binary; Alloy como DaemonSet lendo logs dos pods via API do Kubernetes; Grafana provisionado com os
  mesmos dashboards da Fase 3.

## D15 — Notifications Function no AKS
- **Decisão**: manter o container do host Azure Functions (isolated) no AKS consumindo o Kafka interno, como na
  Fase 3. Function App gerenciada exigiria expor o Kafka do cluster com SASL/TLS e plano Premium/Flex.

## D16 — Rastreabilidade de versão
- **Decisão**: `APP_VERSION` (SHA) injetado no build da imagem; APIs devolvem `X-App-Version`; Deployment recebe
  label `app.kubernetes.io/version` e anotação `kubernetes.io/change-cause`.

## D17 — Testes de integração com Testcontainers
- **Decisão**: testes de integração do Elasticsearch usam Testcontainers (Elasticsearch real em container),
  executados localmente e no CI (runners Linux do GitHub possuem Docker). Categoria `Integration` para filtro.
