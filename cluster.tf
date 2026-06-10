locals {
  talos_version = "v1.13.2"

  nodes = {
    "talos-cp" = {
      vmid    = 800
      cpu     = 2
      ram     = 5120
      ip      = "192.168.1.50"
      gateway = "192.168.1.1"
      cidr    = "/24"
    }
    "talos-worker" = {
      vmid    = 801
      cpu     = 2
      ram     = 5120
      ip      = "192.168.1.51"
      gateway = "192.168.1.1"
      cidr    = "/24"
    }
  }
}

resource "proxmox_download_file" "talos_iso" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = "proxmox"
  url          = data.talos_image_factory_urls.this.urls["iso"]
  file_name    = "talos-nocloud-${local.talos_version}-${talos_image_factory_schematic.this.id}.iso"
  overwrite    = true
  overwrite_unmanaged = true
}

resource "proxmox_virtual_environment_vm" "talos_cluster" {
  for_each = local.nodes

  name      = each.key
  node_name = "proxmox"
  vm_id     = each.value.vmid
  started   = true

  cpu {
    cores = each.value.cpu
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.ram
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 50
    file_format  = "raw"
    discard      = "on"
  }

  cdrom {
    file_id   = proxmox_download_file.talos_iso.id
    interface = "ide3"
  }

  network_device {
    bridge = "vmbr0"
  }

  boot_order = ["scsi0", "ide3"]

  agent {
    enabled = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${each.value.ip}${each.value.cidr}"
        gateway = each.value.gateway
      }
    }
  }
}
