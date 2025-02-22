locals {
  authentik = {
    namespace = "authentik"
    version   = "2024.12.3"
    host      = "authentik.${var.base_domain}"
    groups = {
      gitea = ["gituser", "gitadmin", "gitrestricted"]
    }
  }
}

provider "authentik" {
  url      = "https://${local.authentik.host}"
  token    = random_password.authentik_bootstrap_token.result
  insecure = true
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
  depends_on = [kubernetes_namespace.authentik_namespace, kubernetes_secret.authentik_secrets]
  namespace  = local.authentik.namespace
  name       = "authentik"
  chart      = "goauthentik/authentik"
  version    = local.authentik.version

  values = [
    templatefile("${path.module}/templates/authentik.yaml.tmpl", {
      namespace           = local.authentik.namespace
      host                = local.authentik.host
      postgresql_password = random_password.authentik_postgresql_password.result
      cert_issuer         = var.cluster_cert_issuer
    })
  ]
}

resource "random_password" "gitea_client_id" {
  length  = 32
  special = false
}

resource "random_password" "gitea_client_secret" {
  length  = 64
  special = true
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

resource "authentik_property_mapping_provider_scope" "gitea" {
  depends_on = [helm_release.authentik]
  name       = "authentik gitea OAuth Mapping: OpenID 'gitea'"
  expression = <<EOF
gitea_claims = {}
if request.user.ak_groups.filter(name="gituser").exists():
    gitea_claims["gitea"]= "user"
if request.user.ak_groups.filter(name="gitadmin").exists():
    gitea_claims["gitea"]= "admin"
if request.user.ak_groups.filter(name="gitrestricted").exists():
    gitea_claims["gitea"]= "restricted"

return gitea_claims
EOF
  scope_name = "gitea"
}

resource "authentik_provider_oauth2" "gitea" {
  depends_on = [
    helm_release.authentik,
    authentik_property_mapping_provider_scope.gitea
  ]
  name               = "Gitea"
  client_id          = random_password.gitea_client_id.result
  client_secret      = random_password.gitea_client_secret.result
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id
  allowed_redirect_uris = [
    {
      matching_mode = "strict",
      url           = "https://git.${var.base_domain}/user/oauth2/authentik/callback",
    }
  ]
  property_mappings = [
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.openid.id,
    authentik_property_mapping_provider_scope.gitea.id
  ]
}

resource "authentik_application" "gitea" {
  name              = "Gitea"
  slug              = "gitea-slug"
  protocol_provider = authentik_provider_oauth2.gitea.id
}


resource "authentik_group" "gitea_groups" {
  for_each = toset(local.authentik.groups.gitea)
  name     = each.value
}

