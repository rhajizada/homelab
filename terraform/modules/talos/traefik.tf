# locals {
#   traefik = {
#     username      = "admin"
#     password      = random_password.traefik_dashboard.result
#     dashboard_dns = "traefik.${var.base_domain}"
#     version       = "34.1.0"
#   }
# }
#
# resource "random_password" "traefik_dashboard" {
#   length  = 16
#   special = true
# }
#
#
# resource "helm_release" "traefik" {
#   depends_on = [talos_machine_bootstrap.talos, local_file.talos_kubeconfig]
#   name       = "traefik"
#   chart      = "traefik/traefik"
#   version    = local.traefik.version
#   namespace  = "traefik"
#
#   create_namespace  = true
#   cleanup_on_fail   = true
#   dependency_update = true
#
#   values = [
#     templatefile("${path.module}/templates/traefik.yaml.tmpl", {
#       dashboard_dns = local.traefik.dashboard_dns,
#       ingress_ip    = var.kube_vip,
#       username      = local.traefik.username,
#       password      = local.traefik.password
#     })
#   ]
# }
#

