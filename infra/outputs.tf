output "talos_k8s_vip" {
  description = "Talos Kubernets VIP"
  value       = module.talos.k8s_vip
}

output "talos_k8s_lb_ip" {
  description = "Talos Kubernetes Load Balancer IP"
  value       = module.talos.k8s_lb_ip
}

output "talos_control_plane_ips" {
  description = "IP addresses of the control plane nodes"
  value       = module.talos.control_plane_ips
}

output "talos_worker_ips" {
  description = "IP addresses of the worker nodes"
  value       = module.talos.worker_ips
}


output "talos_gpu_node_ips" {
  description = "IP addresses of the gpu nodes"
  value       = module.talos.gpu_node_ips
}

output "talos_config" {
  description = "Talos cluster client configuration"
  sensitive   = true
  value       = module.talos.talos_config
}

output "talos_kubeconfig" {
  description = "K8s cluster kubeconfig"
  sensitive   = true
  value       = module.talos.kubeconfig
}

output "cluster_cert_issuer" {
  description = "K8s cert-manager cluster issuer"
  value       = module.talos.cert_issuer
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

output "dns_node_ip" {
  description = "IP Address of DNS node"
  sensitive   = false
  value       = module.dns.ip_address
}

output "dns_node_credentials" {
  description = "DNS node credentials"
  sensitive   = true
  value       = module.dns.credentials
}
