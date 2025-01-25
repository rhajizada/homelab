locals {
  vpn_dns_name = var.base_domain == "" ? "" : "vpn.${var.base_domain}"
}

module "talos" {
  source                  = "./modules/talos"
  cluster_name            = var.cluster_name
  cluster_node_network    = var.cluster_node_network
  cluster_network_gateway = var.cluster_network_gateway
  environment             = var.environment
  proxmox_endpoint        = var.proxmox_endpoint
  proxmox_node_name       = var.proxmox_node_name
  talos_version           = var.talos_version
  vm_config               = var.talos_vm_config
}

module "vpn" {
  source            = "./modules/vpn"
  cluster_name      = var.cluster_name
  environment       = var.environment
  proxmox_endpoint  = var.proxmox_endpoint
  proxmox_node_name = var.proxmox_node_name
  vm_config         = var.vpn_vm_config
  dns_name          = local.vpn_dns_name
}

module "route53" {
  source       = "./modules/route53"
  count        = var.base_domain != "" ? 1 : 0
  cluster_name = var.cluster_name
  environment  = var.environment
  base_domain  = var.base_domain
  dns_name     = local.vpn_dns_name
}
