output "talos_control_plane_ips" {
  description = "IP addresses of the control plane nodes"
  value       = module.talos.control_plane_ips
}

output "talos_credentials" {
  description = "Talos cluster credentials"
  sensitive   = true
  value       = module.talos.talos_credentials
}

output "talos_kubeconfig" {
  description = "K8s cluster kubeconfig"
  sensitive   = true
  value       = module.talos.kubeconfig
}

output "talos_worker_ips" {
  description = "IP addresses of the worker nodes"
  value       = module.talos.worker_ips
}

output "vpn_node_ip" {
  description = "IP Address of VPN node"
  sensitive   = false
  value       = module.vpn.ip_address
}

output "vpn_node_credentials" {
  description = "VPN node credentials"
  sensitive   = true
  value       = module.vpn.credentials
}

output "wireguard_client_configuration" {
  description = "wireguard Client configuration"
  sensitive   = true
  value       = module.vpn.wireguard_client_configuration
}
