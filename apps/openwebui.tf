locals {
  openwebui = {
    repository = "https://helm.openwebui.com"
    chart      = "open-webui"
    version    = "6.1.0"
    namespace  = "openwebui"

    host         = "chat.${var.base_domain}"
    storage_size = "16Gi"
    ollama = {
      volume_name  = "openwebui-ollama-pv"
      storage_size = "128Gi"
      models = [
        "deepseek-r1:14b",
        "gemma3:12b",
        "llama3.1:8b",
        "phi4:14b",
      ]
    }
  }
  chromadb = {
    repository   = "https://infracloudio.github.io/charts"
    chart        = "chromadb"
    version      = "0.1.4"
    storage_size = "16Gi"
  }
  tika = {
    repository = "https://apache.jfrog.io/artifactory/tika"
    chart      = "tika"
    version    = "2.9.0"
  }
  playwright = {
    version = "1.51.1"
  }
}

resource "kubernetes_namespace" "openwebui_namespace" {
  metadata {
    name = local.openwebui.namespace
  }
}

resource "random_password" "openwebui_secret_key" {
  length  = 32
  special = false
}

resource "random_password" "openwebui_pipelines_key" {
  length  = 32
  special = false
}

resource "kubernetes_secret" "openwebui_secret" {
  metadata {
    name      = "openwebui-secret"
    namespace = local.openwebui.namespace
  }

  data = {
    secret = random_password.openwebui_secret_key.result
  }

  type = "Opaque"
}

resource "kubernetes_secret" "openwebui_pipelines_secret" {
  metadata {
    name      = "openwebui-pipelines-secret"
    namespace = local.openwebui.namespace
  }

  data = {
    key = random_password.openwebui_pipelines_key.result
  }

  type = "Opaque"
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

resource "helm_release" "chromadb" {
  depends_on = [
    kubernetes_namespace.openwebui_namespace,
  ]

  name       = "open-webui-chromadb"
  chart      = local.chromadb.chart
  repository = local.chromadb.repository
  version    = local.chromadb.version
  namespace  = local.openwebui.namespace

  timeout = 600

  values = [
    templatefile("${path.module}/templates/chromadb.yaml.tmpl", {
      storage_size = local.chromadb.storage_size
    })
  ]
}

resource "helm_release" "tika" {
  depends_on = [
    kubernetes_namespace.openwebui_namespace,
  ]

  name       = "open-webui-tika"
  chart      = local.tika.chart
  repository = local.tika.repository
  version    = local.tika.version
  namespace  = local.openwebui.namespace

  timeout = 600

  values = [
    file("${path.module}/templates/tika.yaml")
  ]
}

resource "helm_release" "openwebui" {
  depends_on = [
    kubernetes_namespace.openwebui_namespace,
    authentik_application.openwebui,
    kubernetes_secret.openwebui_secret,
    kubernetes_secret.openwebui_authentik_secret,
    kubernetes_secret.openwebui_pipelines_secret,
    helm_release.chromadb,
    helm_release.tika
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
      openid_redirect_uri  = "https://${local.openwebui.host}/oauth/oidc/callback"
    })
  ]
}


resource "kubernetes_job" "ollama_init" {
  depends_on = [
    helm_release.openwebui
  ]

  for_each = { for model in local.openwebui.ollama.models : model => model }

  metadata {
    name      = "open-webui-ollama-init-${replace(replace(each.value, ".", "-"), ":", "-")}"
    namespace = local.openwebui.namespace
  }

  spec {
    # run exactly once, no retries
    completions   = 1
    parallelism   = 1
    backoff_limit = 0

    template {
      metadata {
        labels = {
          job = "open-webui-ollama-init-${replace(replace(each.value, ".", "-"), ":", "-")}"
        }
      }

      spec {

        container {
          name  = "ollama-init"
          image = "alpine/curl"
          command = [
            "sh",
            "-c",
            "curl -s http://open-webui-ollama.openwebui.svc.cluster.local:11434/api/pull -d '{\"model\": \"${each.value}\"}'"
          ]
        }
      }
    }
  }

  timeouts {
    create = "1h"
    delete = "1h"
  }
}


