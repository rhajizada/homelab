locals {
  argocd = {
    repository = "https://argoproj.github.io/argo-helm"
    chart      = "argo/argo-cd"
    version    = "7.8.23"
    namespace  = "argocd"
    host       = "argocd.${var.base_domain}"
  }
}

resource "kubernetes_namespace" "argocd_namespace" {
  metadata {
    name = local.argocd.namespace
  }
}

resource "random_password" "argocd_admin_password" {
  length  = 16
  special = false
}

resource "bcrypt_hash" "argocd_admin_password" {
  cleartext = random_password.argocd_admin_password.result
}

resource "helm_release" "argocd" {
  depends_on = [
    kubernetes_namespace.argocd_namespace,
    authentik_provider_oauth2.argocd,
    authentik_application.argocd
  ]

  name      = "argoocd"
  chart     = local.argocd.chart
  version   = local.argocd.version
  namespace = local.argocd.namespace

  timeout = 600

  values = [
    templatefile("${path.module}/templates/argocd.yaml.tmpl", {
      host                = local.argocd.host
      cert_issuer         = var.cluster_cert_issuer
      admin_password      = bcrypt_hash.argocd_admin_password.id
      oauth_name          = "authentik"
      oauth_issuer        = "https://${local.authentik.host}/application/o/argocd-slug/"
      oauth_client_id     = random_password.argocd_client_id.result
      oauth_client_secret = random_password.argocd_client_secret.result
      oauth_scopes        = ["openid", "profile", "email"]
    })
  ]
}
