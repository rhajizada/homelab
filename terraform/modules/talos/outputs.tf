output "k8s_vip" {
  description = "Kubernetes VIP"
  value       = var.k8s_vip
}

output "k8s_lb_ip" {
  description = "Kubenenetes Load Balancer IP"
  value       = var.k8s_lb_ip
}

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

output "talos_client_config" {
  description = "Talos cluster client configuration"
  sensitive   = true
  value       = talos_machine_secrets.cluster.client_configuration.client_certificate
}

output "cert_issuer" {
  description = "K8s cert-manager cluster issuer name"
  value       = local.cert_manager.issuer_name
}
