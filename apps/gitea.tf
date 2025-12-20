locals {
  gitea = {
    repository = "https://dl.gitea.com/charts/"
    chart      = "gitea"
    version    = "10.6.0"
    namespace  = "gitea"

    host = "git.${var.base_domain}"
    admin = {
      username = "gitea_admin"
      email    = "gitea@${var.base_domain}"
    }
    groups       = ["git-users", "git-admins"]
    storage_size = "64Gi"
  }
}

resource "kubernetes_namespace" "gitea_namespace" {
  metadata {
    name = local.gitea.namespace
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

resource "random_password" "gitea_admin_password" {
  length  = 16
  special = false
}


resource "random_password" "gitea_client_id" {
  length  = 32
  special = false
}

resource "random_password" "gitea_client_secret" {
  length  = 64
  special = true
}

resource "authentik_property_mapping_provider_scope" "gitea" {
  depends_on = [helm_release.authentik]
  name       = "authentik gitea OAuth Mapping: OpenID 'gitea'"
  expression = <<EOF
gitea_claims = {}
gitea_claims["gitea"]= "restricted"

if request.user.ak_groups.filter(name="git-users").exists():
    gitea_claims["gitea"]= "user"
if request.user.ak_groups.filter(name="git-admins").exists():
    gitea_claims["gitea"]= "admin"

return gitea_claims
EOF
  scope_name = "gitea"
}

resource "authentik_provider_oauth2" "gitea" {
  depends_on = [
    helm_release.authentik,
    authentik_property_mapping_provider_scope.gitea
  ]
  name                    = "gitea"
  client_id               = random_password.gitea_client_id.result
  client_secret           = random_password.gitea_client_secret.result
  authorization_flow      = data.authentik_flow.default_authorization_flow.id
  invalidation_flow       = data.authentik_flow.default_invalidation_flow.id
  logout_method           = "backchannel"
  refresh_token_threshold = "seconds=0"
  allowed_redirect_uris = [
    {
      matching_mode = "strict",
      url           = "https://${local.gitea.host}/user/oauth2/authentik/callback",
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
  meta_icon         = "https://simpleicons.org/icons/gitea.svg"
}


resource "authentik_group" "gitea_groups" {
  depends_on = [helm_release.authentik]
  for_each   = toset(local.gitea.groups)
  name       = each.value
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

  name       = "gitea"
  repository = local.gitea.repository
  chart      = local.gitea.chart
  version    = local.gitea.version
  namespace  = local.gitea.namespace

  timeout = 600

  values = [
    templatefile("${path.module}/templates/gitea.yaml.tmpl", {
      oauth_name             = "authentik"
      oauth_group_claim_name = "gitea"
      oauth_discovery_url    = "https://${local.authentik.host}/application/o/gitea-slug/.well-known/openid-configuration"
      oauth_scopes           = "email profile gitea"
      host                   = local.gitea.host
      cert_issuer            = var.cluster_cert_issuer
      storage_size           = local.gitea.storage_size
    })
  ]
}
