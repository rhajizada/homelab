locals {
  gazette = {
    namespace = "gazette"
    host      = "gazette.${var.base_domain}"
  }
}

resource "kubernetes_namespace" "gazette_namespace" {
  metadata {
    name = local.gazette.namespace
  }
}

resource "kubernetes_secret" "gazette_oauth_secrets" {
  metadata {
    name      = "gazette-oauth-secrets"
    namespace = local.gazette.namespace
  }

  data = {
    client_id     = random_password.gazette_client_id.result
    client_secret = random_password.gazette_client_secret.result
    issuer_url    = "https://${local.authentik.host}/application/o/gazette-slug/"
    redirect_url  = "https://${local.gazette.host}/oauth/callback"
  }

  type = "Opaque"
}
