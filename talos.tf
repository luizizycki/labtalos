locals {
  cp_ip       = local.nodes["talos-cp"].ip
  worker_ip   = local.nodes["talos-worker"].ip
  cluster_ep  = "https://${local.nodes["talos-cp"].ip}:6443"
  gateway     = local.nodes["talos-cp"].gateway
  cidr_suffix = "/24"
}

# === 0. IMAGE FACTORY: GERA ISO COM QEMU-GUEST-AGENT ===
resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = [
          "siderolabs/qemu-guest-agent",
        ]
      }
    }
  })
}

data "talos_image_factory_urls" "this" {
  talos_version = local.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "nocloud"
}

# === 1. SEGREDOS DO CLUSTER (vai pro state) ===
resource "talos_machine_secrets" "this" {}

# === 2. TALOSCONFIG PRA CONECTAR NOS NÓS ===
data "talos_client_configuration" "this" {
  cluster_name         = "labtalos"
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [local.cp_ip, local.worker_ip]
  nodes                = [local.cp_ip, local.worker_ip]
}

# === 3. CONFIG DO CONTROL PLANE ===
data "talos_machine_configuration" "cp" {
  cluster_name     = "labtalos"
  machine_type     = "controlplane"
  cluster_endpoint = local.cluster_ep
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = local.talos_version
  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk  = "/dev/sda"
          image = data.talos_image_factory_urls.this.urls["installer"]
        }
        network = {
          interfaces = [{
            interface = "eth0"
            dhcp      = false
            addresses = ["${local.cp_ip}${local.cidr_suffix}"]
            routes = [{
              network = "0.0.0.0/0"
              gateway = local.gateway
            }]
          }]
          nameservers = ["1.1.1.1", "8.8.8.8"]
        }
        features = {
          diskQuotaSupport = true
          kubePrism = {
            enabled = true
            port    = 7445
          }
          hostDNS = {
            enabled              = true
            forwardKubeDNSToHost = true
          }
        }
        nodeLabels = {
          "node.kubernetes.io/exclude-from-external-load-balancers" = ""
        }
      }
      cluster = {
        proxy = {
          disabled = true
        }
        network = {
          cni = {
            name = "none"
          }
        }
        inlineManifests = [
          {
            name     = "cilium"
            contents = file("${path.module}/generated/cilium.yaml")
          }
        ]
        apiServer = {}
      }
    })
  ]
}

# === 4. CONFIG DO WORKER ===
data "talos_machine_configuration" "worker" {
  cluster_name     = "labtalos"
  machine_type     = "worker"
  cluster_endpoint = local.cluster_ep
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = local.talos_version
  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk  = "/dev/sda"
          image = data.talos_image_factory_urls.this.urls["installer"]
        }
        network = {
          interfaces = [{
            interface = "eth0"
            dhcp      = false
            addresses = ["${local.worker_ip}${local.cidr_suffix}"]
            routes = [{
              network = "0.0.0.0/0"
              gateway = local.gateway
            }]
          }]
          nameservers = ["1.1.1.1", "8.8.8.8"]
        }
        features = {
          diskQuotaSupport = true
          kubePrism = {
            enabled = true
            port    = 7445
          }
          hostDNS = {
            enabled              = true
            forwardKubeDNSToHost = true
          }
        }
      }
    })
  ]
}

# === 5. APLICA CONFIG NO CONTROL PLANE ===
resource "talos_machine_configuration_apply" "cp" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.cp.machine_configuration
  node                        = local.cp_ip
  depends_on = [
    resource.proxmox_virtual_environment_vm.talos_cluster
  ]
}

# === 6. APLICA CONFIG NO WORKER ===
resource "talos_machine_configuration_apply" "worker" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = local.worker_ip
  depends_on = [
    resource.proxmox_virtual_environment_vm.talos_cluster
  ]
}

# === 7. BOOTSTRAP DO ETCD ===
resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.cp_ip
  depends_on = [
    resource.talos_machine_configuration_apply.cp
  ]
}

# === 8. KUBECONFIG ===
resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.cp_ip
  depends_on = [
    resource.talos_machine_bootstrap.this
  ]
}

resource "local_file" "kubeconfig" {
  filename = "kubeconfig"
  content  = talos_cluster_kubeconfig.this.kubeconfig_raw
}

resource "local_file" "talosconfig" {
  filename = "talosconfig"
  content  = data.talos_client_configuration.this.talos_config
}
