# Lab Talos

Cluster Kubernetes Talos + GitOps via ArgoCD.

Este repositório implementa um deploy **zero-touch** completo: do provisionamento de VMs no Proxmox à configuração e sincronização de aplicativos de infraestrutura via ArgoCD.

## Pré-requisitos

Antes de iniciar, garanta que você possui as seguintes ferramentas instaladas localmente (onde o Terraform será executado):

1. **Dependências Obrigatórias**:
   * `terraform` (v1.5.0+)
   * `kubectl` (v1.28+)
   * `helm` (v3.0+)
2. **Dependência Opcional**:
   * `talosctl` (para interagir diretamente com o sistema operacional Talos)

Você pode verificar as dependências rodando o script:
```bash
./scripts/check-deps.sh
```

## Configuração Inicial

### 1. Variáveis do Terraform
Copie o arquivo de exemplo de variáveis e configure com suas credenciais do Proxmox:
```bash
cp terraform.tfvars.example terraform.tfvars
# Edite terraform.tfvars com suas configurações
```

### 2. Configurações Locais do ArgoCD (SSO)
O ArgoCD utiliza autenticação via GitHub (Dex). Por motivos de segurança, a chave privada (`clientSecret`) deve ser mantida localmente e não versionada no Git.

Copie o arquivo de exemplo de values locais e insira seu `clientSecret` real:
```bash
cp helm-values/argocd.local.yaml.example helm-values/argocd.local.yaml
# Insira seu clientSecret real no arquivo helm-values/argocd.local.yaml
```

*Nota: O arquivo `argocd.local.yaml` é ignorado pelo Git (configurado no `.gitignore`) para evitar vazamento acidental de credenciais.*

## Deploy

Com as dependências instaladas e as variáveis configuradas, o deploy é totalmente automatizado:

```bash
terraform init
terraform apply
```

O Terraform realizará os seguintes passos automaticamente:
1. Criará as VMs no Proxmox e instalará o Talos OS.
2. Aguardará o cluster ficar responsivo.
3. Aplicará as CRDs oficiais do **Gateway API**.
4. Reiniciará o **Cilium Operator** para registrar automaticamente o controlador de Gateway API.
5. Instalará o **ArgoCD** utilizando as configurações padrão (`argocd.yaml`) mescladas com seus segredos locais (`argocd.local.yaml`).
6. Aplicará a Application raiz (`bootstrap-app.yaml`), que instruirá o ArgoCD a assumir o controle do cluster e sincronizar todos os workloads.

## GitOps Flow

Uma vez finalizado o apply do Terraform, toda mudança na infraestrutura ou nos workloads deve ser feita declarativamente via Git.

Para atualizar o cluster:
1. Altere os manifestos correspondentes na pasta `apps/`.
2. Commit e Push para a branch `main`:
   ```bash
   git add .
   git commit -m "feat: atualiza config"
   git push origin main
   ```
3. O ArgoCD detectará o drift no Git e sincronizará automaticamente.

## Estrutura do Repositório

* `apps/` - Definições de Applications do ArgoCD e seus recursos
* `crds/` - Custom Resource Definitions aplicadas no bootstrap
* `generated/` - Manifestos gerados automaticamente (como `cilium.yaml`)
* `helm-values/` - Arquivos de configuração dos charts Helm (incluindo `argocd.local.yaml` para segredos)
* `scripts/` - Scripts de validação e geração de código
* `*.tf` - Código Terraform para infraestrutura e bootstrap

## Versões dos Componentes

| Componente | Versão |
|---|---|
| Talos | v1.13.2 |
| Kubernetes | v1.34.1 |
| Cilium | v1.17.2 |
| ArgoCD | v3.4.3 (chart: argo-cd 9.5.17) |
| Gateway API | v1.2.x |
