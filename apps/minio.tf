locals {
  minio = {
    version   = "15.0.4"
    host      = "minio.${var.base_domain}"
    namespace = "minio"
    admin = {
      username = "admin"
    }
    storage_size = "120Gi"
  }
}

resource "kubernetes_namespace" "minio_namespace" {
  metadata {
    name = local.minio.namespace
  }
}

resource "random_password" "minio_admin_password" {
  length  = 16
  special = false
}

resource "kubernetes_secret" "minio_authentik_secret" {
  metadata {
    name      = "minio-authentik-secret"
    namespace = local.minio.namespace
  }

  data = {
    key    = random_password.minio_client_id.result
    secret = random_password.minio_client_secret.result
  }

  type = "Opaque"
}

resource "kubernetes_secret" "minio_admin_secret" {
  metadata {
    name      = "minio-admin-secret"
    namespace = local.minio.namespace
  }

  data = {
    username = local.minio.admin.username
    password = random_password.minio_admin_password.result
  }

  type = "Opaque"
}

resource "helm_release" "minio" {
  depends_on = [
    kubernetes_namespace.minio_namespace,
    kubernetes_secret.minio_admin_secret,
    kubernetes_secret.minio_authentik_secret,
    authentik_provider_oauth2.minio,
  authentik_application.minio]
  namespace = local.minio.namespace
  name      = "minio"
  chart     = "bitnami/minio"
  version   = local.minio.version
  timeout   = 600

  values = [
    templatefile("${path.module}/templates/minio.yaml.tmpl", {
      host                = local.minio.host
      cert_issuer         = var.cluster_cert_issuer
      openid_config_url   = "https://${local.authentik.host}/application/o/minio-slug/.well-known/openid-configuration"
      openid_scopes       = "openid,profile,email,minio"
      openid_redirect_uri = "https://${local.minio.host}/oauth_callback"
      storage_size        = local.minio.storage_size
    })
  ]
}
