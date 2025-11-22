locals {
  grafana = {
    repository = "https://grafana.github.io/helm-charts/"
    chart      = "grafana"
    version    = "8.10.1"
    namespace  = "grafana"

    admin = {
      username = "admin"
    }
    host   = "grafana.${var.base_domain}"
    groups = ["grafana-editors", "grafana-admins"]
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


resource "random_password" "grafana_client_id" {
  length  = 32
  special = false
}

resource "random_password" "grafana_client_secret" {
  length  = 64
  special = true
}

resource "authentik_group" "grafana_groups" {
  for_each = toset(local.grafana.groups)
  name     = each.value
}

resource "authentik_provider_oauth2" "grafana" {
  depends_on = [
    helm_release.authentik
  ]
  name               = "grafana"
  client_type        = "confidential"
  client_id          = random_password.grafana_client_id.result
  client_secret      = random_password.grafana_client_secret.result
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id
  allowed_redirect_uris = [
    {
      matching_mode = "strict",
      url           = "https://${local.grafana.host}/login/generic_oauth",
    }
  ]
  property_mappings = [
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.openid.id,
  ]
  signing_key = data.authentik_certificate_key_pair.generated.id
}

resource "authentik_application" "grafana" {
  name              = "Grafana"
  slug              = "grafana-slug"
  protocol_provider = authentik_provider_oauth2.grafana.id
  meta_icon         = "https://simpleicons.org/icons/grafana.svg"
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
