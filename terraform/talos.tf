locals {
  cluster_endpoint = "https://${local.control_nodes[0].address}:6443"
  common_machine_config = {
    machine = {
      install = {
        extensions = [
          {
            image = "ghcr.io/siderolabs/intel-ucode:20241112"
          },
          {
            image = "ghcr.io/siderolabs/qemu-guest-agent:9.2.0"
          }
        ]
      }
      features = {
        # see https://www.talos.dev/v1.8/talos-guides/network/host-dns/
        hostDNS = {
          enabled              = true
          forwardKubeDNSToHost = true
        }
      }
      kubelet = {
        extraArgs = {
          rotate-server-certificates = true
        }
      }
    }
  }
}

resource "talos_machine_secrets" "cluster" {
  talos_version = "v${var.talos_version}"
}

data "talos_machine_configuration" "control" {
  cluster_name     = var.cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = local.cluster_endpoint
  talos_version    = "v${var.talos_version}"
  machine_secrets  = talos_machine_secrets.cluster.machine_secrets
  examples         = false
  docs             = false
  config_patches = [
    yamlencode(local.common_machine_config),
    yamlencode({
      cluster = {
        extraManifests = [
          "https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/main/deploy/standalone-install.yaml",
          "https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
        ]
      }
    })
  ]
}

data "talos_machine_configuration" "worker" {
  cluster_name     = var.cluster_name
  machine_type     = "worker"
  cluster_endpoint = local.cluster_endpoint
  talos_version    = "v${var.talos_version}"
  machine_secrets  = talos_machine_secrets.cluster.machine_secrets
  config_patches = [
    yamlencode(local.common_machine_config)
  ]
}

data "talos_client_configuration" "talos" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.cluster.client_configuration
  endpoints            = [for node in local.control_nodes : node.address]
}

resource "talos_cluster_kubeconfig" "talos" {
  client_configuration = talos_machine_secrets.cluster.client_configuration
  endpoint             = local.control_nodes[0].address
  node                 = local.control_nodes[0].address
  depends_on = [
    talos_machine_bootstrap.talos,
  ]
}

resource "talos_machine_configuration_apply" "control" {
  count                       = var.vm_config["control"].count
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.control.machine_configuration
  endpoint                    = local.control_nodes[count.index].address
  node                        = local.control_nodes[count.index].address
  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname = local.control_nodes[count.index].name
        }
      }
    })
  ]
  depends_on = [
    proxmox_virtual_environment_vm.control_plane,
  ]
}

// see https://registry.terraform.io/providers/siderolabs/talos/0.6.1/docs/resources/machine_configuration_apply
resource "talos_machine_configuration_apply" "worker" {
  count                       = var.vm_config["worker"].count
  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  endpoint                    = local.worker_nodes[count.index].address
  node                        = local.worker_nodes[count.index].address
  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname = local.worker_nodes[count.index].name
        }
      }
    }),
  ]
  depends_on = [
    proxmox_virtual_environment_vm.worker,
  ]
}

resource "talos_machine_bootstrap" "talos" {
  client_configuration = talos_machine_secrets.cluster.client_configuration
  endpoint             = local.control_nodes[0].address
  node                 = local.control_nodes[0].address
  depends_on = [
    talos_machine_configuration_apply.control,
  ]
}
