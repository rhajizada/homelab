locals {
  harbor = {
    version      = "1.16.2"
    host         = "harbor.${var.base_domain}"
    namespace    = "harbor"
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
    config_overwrite_json = "{\"auth_mode\": \"oidc_auth\", \"oidc_name\": \"Authentik\", \"oidc_endpoint\": \"https://${local.authentik.host}/application/o/harbor-slug/\", \"oidc_client_id\": \"${random_password.harbor_client_id.result}\", \"oidc_client_secret\": \"${random_password.harbor_client_secret.result}\", \"oidc_groups_claim\": \"groups\", \"oidc_admin_group\": \"harbor-admins\", \"oidc_scope\": \"openid,profile,email\", \"oidc_verify_cert\": \"true\", \"oidc_auto_onboard\": \"true\", \"oidc_user_claim\": \"preferred_username\"}"
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
  namespace = local.harbor.namespace
  name      = "harbor"
  chart     = "harbor/harbor"
  version   = local.harbor.version
  timeout   = 600

  values = [
    templatefile("${path.module}/templates/harbor.yaml.tmpl", {
      host         = local.harbor.host
      cert_issuer  = var.cluster_cert_issuer
      storage_size = local.harbor.storage_size
    })
  ]
}
