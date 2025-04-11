locals {
  openwebui = {
    repository = "https://helm.openwebui.com"
    chart      = "open-webui"
    version    = "6.1.0"
    namespace  = "openwebui"

    host         = "openwebui.${var.base_domain}"
    storage_size = "16Gi"
    ollama = {
      volume_name  = "openwebui-ollama-pv"
      storage_size = "128Gi"
    }
  }
}

resource "kubernetes_namespace" "openwebui_namespace" {
  metadata {
    name = local.openwebui.namespace
  }
}

resource "kubernetes_secret" "openwebui_authentik_secret" {
  metadata {
    name      = "openwebui-authentik-secret"
    namespace = local.openwebui.namespace
  }

  data = {
    client_id     = random_password.openwebui_client_id.result
    client_secret = random_password.openwebui_client_secret.result
  }

  type = "Opaque"
}

resource "helm_release" "openwebui" {
  depends_on = [
    kubernetes_namespace.openwebui_namespace,
    authentik_application.openwebui,
    kubernetes_secret.openwebui_authentik_secret
    ,
  ]

  name       = "openwebui"
  chart      = local.openwebui.chart
  repository = local.openwebui.repository
  version    = local.openwebui.version
  namespace  = local.openwebui.namespace

  timeout = 1200

  values = [
    templatefile("${path.module}/templates/openwebui.yaml.tmpl", {
      host                 = local.openwebui.host
      cert_issuer          = var.cluster_cert_issuer
      storage_size         = local.openwebui.storage_size
      ollama_size          = local.openwebui.ollama.storage_size
      openid_provider_url  = "https://${local.authentik.host}/application/o/openwebui-slug/.well-known/openid-configuration"
      openid_provider_name = "authentik"
      openid_redirect_uri  = "http://192.168.1.234:32000/oauth/oidc/callback"
    })
  ]
}
