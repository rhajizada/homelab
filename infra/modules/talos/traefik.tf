locals {
  traefik = {
    username      = "admin"
    password      = random_password.traefik_dashboard.result
    dashboard_dns = "traefik.${var.base_domain}"
    version       = "34.1.0"
  }
  traefik_crds = {
    version = "1.2.0"
  }
}

resource "random_password" "traefik_dashboard" {
  length  = 16
  special = true
}

data "helm_template" "traefik_crds" {
  namespace    = "traefik"
  name         = "traefik-crds"
  chart        = "traefik/traefik-crds"
  version      = local.traefik_crds.version
  kube_version = var.k8s_version

}


data "helm_template" "traefik" {
  namespace    = "traefik"
  name         = "traefik"
  chart        = "traefik/traefik"
  version      = local.traefik.version
  kube_version = var.k8s_version

  values = [
    templatefile("${path.module}/templates/traefik.yaml.tmpl", {
      lb_ip         = var.k8s_lb_ip,
      dashboard_dns = local.traefik.dashboard_dns,
      username      = local.traefik.username,
      password      = local.traefik.password
    })
  ]
}


