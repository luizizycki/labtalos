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
        sysctls = {
          "net.core.rmem_max"               = "16777216"
          "net.core.wmem_max"               = "16777216"
          "net.ipv4.tcp_rmem"               = "4096 87380 16777216"
          "net.ipv4.tcp_wmem"               = "4096 65536 16777216"
          "net.ipv4.tcp_congestion_control" = "bbr"
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
        sysctls = {
          "net.core.rmem_max"               = "16777216"
          "net.core.wmem_max"               = "16777216"
          "net.ipv4.tcp_rmem"               = "4096 87380 16777216"
          "net.ipv4.tcp_wmem"               = "4096 65536 16777216"
          "net.ipv4.tcp_congestion_control" = "bbr"
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

# === 8.5. BUSCA KEY DO SOPS NO BITWARDEN ===
data "external" "sops_age_key" {
  program = ["bash", "-c", <<-EOT
    bw get item sops-age-key 2>/dev/null \
      | jq -r '.notes' \
      | jq -Rs '{key: .}'
  EOT
  ]
}

# === 9. BOOTSTRAP DO ARGOCD + APPLICATIONS ===
resource "null_resource" "bootstrap" {
  depends_on = [local_file.kubeconfig]

  triggers = {
    talos_tf_md5       = filemd5("${path.module}/talos.tf")
    argocd_values_md5  = filemd5("${path.module}/helm-values/argocd.yaml")
    bootstrap_app_md5  = filemd5("${path.module}/apps/bootstrap-app.yaml")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = "${path.module}/kubeconfig"
      CWD        = path.module
      SOPS_KEY   = data.external.sops_age_key.result.key
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

      # Aplica as CRDs do Gateway API (via URL oficial) antes do ArgoCD
      echo "Aplicando CRDs do Gateway API..."
      kubectl --kubeconfig "$K" apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/experimental-install.yaml

      # Aguarda Cilium ficar pronto (CNI)
      echo "Aguardando criacao dos recursos do Cilium..."
      for i in $(seq 1 30); do
        if kubectl --kubeconfig "$K" get deployment -n kube-system cilium-operator &>/dev/null && \
           [ "$(kubectl --kubeconfig "$K" get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | wc -w)" -gt 0 ]; then
          echo "Recursos do Cilium encontrados."
          break
        fi
        if [ "$i" -eq 30 ]; then
          echo "Recursos do Cilium nao foram criados apos 5min"
          exit 1
        fi
        sleep 10
      done

      echo "Aguardando Cilium ficar pronto..."
      kubectl --kubeconfig "$K" wait --for=condition=Available -n kube-system deployment/cilium-operator --timeout=180s
      kubectl --kubeconfig "$K" wait --for=condition=Ready -n kube-system pod -l k8s-app=cilium --timeout=180s

      # Reinicia o Cilium Operator para registrar o Gateway API controller caso ele tenha subido antes do CRD
      echo "Reiniciando Cilium Operator para registrar Gateway API..."
      kubectl --kubeconfig "$K" rollout restart deployment/cilium-operator -n kube-system
      kubectl --kubeconfig "$K" rollout status deployment/cilium-operator -n kube-system --timeout=180s

      # Adiciona repo Helm do ArgoCD
      helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
      helm repo update argo 2>/dev/null || true

      # Values do ArgoCD (Dex/SSO removido, sem local.yaml)
      VALUES_HELM="$CWD/helm-values/argocd.yaml"
      
      if [ ! -f "$VALUES_HELM" ]; then
        echo "ERRO: $VALUES_HELM não encontrado"
        exit 1
      fi
      
      VALUES_ARGS="--values $VALUES_HELM"

      # Cria namespace argocd e Secret com a key do SOPS
      echo "Criando Secret sops-age-key..."
      kubectl --kubeconfig "$K" create namespace argocd --dry-run=client -o yaml | kubectl --kubeconfig "$K" apply -f -
      echo "$SOPS_KEY" | kubectl --kubeconfig "$K" create secret generic sops-age-key \
        --namespace argocd --from-file=age.key=/dev/stdin --dry-run=client -o yaml \
        | kubectl --kubeconfig "$K" apply -f -

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
