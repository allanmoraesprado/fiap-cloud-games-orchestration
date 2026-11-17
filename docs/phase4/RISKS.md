# Riscos — Fase 4

| ID | Risco | Prob. | Impacto | Mitigação | Estado |
|---|---|---|---|---|---|
| K01 | **Assinatura Azure inutilizável**: `az account show` retorna `state: Warned`; ARM responde `SubscriptionNotFound` e lista vazia de assinaturas (2026-11-17). Típico de trial expirado ou pagamento pendente | Confirmado | Alto — bloqueia M5/M6 e validação real de M3/M4 | Proprietário deve reativar/converter a assinatura (pay-as-you-go) ou fornecer outra; trabalho local segue | **ABERTO** |
| K02 | Cota de vCPU regional/família (`DASv5`) baixa em assinaturas novas | Média | Médio | `az vm list-usage -l eastus2`; tamanho do nó é variável (`D2as_v5`, `B2ms`) | Aberto |
| K03 | Trial do Elastic Cloud expira (14 dias) antes da gravação | Média | Médio | Criar o deployment só perto do M5; registrar data de expiração; excluir ao final | Aberto |
| K04 | Kong OSS não resolve vault em `jwt_secrets` | Confirmado | Baixo | `kong.yml` renderizado em init container a partir do segredo montado | Mitigado no design |
| K05 | Estado do Terraform contém segredos gerados | Certa | Médio | Estado local fora do Git (`.gitignore`), apagado após `destroy` | Mitigado no design |
| K06 | Recursos esquecidos ligados | Média | Alto | Budget + alertas; `DESTROY.md`; checklist final | Aberto |
| K07 | Workflows reutilizáveis referenciados por `@main` mudam o comportamento de todos os serviços | Baixa | Médio | Mudanças no workflow validadas por um serviço antes; opção de fixar por SHA | Aceito |
| K08 | Configurar variáveis/segredos do GitHub exige acesso do proprietário (sem `gh` autenticado) | Certa | Médio | Script `configure-github.ps1` + instruções; CD condicionado a `AZURE_DEPLOY_ENABLED` | Aberto |
| K09 | Vulnerabilidade CRITICAL em imagem base reprova o pipeline | Baixa | Médio | Atualizar imagem/pacotes; `ignore-unfixed` | Aceito |
| K10 | Memória insuficiente no Docker Desktop com Elasticsearch + stack completa | Média | Baixo | Heap do ES 512 MB; ES opcional nos testes de integração (Testcontainers) | Mitigado |
| K11 | Kafka single-broker no AKS perde offsets em reinício sem volume | Média | Médio | StatefulSet com PVC | Mitigado no design |
| K12 | Divergência entre índice e banco após falha do ES | Média | Baixo | Reconciliação periódica + reindexação manual; métricas de falha | Mitigado no design |
| K13 | Contas locais do AKS desabilitadas exigem `kubelogin` | Certa | Baixo | `az aks install-cli`; `azure/use-kubelogin` no pipeline | Mitigado |
