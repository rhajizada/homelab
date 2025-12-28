locals {
  homarr = {
    repository = "https://homarr-labs.github.io/charts/"
    chart      = "homarr"
    version    = "8.6.0"
    namespace  = "homarr"

    admin = {
      username = "admin"
    }
    host   = "homarr.${var.base_domain}"
    groups = ["homarr-users", "homarr-admins"]
  }
}

resource "kubernetes_namespace" "homarr_namespace" {
  metadata {
    name = local.homarr.namespace
  }
}

resource "random_password" "homarr_db_encryption_key" {
  length  = 64
  special = false
  upper   = false
  lower   = false
  numeric = true
}


resource "random_password" "homarr_client_id" {
  length  = 32
  special = false
}

resource "random_password" "homarr_client_secret" {
  length  = 64
  special = false
}

resource "authentik_group" "homarr_groups" {
  depends_on = [helm_release.authentik]
  for_each   = toset(local.homarr.groups)
  name       = each.value
}

resource "authentik_provider_oauth2" "homarr" {
  depends_on = [
    helm_release.authentik
  ]
  name                    = "homarr"
  client_type             = "confidential"
  client_id               = random_password.homarr_client_id.result
  client_secret           = random_password.homarr_client_secret.result
  authorization_flow      = data.authentik_flow.default_authorization_flow.id
  invalidation_flow       = data.authentik_flow.default_invalidation_flow.id
  logout_method           = "backchannel"
  refresh_token_threshold = "seconds=0"
  allowed_redirect_uris = [
    {
      matching_mode = "strict",
      url           = "https://${local.homarr.host}/api/auth/callback/oidc",
    }
  ]
  property_mappings = [
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.openid.id,
  ]
  signing_key = data.authentik_certificate_key_pair.generated.id
}

resource "authentik_application" "homarr" {
  name              = "homarr"
  slug              = "homarr-slug"
  protocol_provider = authentik_provider_oauth2.homarr.id
  meta_icon         = "https://simpleicons.org/icons/homarr.svg"
}

resource "kubernetes_secret" "homarr_db_encryption_key_secret" {
  metadata {
    name      = "homarr-db-encryption"
    namespace = local.homarr.namespace
  }

  data = {
    db-encryption-key = random_password.homarr_db_encryption_key.result
  }

  type = "Opaque"
}

resource "kubernetes_secret" "homarr_authentik_secret" {
  metadata {
    name      = "homarr-authentik-secret"
    namespace = local.homarr.namespace
  }

  data = {
    oidc-client-id     = random_password.homarr_client_id.result
    oidc-client-secret = random_password.homarr_client_secret.result
  }

  type = "Opaque"
}

resource "helm_release" "homarr" {
  depends_on = [
    kubernetes_namespace.homarr_namespace,
    kubernetes_secret.homarr_db_encryption_key_secret,
    authentik_application.homarr,
    kubernetes_secret.homarr_authentik_secret
  ]

  name       = "homarr"
  repository = local.homarr.repository
  chart      = local.homarr.chart
  version    = local.homarr.version
  namespace  = local.homarr.namespace


  values = [
    templatefile("${path.module}/templates/homarr.yaml.tmpl", {
      oidc_name      = "authentik"
      oidc_slug      = "homarr-slug"
      oidc_scopes    = "openid profile email"
      oidc_issuer    = "https://${local.authentik.host}/application/o/homarr-slug/"
      authentik_host = local.authentik.host
      host           = local.homarr.host
      cert_issuer    = var.cluster_cert_issuer
    })
  ]
}
