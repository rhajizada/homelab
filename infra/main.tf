locals {
  vpn_dns_name     = "vpn.${var.base_domain}"
  dns_ip           = cidrhost(var.cluster_ip_range, 1)
  vpn_ip           = cidrhost(var.cluster_ip_range, 2)
  k8s_vip          = cidrhost(var.cluster_ip_range, 3)
  k8s_lb_ip        = cidrhost(var.cluster_ip_range, 4)
  control_node_ips = [for i in range(var.talos_vm_config.control.count) : cidrhost(var.cluster_ip_range, 5 + i)]
  worker_node_ips  = [for i in range(var.talos_vm_config.worker.count) : cidrhost(var.cluster_ip_range, 5 + var.talos_vm_config.control.count + i)]
}

module "vpn" {
  source                  = "./modules/vpn"
  cluster_name            = var.cluster_name
  cluster_node_network    = var.cluster_node_network
  cluster_network_gateway = var.cluster_network_gateway
  environment             = var.environment
  proxmox_endpoint        = var.proxmox_endpoint
  proxmox_node_name       = var.proxmox_secondary_node
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
  proxmox_node_name       = var.proxmox_secondary_node
  ip_address              = local.dns_ip
  base_domain             = var.base_domain
  dns_entries = [
    {
      name  = "${var.base_domain}."
      type  = "IN A"
      value = local.k8s_lb_ip
    }
  ]
  vm_config    = var.dns_vm_config
  ubuntu_image = proxmox_virtual_environment_download_file.ubuntu_image.id
}

module "route53" {
  source       = "./modules/route53"
  cluster_name = var.cluster_name
  environment  = var.environment
  base_domain  = var.base_domain
  dns_name     = local.vpn_dns_name
}

module "talos" {
  source                  = "./modules/talos"
  cluster_name            = var.cluster_name
  cluster_node_network    = var.cluster_node_network
  cluster_network_gateway = var.cluster_network_gateway
  environment             = var.environment
  proxmox_endpoint        = var.proxmox_endpoint
  proxmox_node_name       = var.proxmox_primary_node
  k8s_vip                 = local.k8s_vip
  k8s_lb_ip               = local.k8s_lb_ip
  control_node_ips        = local.control_node_ips
  worker_node_ips         = local.worker_node_ips
  talos_version           = var.talos_version
  vm_config               = var.talos_vm_config
  aws_iam_credentials     = module.route53.talos_iam_user
  aws_region              = module.route53.aws_region
  aws_route53_zone_id     = module.route53.route_53_zone_id
  acme_email              = var.acme_email
  acme_server             = var.acme_server
}


