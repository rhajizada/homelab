locals {
  argocd = {
    repository = "https://argoproj.github.io/argo-helm"
    chart      = "argo/argo-cd"
    version    = "7.8.23"
    namespace  = "argocd"
    host       = "argocd.${var.base_domain}"
    groups     = ["argocd-admins", "argocd-viewers"]
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


resource "random_password" "argocd_client_id" {
  length  = 32
  special = false
}

resource "random_password" "argocd_client_secret" {
  length  = 64
  special = true
}

resource "authentik_group" "argocd_groups" {
  for_each = toset(local.argocd.groups)
  name     = each.value
}

resource "authentik_provider_oauth2" "argocd" {
  depends_on = [
    helm_release.authentik
  ]
  name               = "argocd"
  client_type        = "confidential"
  client_id          = random_password.argocd_client_id.result
  client_secret      = random_password.argocd_client_secret.result
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id
  allowed_redirect_uris = [
    {
      matching_mode = "strict",
      url           = "https://${local.argocd.host}/auth/callback",
    }
  ]
  property_mappings = [
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.openid.id,
  ]
  signing_key = data.authentik_certificate_key_pair.generated.id
}

resource "authentik_application" "argocd" {
  name              = "argocd"
  slug              = "argocd-slug"
  protocol_provider = authentik_provider_oauth2.argocd.id
  meta_icon         = "https://simpleicons.org/icons/argo.svg"
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
