# Documentação Interna - Lab Talos

Essa documentação contém as credenciais e endereçamentos da infraestrutura do laboratório baseada no Proxmox e Talos Linux.

## 🌐 Rede e Acessos

### Proxmox VE
- **Painel Web:** `https://192.168.1.100:8006/`
- **API Token (Terraform):** `terraform@pve!provider=<seu-token-aqui>`
- **Gateway da Rede:** `192.168.1.1`

### Cluster Talos (v1.13.2)
- **Endpoint da API do Kubernetes:** `https://192.168.1.50:6443`
- **Control Plane (`talos-cp` | VMID 800):** `192.168.1.50` 
- **Worker (`talos-worker` | VMID 801):** `192.168.1.51`
- **MetalLB (Load Balancers):** O range configurado para entregar os serviços externamente (Layer 2) é `192.168.1.221` até `192.168.1.229`.

## 💻 Especificações das Máquinas

Ambos os nós do cluster rodam com as mesmas configurações de hardware na bridge `vmbr0`:
- **CPU:** 2 vCores (tipo x86-64-v2-AES otimizado para K8s)
- **RAM:** 5.12 GB dedicados
- **Disco:** 50 GB (Local-LVM / Formato Raw) com suporte a TRIM/Discard ativado para otimização SSD.

## 📂 Arquivos Chave no Repositório

- **`talosconfig`**: Chave de acesso e configuração para gerenciar o Sistema Operacional dos nós usando a ferramenta `talosctl`.
- **`kubeconfig`**: Credencial gerada para interagir com o Kubernetes através do comando `kubectl`.
- **`terraform.tfvars`**: Onde o IP e Token de API do seu Proxmox estão armazenados e declarados para rodar a automação.
- **`cluster.tf`**: Onde as VMs estão declaradas e a versão do Talos está fixada (`local.talos_version = "v1.13.2"`).

## 💡 Dicas Úteis

1. **Gestão do SO:** Como o Talos é imutável, o acesso SSH não existe. Toda administração do sistema, coleta de logs das máquinas, ou reboots devem ser feitos usando `talosctl` (exemplo: `talosctl logs kubelet -n 192.168.1.50`).
2. **Atualização do Cluster:** Evite modificar os nós manualmente. Caso queira atualizar a versão do Talos no futuro, faça a alteração da variável no `cluster.tf`, baixe a nova imagem e utilize o processo de upgrade nativo da documentação do Talos Linux.
3. **Persistência de Load Balancer:** Se os seus serviços K8s (tipo LoadBalancer) pararem de pegar IPs da sua rede local (192.168.1.x), confira se os Manifests do MetalLB L2 (`metallb-l2-config.yaml`) foram devidamente aplicados no cluster.
