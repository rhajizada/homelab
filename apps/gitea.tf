locals {
  gitea = {
    version   = "10.6.0"
    host      = "git.${var.base_domain}"
    namespace = "gitea"
    admin = {
      username = "gitea_admin"
      email    = "gitea@${var.base_domain}"
    }
  }
}

resource "kubernetes_namespace" "gitea_namespace" {
  metadata {
    name = local.gitea.namespace
  }
}

resource "random_password" "gitea_admin_password" {
  length  = 16
  special = false
}

resource "kubernetes_secret" "gitea_authentik_secret" {
  metadata {
    name      = "gitea-authentik-secret"
    namespace = local.gitea.namespace
  }

  data = {
    key    = random_password.gitea_client_id.result
    secret = random_password.gitea_client_secret.result
  }

  type = "Opaque"
}

resource "kubernetes_secret" "gitea_admin_secret" {
  metadata {
    name      = "gitea-admin-secret"
    namespace = local.gitea.namespace
  }

  data = {
    username = local.gitea.admin.username
    email    = local.gitea.admin.email
    password = random_password.gitea_admin_password.result
  }

  type = "Opaque"
}

resource "helm_release" "gitea" {
  depends_on = [
    kubernetes_namespace.gitea_namespace,
    kubernetes_secret.gitea_admin_secret,
    kubernetes_secret.gitea_authentik_secret,
    authentik_provider_oauth2.gitea,
  authentik_application.gitea]
  namespace = local.gitea.namespace
  name      = "gitea"
  chart     = "gitea/gitea"
  version   = local.gitea.version

  values = [
    templatefile("${path.module}/templates/gitea.yaml.tmpl", {
      oauth_name          = "authentik"
      oauth_discovery_url = "https://${local.authentik.host}/application/o/gitea-slug/.well-known/openid-configuration"
      oauth_scopes        = "email profile gitea"
      host                = local.gitea.host
      cert_issuer         = var.cluster_cert_issuer
    })
  ]
}
