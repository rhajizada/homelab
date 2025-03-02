locals {
  grafana = {
    repository = "https://grafana.github.io/helm-charts/"
    chart      = "grafana"
    version    = "8.10.1"
    namespace  = "grafana"

    admin = {
      username = "admin"
    }
    host = "grafana.${var.base_domain}"
  }
}

resource "kubernetes_namespace" "grafana_namespace" {
  metadata {
    name = local.grafana.namespace
  }
}

resource "random_password" "grafana_admin_password" {
  length  = 16
  special = false
}

resource "kubernetes_secret" "grafana_admin_secret" {
  metadata {
    name      = "grafana-admin-secret"
    namespace = local.grafana.namespace
  }

  data = {
    user     = local.grafana.admin.username
    password = random_password.grafana_admin_password.result
  }

  type = "Opaque"
}

resource "kubernetes_secret" "grafana_authentik_secret" {
  metadata {
    name      = "grafana-authentik-secret"
    namespace = local.grafana.namespace
  }

  data = {
    client_id     = random_password.grafana_client_id.result
    client_secret = random_password.grafana_client_secret.result
  }

  type = "Opaque"
}

resource "helm_release" "grafana" {
  depends_on = [
    kubernetes_namespace.grafana_namespace,
    kubernetes_secret.grafana_admin_secret,
    authentik_application.grafana,
    kubernetes_secret.grafana_authentik_secret
  ]

  name       = "grafana"
  repository = local.grafana.repository
  chart      = local.grafana.chart
  version    = local.grafana.version
  namespace  = local.grafana.namespace


  values = [
    templatefile("${path.module}/templates/grafana.yaml.tmpl", {
      oauth_name     = "authentik"
      oauth_slug     = "grafana-slug"
      oauth_scopes   = "openid profile email"
      authentik_host = local.authentik.host
      host           = local.grafana.host
      cert_issuer    = var.cluster_cert_issuer
    })
  ]
}
