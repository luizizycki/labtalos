locals {
  # Variável para atualizar o Talos no futuro trocando num lugar só
  talos_version = "v1.13.2"

  # Nosso "Banco de Dados" de máquinas
  nodes = {
    "talos-cp" = {
      vmid = 800
      cpu  = 2
      ram  = 5120
    }
    "talos-worker" = {
      vmid = 801
      cpu  = 2
      ram  = 5120
    }
  }
}

# 1. Faz o download automático da ISO direto do GitHub pro seu Proxmox
resource "proxmox_download_file" "talos_iso" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = "proxmox" # Mude se o nome do seu node no Proxmox não for 'pve'
  url          = "https://github.com/siderolabs/talos/releases/download/${local.talos_version}/metal-amd64.iso"
  file_name    = "talos-${local.talos_version}-amd64.iso"
}

# 2. Cria as VMs lendo dinamicamente a tabela "nodes" lá do topo
resource "proxmox_virtual_environment_vm" "talos_cluster" {
  for_each = local.nodes

  name      = each.key        # Nome = "talos-cp" e depois "talos-worker"
  node_name = "proxmox"       # Nome do nó no Proxmox
  vm_id     = each.value.vmid # Puxa o 800 e depois o 801
  started   = true            # Já liga a máquina assim que criar

  cpu {
    cores = each.value.cpu
    type  = "x86-64-v2-AES" # Otimizado para K8s
  }

  memory {
    dedicated = each.value.ram
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 50
    file_format  = "raw"
    discard      = "on" # Essencial para SSDs não morrerem cedo (TRIM)
  }

  cdrom {
    enabled   = true
    file_id   = proxmox_download_file.talos_iso.id
    interface = "ide3"
  }

  network_device {
    bridge = "vmbr0" # A bridge que conecta no seu roteador físico
  }

  # Tenta dar boot no disco. Se falhar (disco zerado), usa o CD do Talos
  boot_order = ["scsi0", "ide3"]

  operating_system {
    type = "l26" # Kernel Linux genérico
  }

  agent {
    enabled = false # evitar deadlock
  }
}
