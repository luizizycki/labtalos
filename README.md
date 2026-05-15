# ocilab

cluster kubernetes bare-metal rodando talos linux no proxmox, provisionado 100% com terraform.
armazenamento de arquivos no backblaze b2 (s3) via nextcloud.

## arquitetura

- **processamento**: proxmox local (i5-4570T, 16gb ram, ssd 240gb)
- **armazenamento**: backblaze b2 (object storage s3)
- **orquestração**: talos linux + kubernetes (2 nós)
- **infra como código**: terraform (provider proxmox)
- **rede (exposição externa)**: vps oracle cloud (oci) atuando como gateway. túnel reverso via wireguard interligando a nuvem ao homelab (lxc no proxmox). haproxy fazendo o repasse tcp (camada 4) para o k8s, contornando cgnat e bloqueios de operadora.

## estrutura

```
.
├── terraform/     # provisionamento das vms no proxmox
└── kubernetes/    # manifests e configurações do cluster
```

## status

- [x] terraform pro proxmox
- [x] cluster talos (control plane + worker)
- [x] roteamento externo (wireguard + haproxy via oci)
- [ ] gateway api / ingress controller
- [ ] nextcloud + backblaze b2
- [ ] monitoramento (grafana + prometheus)
