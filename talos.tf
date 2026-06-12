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

# === 9. BOOTSTRAP DO ARGOCD + APPLICATIONS ===
resource "null_resource" "bootstrap" {
  depends_on = [local_file.kubeconfig]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = "${path.module}/kubeconfig"
      CWD        = path.module
    }
    command = <<-EOT
      set -eux

      K=$(echo "$KUBECONFIG" | tr -d '\r')
      CWD=$(echo "$CWD" | tr -d '\r')

      # Aguarda o cluster ficar responsivo
      echo "Aguardando cluster..."
      for i in $(seq 1 30); do
        if kubectl --kubeconfig "$K" get nodes &>/dev/null; then
          echo "Cluster pronto"
          break
        fi
        if [ "$i" -eq 30 ]; then
          echo "Cluster nao respondeu apos 5min"
          exit 1
        fi
        sleep 10
      done

      # Aplica as CRDs do Gateway API antes do Cilium/ArgoCD para evitar race conditions
      echo "Aplicando CRDs do Gateway API (Server-Side Apply)..."
      kubectl --kubeconfig "$K" apply --server-side -f "$CWD/crds/gateway-api/"

      # Aguarda Cilium ficar pronto (CNI)
      echo "Aguardando Cilium..."
      kubectl --kubeconfig "$K" wait --for=condition=Available -n kube-system deployment/cilium-operator --timeout=180s
      kubectl --kubeconfig "$K" wait --for=condition=Ready -n kube-system pod -l k8s-app=cilium --timeout=180s

      # Reinicia o Cilium Operator para registrar o Gateway API controller caso ele tenha subido antes do CRD
      echo "Reiniciando Cilium Operator para registrar Gateway API..."
      kubectl --kubeconfig "$K" rollout restart deployment/cilium-operator -n kube-system
      kubectl --kubeconfig "$K" rollout status deployment/cilium-operator -n kube-system --timeout=180s

      # Adiciona repo Helm do ArgoCD
      helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
      helm repo update argo 2>/dev/null || true

      # Monta args de values (argocd.local.yaml é opcional)
      VALUES_HELM="$CWD/helm-values/argocd.yaml"
      VALUES_LOCAL="$CWD/helm-values/argocd.local.yaml"
      VALUES_ARGS="--values $VALUES_HELM"
      if [ -f "$VALUES_LOCAL" ]; then
        VALUES_ARGS="$VALUES_ARGS --values $VALUES_LOCAL"
      fi

      # Instala ArgoCD via Helm
      echo "Instalando ArgoCD..."
      helm upgrade --install argocd argo/argo-cd \
        --kubeconfig "$K" \
        --namespace argocd --create-namespace \
        --version 9.5.17 \
        $VALUES_ARGS \
        --wait \
        --timeout 5m

      # Aguarda ArgoCD server ficar pronto
      echo "Aguardando ArgoCD server..."
      kubectl --kubeconfig "$K" wait --for=condition=Available -n argocd deployment/argocd-server --timeout=180s

      # Aplica bootstrap Application
      echo "Aplicando bootstrap Application..."
      kubectl --kubeconfig "$K" apply -f "$CWD/apps/bootstrap-app.yaml"

      echo "Bootstrap concluido! ArgoCD esta sincronizando as Applications do Git."
    EOT
  }
}

output "kubeconfig_raw" {
  value     = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive = true
}
