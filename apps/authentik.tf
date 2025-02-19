locals {
  authentik = {
    namespace = "authentik"
    version   = "2024.12.3"
    host      = "authentik.${var.base_domain}"
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

  force_update = true
}
