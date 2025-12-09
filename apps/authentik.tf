locals {
  authentik = {
    repository = "https://charts.goauthentik.io/"
    chart      = "authentik"
    version    = "2025.10.2"
    namespace  = "authentik"

    host = "authentik.${var.base_domain}"
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

provider "authentik" {
  url      = "https://${local.authentik.host}"
  token    = random_password.authentik_bootstrap_token.result
  insecure = true
}

data "authentik_flow" "default_authorization_flow" {
  depends_on = [
    helm_release.authentik
  ]
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "default_invalidation_flow" {
  depends_on = [
    helm_release.authentik
  ]
  slug = "default-provider-invalidation-flow"
}

data "authentik_property_mapping_provider_scope" "email" {
  depends_on = [
    helm_release.authentik
  ]
  name = "authentik default OAuth Mapping: OpenID 'email'"
}

data "authentik_property_mapping_provider_scope" "profile" {
  depends_on = [
    helm_release.authentik
  ]
  name = "authentik default OAuth Mapping: OpenID 'profile'"
}

data "authentik_property_mapping_provider_scope" "openid" {
  depends_on = [
    helm_release.authentik
  ]
  name = "authentik default OAuth Mapping: OpenID 'openid'"
}

data "authentik_certificate_key_pair" "generated" {
  depends_on = [
    helm_release.authentik
  ]
  name = "authentik Self-signed Certificate"
}

resource "authentik_property_mapping_provider_scope" "preferred_username" {
  depends_on = [helm_release.authentik]
  name       = "authentik preferred_username OAuth Mapping: OpenID 'preferred_username'"
  expression = <<EOF
    return { "preferred_username": request.user.attributes.get("username", "") }
EOF
  scope_name = "preferred_username"
  lifecycle {
    ignore_changes = [expression]
  }
}
