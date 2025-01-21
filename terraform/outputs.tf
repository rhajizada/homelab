output "control_plane_ips" {
  description = "IP addresses of the control plane nodes"
  value       = [for node in local.control_nodes : node.address]
}

output "worker_ips" {
  description = "IP addresses of the worker nodes"
  value       = [for node in local.worker_nodes : node.address]
}

output "kubeconfig" {
  description = "K8s cluster kubeconfig"
  sensitive   = true
  value       = talos_cluster_kubeconfig.talos.kubeconfig_raw
}

