locals {
  cp_ip       = "192.168.1.50"
  worker_ip   = "192.168.1.51"
  cluster_ep  = "https://${local.cp_ip}:6443"
  gateway     = "192.168.1.1"
  cidr_suffix = "/24"
}

ephemeral "talos_machine_secrets" "this" {}

ephemeral "talos_client_configuration" "this" {
  cluster_name    = "ocilab"
  machine_secrets = ephemeral.talos_machine_secrets.this.machine_secrets
  endpoints       = [local.cp_ip, local.worker_ip]
  nodes           = [local.cp_ip, local.worker_ip]
}

ephemeral "talos_machine_configuration" "cp" {
  cluster_name     = "ocilab"
  machine_type     = "controlplane"
  cluster_endpoint = local.cluster_ep
  machine_secrets  = ephemeral.talos_machine_secrets.this.machine_secrets
  talos_version    = "v1.13"
  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk = "/dev/sda"
        }
        network = {
          interfaces = [{
            interface = "ens18"
            dhcp     = false
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
          extraArgs = {
            "ipvs-strict-arp" = "true"
          }
        }
        network = {
          cni = {
            name = "custom"
            urls = ["https://raw.githubusercontent.com/projectcalico/calico/v3.29.3/manifests/calico.yaml"]
          }
        }
        apiServer = {
          admissionControl = [{
            name = "PodSecurity"
            configuration = {
              apiVersion = "pod-security.admission.config.k8s.io/v1alpha1"
              kind       = "PodSecurityConfiguration"
              defaults = {
                enforce         = "baseline"
                "enforce-version" = "latest"
                audit           = "restricted"
                "audit-version"   = "latest"
                warn            = "restricted"
                "warn-version"    = "latest"
              }
              exemptions = {
                namespaces = ["kube-system"]
              }
            }
          }]
        }
      }
    })
  ]
}

ephemeral "talos_machine_configuration" "worker" {
  cluster_name     = "ocilab"
  machine_type     = "worker"
  cluster_endpoint = local.cluster_ep
  machine_secrets  = ephemeral.talos_machine_secrets.this.machine_secrets
  talos_version    = "v1.13"
  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk = "/dev/sda"
        }
        network = {
          interfaces = [{
            interface = "ens18"
            dhcp     = false
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

ephemeral "talos_cluster_kubeconfig" "this" {
  cluster_name    = "ocilab"
  machine_secrets = ephemeral.talos_machine_secrets.this.machine_secrets
  endpoint        = local.cluster_ep
}
