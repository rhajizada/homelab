locals {
  authentik = {
    repository = "https://charts.goauthentik.io/"
    chart      = "authentik"
    version    = "2024.12.3"
    namespace  = "authentik"

    host = "authentik.${var.base_domain}"
    groups = {
      gitea   = ["git-users", "git-admins"],
      harbor  = ["harbor-admins"]
      grafana = ["grafana-editors", "grafana-admins"]
      argocd  = ["argocd-admins", "argocd-viewers"]
      llamero = ["llamero-admins", "llamero-maintainers", "llamero-users"]
    }
  }
}

resource "kubernetes_namespace" "authentik_namespace" {
  metadata {
    name = local.authentik.namespace
  }
}

resource "random_password" "authentik_secret_key" {
  length  = 32
  special = false
}

resource "random_password" "authentik_bootstrap_token" {
  length  = 32
  special = false
}

resource "random_password" "authentik_bootstrap_password" {
  length  = 32
  special = false
}

resource "random_password" "authentik_postgresql_password" {
  length  = 32
  special = false
}

resource "kubernetes_secret" "authentik_secrets" {
  metadata {
    name      = "authentik-secrets"
    namespace = local.authentik.namespace
  }

  data = {
    secret-key         = random_password.authentik_secret_key.result
    bootstrap-token    = random_password.authentik_bootstrap_token.result
    bootstrap-password = random_password.authentik_bootstrap_password.result
  }

  type = "Opaque"
}

resource "helm_release" "authentik" {
  depends_on = [
    kubernetes_namespace.authentik_namespace,
    kubernetes_secret.authentik_secrets
  ]

  name       = "authentik"
  repository = local.authentik.repository
  chart      = local.authentik.chart
  version    = local.authentik.version
  namespace  = local.authentik.namespace

  timeout = 600

  values = [
    templatefile("${path.module}/templates/authentik.yaml.tmpl", {
      namespace           = local.authentik.namespace
      host                = local.authentik.host
      postgresql_password = random_password.authentik_postgresql_password.result
      cert_issuer         = var.cluster_cert_issuer
    })
  ]
}
