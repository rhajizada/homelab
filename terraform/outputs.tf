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

output "talos_ca_certificate" {
  description = "Talos CA certificate"
  sensitive   = true
  value       = talos_machine_secrets.cluster.client_configuration.ca_certificate
}

output "talos_client_key" {
  description = "Talos client key"
  sensitive   = true
  value       = talos_machine_secrets.cluster.client_configuration.client_key
}

output "talos_client_certificate" {
  description = "Talos client key"
  sensitive   = true
  value       = talos_machine_secrets.cluster.client_configuration.client_certificate
}
