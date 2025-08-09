locals {
  ollama = {
    namespace    = "ollama"
    volume_name  = "openwebui-ollama-pv"
    storage_size = "128Gi"
    image        = "ollama/ollama:latest"
    models = [
      "deepseek-r1:14b",
      "gemma3:12b",
      "gpt-oss:20b",
      "llama3.1:8b",
      "nomic-embed-text",
      "qwen3:14b"
      # "mistral",
      # "phi4:14b",
      # "qwen2.5-coder:14b",
    ]
  }
  gateway = {
    host  = "ollama.${var.base_domain}"
    image = "1lcb/ollama-gateway:latest"
    config = jsonencode({
      ollamaAddresses = ["http://ollama.${local.ollama.namespace}.svc.cluster.local:11434/"]
      gatewayAddress  = "0.0.0.0:8080"
      logging         = true
      authHeaderName  = "Authorization"
      apiKeys         = [random_password.gateway_api_key.result]
      rateLimit       = { enabled = false, maxRequests = 100, timeWindowSeconds = 60 }
      metrics         = { enabled = true, endpoint = "/metrics", namespace = "gateway" }
    })
  }
}

resource "random_password" "gateway_api_key" {
  length  = 48
  special = false
}

resource "kubernetes_namespace" "ollama_namespace" {
  metadata {
    name = local.ollama.namespace
  }
}

resource "kubernetes_secret" "gateway_config" {
  metadata {
    name      = "gateway-config"
    namespace = local.ollama.namespace
  }
  type = "Opaque"
  data = {
    "config.json" = local.gateway.config
  }
}

resource "kubernetes_persistent_volume_claim" "ollama_pvc" {
  metadata {
    name      = local.ollama.volume_name
    namespace = local.ollama.namespace
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = local.ollama.storage_size
      }
    }
  }
}

resource "kubernetes_deployment" "ollama" {
  metadata {
    name      = "ollama"
    namespace = local.ollama.namespace
    labels    = { app = "ollama" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "ollama" } }
    template {
      metadata { labels = { app = "ollama" } }
      spec {

        container {
          name  = "ollama"
          image = local.ollama.image

          port {
            name           = "http"
            container_port = 11434
          }

          env {
            name  = "OLLAMA_HOST"
            value = "0.0.0.0:11434"
          }

          resources {
            limits = { "nvidia.com/gpu" = "1" }
          }

          volume_mount {
            name       = "ollama-data"
            mount_path = "/root/.ollama"
          }
        }

        volume {
          name = "ollama-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.ollama_pvc.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "ollama" {
  metadata {
    name      = "ollama"
    namespace = local.ollama.namespace
    labels    = { app = "ollama" }
  }
  spec {
    selector = { app = "ollama" }
    port {
      name        = "http"
      port        = 11434
      target_port = 11434
    }
  }
}

resource "kubernetes_deployment" "ollama_gateway" {
  metadata {
    name      = "ollama-gateway"
    namespace = local.ollama.namespace
    labels    = { app = "ollama-gateway" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "ollama-gateway" } }
    template {
      metadata { labels = { app = "ollama-gateway" } }
      spec {
        container {
          name  = "gateway"
          image = local.gateway.image
          port {
            name           = "http"
            container_port = 8080
          }
          volume_mount {
            name       = "cfg"
            mount_path = "/config.json"
            sub_path   = "config.json"
          }
        }
        volume {
          name = "cfg"
          secret {
            secret_name = kubernetes_secret.gateway_config.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "ollama_gateway" {
  metadata {
    name      = "ollama-gateway"
    namespace = local.ollama.namespace
    labels    = { app = "ollama-gateway" }
  }
  spec {
    selector = { app = "ollama-gateway" }
    port {
      name        = "http"
      port        = 80
      target_port = 8080
    }
  }
}



resource "kubernetes_ingress_v1" "ollama_gateway" {
  metadata {
    name      = "ollama-gateway"
    namespace = local.ollama.namespace
    annotations = {
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
      "cert-manager.io/cluster-issuer"                   = var.cluster_cert_issuer
    }
  }
  spec {
    ingress_class_name = "traefik"
    rule {
      host = local.gateway.host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.ollama_gateway.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
    tls {
      secret_name = "ollama-tls"
      hosts       = [local.gateway.host]
    }
  }
}

resource "kubernetes_job" "ollama_init" {
  depends_on = [
    kubernetes_deployment.ollama
  ]

  for_each = { for model in local.ollama.models : model => model }

  metadata {
    name      = "ollama-init-${replace(replace(each.value, ".", "-"), ":", "-")}"
    namespace = local.ollama.namespace
  }

  spec {
    # run exactly once, no retries
    completions   = 1
    parallelism   = 1
    backoff_limit = 0

    template {
      metadata {
        labels = {
          job = "ollama-init-${replace(replace(each.value, ".", "-"), ":", "-")}"
        }
      }

      spec {

        container {
          name  = "ollama-init"
          image = "alpine/curl"
          command = [
            "sh",
            "-c",
            "curl -s http://ollama.${local.ollama.namespace}.svc.cluster.local:11434/api/pull -d '{\"model\": \"${each.value}\"}'"
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
