locals {
  openwebui = {
    repository = "https://helm.openwebui.com"
    chart      = "open-webui"
    version    = "5.25.0"
    namespace  = "openwebui"

    host         = "openwebui.${var.base_domain}"
    storage_size = "16Gi"
    ollama = {
      volume_name  = "openwebui-ollama-pv"
      storage_size = "16Gi"
    }
  }
}

resource "kubernetes_namespace" "openwebui_namespace" {
  metadata {
    name = local.openwebui.namespace
  }
}


resource "random_password" "openwebui_secret" {
  length  = 16
  special = false
}

resource "helm_release" "openwebui" {
  depends_on = [
    kubernetes_namespace.openwebui_namespace,
    random_password.openwebui_secret,
  ]

  name       = "openwebui"
  chart      = local.openwebui.chart
  repository = local.openwebui.repository
  version    = local.openwebui.version
  namespace  = local.openwebui.namespace

  timeout = 600

  values = [
    templatefile("${path.module}/templates/openwebui.yaml.tmpl", {
      host         = local.openwebui.host
      cert_issuer  = var.cluster_cert_issuer
      storage_size = local.openwebui.storage_size
      ollama_size  = local.openwebui.ollama.storage_size
    })
  ]
}
