locals {
  cert_manager = {
    version     = "1.16.3"
    issuer_name = "letsencrypt-${var.environment}"
  }
}

data "helm_template" "cert_manager" {
  namespace    = "cert-manager"
  name         = "cert-manager"
  chart        = "jetstack/cert-manager"
  version      = local.cert_manager.version
  kube_version = var.k8s_version
}
