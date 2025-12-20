locals {
  harbor = {
    repository = "https://helm.goharbor.io"
    chart      = "harbor"
    version    = "1.18.0"
    namespace  = "harbor"

    host         = "harbor.${var.base_domain}"
    groups       = ["harbor-admins"]
    storage_size = "64Gi"
  }
}

resource "kubernetes_namespace" "harbor_namespace" {
  metadata {
    name = local.harbor.namespace
  }
}

resource "random_password" "harbor_admin_password" {
  length  = 16
  special = false
}

resource "random_password" "harbor_secret" {
  length  = 16
  special = false
}

resource "random_password" "harbor_client_id" {
  length  = 32
  special = false
}

resource "random_password" "harbor_client_secret" {
  length  = 64
  special = true
}

resource "authentik_group" "harbor_groups" {
  depends_on = [helm_release.authentik]
  for_each   = toset(local.harbor.groups)
  name       = each.value
}

resource "authentik_provider_oauth2" "harbor" {
  depends_on = [
    helm_release.authentik
  ]
  name                    = "harbor"
  client_type             = "confidential"
  client_id               = random_password.harbor_client_id.result
  client_secret           = random_password.harbor_client_secret.result
  authorization_flow      = data.authentik_flow.default_authorization_flow.id
  invalidation_flow       = data.authentik_flow.default_invalidation_flow.id
  logout_method           = "backchannel"
  refresh_token_threshold = "seconds=0"
  allowed_redirect_uris = [
    {
      matching_mode = "strict",
      url           = "https://${local.harbor.host}/c/oidc/callback",
    }
  ]
  property_mappings = [
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.openid.id,
    authentik_property_mapping_provider_scope.preferred_username.id
  ]
  signing_key = data.authentik_certificate_key_pair.generated.id
}

resource "authentik_application" "harbor" {
  name              = "Harbor"
  slug              = "harbor-slug"
  protocol_provider = authentik_provider_oauth2.harbor.id
  meta_icon         = "https://simpleicons.org/icons/harbor.svg"
}

resource "kubernetes_secret" "harbor_admin_secret" {
  metadata {
    name      = "harbor-admin-secret"
    namespace = local.harbor.namespace
  }

  data = {
    password = random_password.harbor_admin_password.result
  }

  type = "Opaque"
}

resource "kubernetes_secret" "harbor_secret" {
  metadata {
    name      = "harbor-secret"
    namespace = local.harbor.namespace
  }

  data = {
    secretKey = random_password.harbor_secret.result
  }

  type = "Opaque"
}

resource "kubernetes_secret" "harbor_oidc_config" {
  metadata {
    name      = "harbor-oidc-config"
    namespace = local.harbor.namespace
  }

  data = {
    config_overwrite_json = "{\"auth_mode\": \"oidc_auth\", \"oidc_name\": \"authentik\", \"oidc_endpoint\": \"https://${local.authentik.host}/application/o/harbor-slug/\", \"oidc_client_id\": \"${random_password.harbor_client_id.result}\", \"oidc_client_secret\": \"${random_password.harbor_client_secret.result}\", \"oidc_groups_claim\": \"groups\", \"oidc_admin_group\": \"harbor-admins\", \"oidc_scope\": \"openid,profile,email,preferred_username\", \"oidc_verify_cert\": \"true\", \"oidc_auto_onboard\": \"true\", \"oidc_user_claim\": \"preferred_username\"}"
  }

  type = "Opaque"
}

resource "helm_release" "harbor" {
  depends_on = [
    kubernetes_namespace.harbor_namespace,
    kubernetes_secret.harbor_admin_secret,
    kubernetes_secret.harbor_oidc_config,
    authentik_provider_oauth2.harbor,
    authentik_application.harbor
  ]

  name       = "harbor"
  repository = local.harbor.repository
  chart      = local.harbor.chart
  version    = local.harbor.version
  namespace  = local.harbor.namespace

  timeout = 600

  values = [
    templatefile("${path.module}/templates/harbor.yaml.tmpl", {
      host         = local.harbor.host
      cert_issuer  = var.cluster_cert_issuer
      storage_size = local.harbor.storage_size
    })
  ]
}
