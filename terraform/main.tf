locals {
  vpn_dns_name     = var.base_domain == "" ? "" : "vpn.${var.base_domain}"
  dns_ip           = cidrhost(var.cluster_ip_range, 1)
  vpn_ip           = cidrhost(var.cluster_ip_range, 2)
  kube_vip         = cidrhost(var.cluster_ip_range, 3)
  control_node_ips = [for i in range(var.talos_vm_config.control.count) : cidrhost(var.cluster_ip_range, 4 + i)]
  worker_node_ips  = [for i in range(var.talos_vm_config.worker.count) : cidrhost(var.cluster_ip_range, 4 + var.talos_vm_config.control.count + i)]
}

module "vpn" {
  source                  = "./modules/vpn"
  cluster_name            = var.cluster_name
  cluster_node_network    = var.cluster_node_network
  cluster_network_gateway = var.cluster_network_gateway
  environment             = var.environment
  proxmox_endpoint        = var.proxmox_endpoint
  proxmox_node_name       = var.proxmox_node_name
  ip_address              = local.vpn_ip
  vm_config               = var.vpn_vm_config
  dns_name                = local.vpn_dns_name
  ubuntu_image            = proxmox_virtual_environment_download_file.ubuntu_image.id
}

module "dns" {
  source                  = "./modules/dns"
  cluster_name            = var.cluster_name
  cluster_node_network    = var.cluster_node_network
  cluster_network_gateway = var.cluster_network_gateway
  environment             = var.environment
  proxmox_endpoint        = var.proxmox_endpoint
  proxmox_node_name       = var.proxmox_node_name
  ip_address              = local.dns_ip
  vm_config               = var.dns_vm_config
  ubuntu_image            = proxmox_virtual_environment_download_file.ubuntu_image.id
}

module "talos" {
  source                  = "./modules/talos"
  cluster_name            = var.cluster_name
  cluster_node_network    = var.cluster_node_network
  cluster_network_gateway = var.cluster_network_gateway
  environment             = var.environment
  proxmox_endpoint        = var.proxmox_endpoint
  proxmox_node_name       = var.proxmox_node_name
  kube_vip                = local.kube_vip
  control_node_ips        = local.control_node_ips
  worker_node_ips         = local.worker_node_ips
  talos_version           = var.talos_version
  vm_config               = var.talos_vm_config
}

module "route53" {
  source       = "./modules/route53"
  count        = var.base_domain != "" ? 1 : 0
  cluster_name = var.cluster_name
  environment  = var.environment
  base_domain  = var.base_domain
  dns_name     = local.vpn_dns_name
}
