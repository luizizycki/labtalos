# Ocilab

Um cluster Kubernetes rodando Talos Linux no Proxmox, tudo provisionado com Terraform e gerenciado via GitOps com ArgoCD.

## Como funciona

| Peça | O quê |
|---|---|
| **Servidor** | Proxmox num i5-4570T, 16GB RAM, SSD 240GB — o cérebro da operação |
| **Armazenamento** | Backblaze B2 (S3) via Nextcloud |
| **Cluster** | Talos Linux + Kubernetes, 2 nós (control plane + worker) |
| **Infra como código** | Terraform com provider Proxmox — `terraform apply` e pronto |
| **GitOps** | ArgoCD em auto-sync: empurrou no git, foi pro cluster |
| **Rede externa** | VPS na Oracle Cloud (OCI) fazendo de gateway. WireGuard do homelab até a nuvem, HAProxy repassando TCP pro K8s. tudo pra furar o CGNAT da operadora |

## Bootstrap

Só isso:

```bash
cp terraform.tfvars.example terraform.tfvars          # bota os secrets
cp helm-values/argocd.local.yaml.example \
   helm-values/argocd.local.yaml                      # configura SSO do GitHub
terraform apply                                        # e vai tomar um café
```

Em uns 12 minutos o cluster sobe com certificado Let's Encrypt válido. Zero intervenção manual.

## GitOps Flow

```
git add . && git commit -m "bati o layout" && git push
```

ArgoCD sincroniza sozinho. Se alguém mexer no cluster na mão, ele volta ao que tá no git na próxima reconciliação.

## Estrutura

```
.
├── apps/            # app-of-apps + aplicações (cert-manager, gateway-api, etc.)
├── helm-values/     # values dos Helm charts
├── generated/       # manifests gerados (Cilium)
├── cluster.tf       # config das VMs
├── talos.tf         # bootstrap + inline manifests
├── provider.tf      # provider Proxmox
└── variables.tf     # variáveis do Terraform
```

## Versões

| Componente | Versão |
|---|---|
| Talos | v1.13.2 |
| Kubernetes | v1.36.0 |
| Cilium | v1.17.2 |
| ArgoCD | v3.4.3 |
| Gateway API | v1.2.1 |
| cert-manager | v1.18.2 |

## O que já roda

- [x] Cluster Talos (control plane + worker)
- [x] Roteamento externo (WireGuard + HAProxy via OCI)
- [x] TLS automático com Let's Encrypt
- [x] Gateway API + Cilium como ingress controller
- [x] Nextcloud + Backblaze B2
- [ ] Monitoramento (Grafana + Prometheus) — em breve
