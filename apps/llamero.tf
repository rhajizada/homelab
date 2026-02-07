locals {
  llamero = {
    namespace = "llamero"
    host      = "llamero.${var.base_domain}"
    tag       = ""

    postgres = {
      image   = "postgres:18"
      storage = "1Gi"
    }

    redis = {
      image   = "redis:8"
      storage = "1Gi"
    }

    server = {
      image = "ghcr.io/rhajizada/llamero/server:v0.1.2"
      resources = {
        requests = {
          cpu    = "200m"
          memory = "256Mi"
        }
        limits = {
          cpu    = "750m"
          memory = "512Mi"
        }
      }
    }

    worker = {
      image = "ghcr.io/rhajizada/llamero/worker:v0.1.2"
      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "256Mi"
        }
      }
    }

    scheduler = {
      image = "ghcr.io/rhajizada/llamero/scheduler:v0.1.2"
      resources = {
        requests = {
          cpu    = "50m"
          memory = "64Mi"
        }
        limits = {
          cpu    = "250m"
          memory = "128Mi"
        }
      }
    }

    ui = {
      image = "ghcr.io/rhajizada/llamero/ui:v0.1.2"
      resources = {
        requests = {
          cpu    = "250m"
          memory = "375Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "750Mi"
        }
      }
    }

    ollama = {
      image       = "ollama/ollama:latest"
      storage     = "128Gi"
      volume_name = "ollama-pv"
      models = [
        "deepseek-r1:14b",
        "gemma3:12b",
        "gpt-oss:20b",
        "llama3.1:8b",
        "llama3.2:3b",
        "nomic-embed-text",
        "qwen3:14b"
      ]
    }

    groups = ["llamero-admins", "llamero-users"]
  }
}

resource "kubernetes_namespace" "llamero" {
  metadata {
    name = local.llamero.namespace
  }
}

resource "random_password" "llamero_client_id" {
  length  = 32
  special = false
}

resource "random_password" "llamero_client_secret" {
  length  = 64
  special = true
}

resource "authentik_group" "llamero_groups" {
  depends_on = [helm_release.authentik]
  for_each   = toset(local.llamero.groups)
  name       = each.value
}

resource "authentik_provider_oauth2" "llamero" {
  depends_on = [helm_release.authentik]

  name                    = "llamero"
  client_type             = "confidential"
  client_id               = random_password.llamero_client_id.result
  client_secret           = random_password.llamero_client_secret.result
  authorization_flow      = data.authentik_flow.default_authorization_flow.id
  invalidation_flow       = data.authentik_flow.default_invalidation_flow.id
  logout_method           = "backchannel"
  refresh_token_threshold = "seconds=0"

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://${local.llamero.host}/auth/callback"
    },
    {
      matching_mode = "strict"
      url           = "http://localhost:8080/auth/callback"
    }
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.openid.id
  ]

  signing_key = data.authentik_certificate_key_pair.generated.id
}

resource "authentik_application" "llamero" {
  name              = "Llamero"
  slug              = "llamero-slug"
  protocol_provider = authentik_provider_oauth2.llamero.id
  meta_icon         = "https://simpleicons.org/icons/ollama.svg"
}

resource "tls_private_key" "llamero_jwt" {
  algorithm = "ED25519"
}

resource "kubernetes_secret" "llamero_jwt_keys" {
  metadata {
    name      = "llamero-jwt-keys"
    namespace = local.llamero.namespace
  }

  data = {
    "jwt_private.pem" = tls_private_key.llamero_jwt.private_key_pem
    "jwt_public.pem"  = tls_private_key.llamero_jwt.public_key_pem
  }
}

resource "random_password" "postgres_password" {
  length  = 32
  special = false
}

resource "random_password" "redis_password" {
  length  = 32
  special = false
}

resource "kubernetes_secret" "llamero_app" {
  metadata {
    name      = "llamero-app-secret"
    namespace = local.llamero.namespace
  }

  data = {
    LLAMERO_OAUTH_CLIENT_ID     = random_password.llamero_client_id.result
    LLAMERO_OAUTH_CLIENT_SECRET = random_password.llamero_client_secret.result
    LLAMERO_POSTGRES_PASSWORD   = random_password.postgres_password.result
    LLAMERO_REDIS_PASSWORD      = random_password.redis_password.result
  }
}

resource "kubernetes_config_map" "llamero_roles" {
  metadata {
    name      = "llamero-roles"
    namespace = local.llamero.namespace
  }

  data = {
    "roles.yaml" = <<EOF
default_role: user
roles:
  - name: admin
    scopes:
      - backends:list
      - backends:listModels
      - backends:ps
      - backends:createModel
      - backends:pullModel
      - backends:pushModel
      - backends:deleteModel
      - models:list
      - llm:chat
      - llm:embeddings
      - profile:get
  - name: user
    scopes:
      - models:list
      - llm:chat
      - llm:embeddings
      - profile:get
EOF
  }
}

resource "kubernetes_config_map" "llamero_backends" {
  metadata {
    name      = "llamero-backends"
    namespace = local.llamero.namespace
  }

  data = {
    "backends.yaml" = <<EOF
backends:
  - id: ollama
    address: http://ollama.${local.llamero.namespace}.svc.cluster.local:11434
    tags:
      - gpu
EOF
  }
}

resource "kubernetes_stateful_set" "postgres" {
  metadata {
    name      = "llamero-postgres"
    namespace = local.llamero.namespace
  }

  spec {
    service_name = "llamero-postgres"
    replicas     = 1

    selector {
      match_labels = {
        app = "llamero-postgres"
      }
    }

    template {
      metadata {
        labels = {
          app = "llamero-postgres"
        }
      }

      spec {
        container {
          name  = "postgres"
          image = local.llamero.postgres.image

          env {
            name  = "POSTGRES_DB"
            value = "llamero"
          }

          env {
            name  = "POSTGRES_USER"
            value = "llamero"
          }

          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.llamero_app.metadata[0].name
                key  = "LLAMERO_POSTGRES_PASSWORD"
              }
            }
          }

          port {
            name           = "postgres"
            container_port = 5432
          }


          volume_mount {
            name       = "postgres-data"
            mount_path = "/var/lib/postgresql"

          }

        }
      }
    }

    volume_claim_template {
      metadata {
        name = "postgres-data"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = local.llamero.postgres.storage
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "postgres" {
  metadata {
    name      = "llamero-postgres"
    namespace = local.llamero.namespace
  }

  spec {
    selector = {
      app = "llamero-postgres"
    }

    port {
      name        = "postgres"
      port        = 5432
      target_port = 5432
    }
  }
}

resource "kubernetes_stateful_set" "redis" {
  metadata {
    name      = "llamero-redis"
    namespace = local.llamero.namespace
  }

  spec {
    service_name = "llamero-redis"
    replicas     = 1

    selector {
      match_labels = {
        app = "llamero-redis"
      }
    }

    template {
      metadata {
        labels = {
          app = "llamero-redis"
        }
      }

      spec {
        security_context {
          fs_group = 999
        }

        container {
          name  = "redis"
          image = local.llamero.redis.image

          args = [
            "--requirepass", random_password.redis_password.result,
          ]

          port {
            name           = "redis"
            container_port = 6379
          }

          volume_mount {
            name       = "redis-data"
            mount_path = "/data"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "redis-data"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = local.llamero.redis.storage
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "redis" {
  metadata {
    name      = "llamero-redis"
    namespace = local.llamero.namespace
  }

  spec {
    selector = {
      app = "llamero-redis"
    }

    port {
      name        = "redis"
      port        = 6379
      target_port = 6379
    }
  }
}


resource "kubernetes_deployment" "llamero_server" {
  metadata {
    name      = "llamero-server"
    namespace = local.llamero.namespace
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "llamero-server"
      }
    }

    template {
      metadata {
        labels = {
          app = "llamero-server"
        }
      }

      spec {
        volume {
          name = "jwt-keys"
          secret {
            secret_name = kubernetes_secret.llamero_jwt_keys.metadata[0].name
          }
        }

        volume {
          name = "roles"
          config_map {
            name = kubernetes_config_map.llamero_roles.metadata[0].name
          }
        }

        volume {
          name = "backends"
          config_map {
            name = kubernetes_config_map.llamero_backends.metadata[0].name
          }
        }

        container {
          name  = "server"
          image = local.llamero.server.image

          resources {
            limits   = local.llamero.server.resources.limits
            requests = local.llamero.server.resources.requests
          }

          port {
            name           = "http"
            container_port = 8080
          }

          env {
            name  = "LLAMERO_SERVER_ADDRESS"
            value = ":8080"
          }
          env {
            name  = "LLAMERO_SERVER_EXTERNAL_URL"
            value = "https://${local.llamero.host}"
          }
          env {
            name  = "LLAMERO_JWT_SIGNING_METHOD"
            value = "EdDSA"
          }
          env {
            name  = "LLAMERO_JWT_PRIVATE_KEY_PATH"
            value = "/app/secrets/jwt_private.pem"
          }
          env {
            name  = "LLAMERO_JWT_PUBLIC_KEY_PATH"
            value = "/app/secrets/jwt_public.pem"
          }
          env {
            name  = "LLAMERO_JWT_TTL"
            value = "1h"
          }
          env {
            name  = "LLAMERO_BACKENDS_FILE"
            value = "/app/config/backends.yaml"
          }
          env {
            name = "LLAMERO_OAUTH_CLIENT_ID"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.llamero_app.metadata[0].name
                key  = "LLAMERO_OAUTH_CLIENT_ID"
              }
            }
          }
          env {
            name = "LLAMERO_OAUTH_CLIENT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.llamero_app.metadata[0].name
                key  = "LLAMERO_OAUTH_CLIENT_SECRET"
              }
            }
          }
          env {
            name  = "LLAMERO_OAUTH_AUTHORIZE_URL"
            value = "https://${local.authentik.host}/application/o/authorize/"
          }
          env {
            name  = "LLAMERO_OAUTH_TOKEN_URL"
            value = "https://${local.authentik.host}/application/o/token/"
          }
          env {
            name  = "LLAMERO_OAUTH_USERINFO_URL"
            value = "https://${local.authentik.host}/application/o/userinfo/"
          }
          env {
            name  = "LLAMERO_OAUTH_REDIRECT_URL"
            value = "https://${local.llamero.host}/auth/callback"
          }
          env {
            name  = "LLAMERO_ROLE_GROUPS"
            value = "admin=llamero-admins;user=llamero-users"
          }
          env {
            name  = "LLAMERO_POSTGRES_HOST"
            value = "llamero-postgres.${local.llamero.namespace}.svc.cluster.local"
          }
          env {
            name  = "LLAMERO_POSTGRES_PORT"
            value = "5432"
          }
          env {
            name  = "LLAMERO_POSTGRES_USER"
            value = "llamero"
          }
          env {
            name = "LLAMERO_POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.llamero_app.metadata[0].name
                key  = "LLAMERO_POSTGRES_PASSWORD"
              }
            }
          }
          env {
            name  = "LLAMERO_POSTGRES_DBNAME"
            value = "llamero"
          }
          env {
            name  = "LLAMERO_POSTGRES_SSLMODE"
            value = "disable"
          }

          env {
            name  = "LLAMERO_REDIS_ADDR"
            value = "llamero-redis.${local.llamero.namespace}.svc.cluster.local:6379"
          }
          env {
            name = "LLAMERO_REDIS_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.llamero_app.metadata[0].name
                key  = "LLAMERO_REDIS_PASSWORD"
              }
            }
          }

          volume_mount {
            name       = "jwt-keys"
            mount_path = "/app/secrets"
            read_only  = true
          }

          volume_mount {
            name       = "roles"
            mount_path = "/app/config/roles.yaml"
            sub_path   = "roles.yaml"
            read_only  = true
          }

          volume_mount {
            name       = "backends"
            mount_path = "/app/config/backends.yaml"
            sub_path   = "backends.yaml"
            read_only  = true
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = "http"
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 2
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = "http"
            }
            initial_delay_seconds = 3
            period_seconds        = 10
            timeout_seconds       = 2
          }
        }
      }
    }
  }
}


resource "kubernetes_service" "llamero_server" {
  metadata {
    name      = "llamero-server"
    namespace = local.llamero.namespace
  }

  spec {
    selector = {
      app = "llamero-server"
    }

    port {
      name        = "http"
      port        = 8080
      target_port = 8080
    }
  }
}


resource "kubernetes_deployment" "llamero_worker" {
  metadata {
    name      = "llamero-worker"
    namespace = local.llamero.namespace
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "llamero-worker"
      }
    }

    template {
      metadata {
        labels = {
          app = "llamero-worker"
        }
      }

      spec {
        container {
          name  = "worker"
          image = local.llamero.worker.image

          resources {
            limits   = local.llamero.worker.resources.limits
            requests = local.llamero.worker.resources.requests
          }

          env {
            name  = "LLAMERO_POSTGRES_HOST"
            value = "llamero-postgres.${local.llamero.namespace}.svc.cluster.local"
          }
          env {
            name  = "LLAMERO_POSTGRES_PORT"
            value = "5432"
          }
          env {
            name  = "LLAMERO_POSTGRES_USER"
            value = "llamero"
          }
          env {
            name = "LLAMERO_POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.llamero_app.metadata[0].name
                key  = "LLAMERO_POSTGRES_PASSWORD"
              }
            }
          }
          env {
            name  = "LLAMERO_POSTGRES_DBNAME"
            value = "llamero"
          }
          env {
            name  = "LLAMERO_POSTGRES_SSLMODE"
            value = "disable"
          }

          env {
            name  = "LLAMERO_REDIS_ADDR"
            value = "llamero-redis.${local.llamero.namespace}.svc.cluster.local:6379"
          }
          env {
            name = "LLAMERO_REDIS_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.llamero_app.metadata[0].name
                key  = "LLAMERO_REDIS_PASSWORD"
              }
            }
          }
          env {
            name  = "LLAMERO_WORKER_CONCURRENCY"
            value = "5"
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment" "llamero_scheduler" {
  metadata {
    name      = "llamero-scheduler"
    namespace = local.llamero.namespace
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "llamero-scheduler"
      }
    }

    template {
      metadata {
        labels = {
          app = "llamero-scheduler"
        }
      }

      spec {
        container {
          name  = "scheduler"
          image = local.llamero.scheduler.image

          resources {
            limits   = local.llamero.scheduler.resources.limits
            requests = local.llamero.scheduler.resources.requests
          }

          env {
            name  = "LLAMERO_REDIS_ADDR"
            value = "llamero-redis.${local.llamero.namespace}.svc.cluster.local:6379"
          }
          env {
            name = "LLAMERO_REDIS_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.llamero_app.metadata[0].name
                key  = "LLAMERO_REDIS_PASSWORD"
              }
            }
          }
          env {
            name  = "LLAMERO_SCHEDULER_PING_SPEC"
            value = "@every 5m"
          }
        }
      }
    }
  }
}


resource "kubernetes_deployment" "llamero_ui" {
  metadata {
    name      = "llamero-ui"
    namespace = local.llamero.namespace
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "llamero-ui"
      }
    }

    template {
      metadata {
        labels = {
          app = "llamero-ui"
        }
      }

      spec {
        container {
          name  = "ui"
          image = local.llamero.ui.image

          resources {
            limits   = local.llamero.ui.resources.limits
            requests = local.llamero.ui.resources.requests
          }

          env {
            name  = "NEXT_TELEMETRY_DISABLED"
            value = "1"
          }
          env {
            name  = "HOST"
            value = "0.0.0.0"
          }
          env {
            name  = "PORT"
            value = "3000"
          }

          port {
            name           = "http"
            container_port = 3000
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "llamero_ui" {
  metadata {
    name      = "llamero-ui"
    namespace = local.llamero.namespace
  }

  spec {
    selector = {
      app = "llamero-ui"
    }

    port {
      name        = "http"
      port        = 3000
      target_port = 3000
    }
  }
}

resource "kubernetes_persistent_volume_claim" "ollama_pvc" {
  metadata {
    name      = local.llamero.ollama.volume_name
    namespace = local.llamero.namespace
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = local.llamero.ollama.storage
      }
    }
  }
}

resource "kubernetes_deployment" "ollama" {
  metadata {
    name      = "ollama"
    namespace = local.llamero.namespace
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "ollama"
      }
    }

    template {
      metadata {
        labels = {
          app = "ollama"
        }
      }

      spec {
        container {
          name              = "ollama"
          image             = local.llamero.ollama.image
          image_pull_policy = "Always"

          port {
            name           = "http"
            container_port = 11434
          }

          env {
            name  = "OLLAMA_HOST"
            value = "0.0.0.0:11434"
          }

          resources {
            limits = {
              "nvidia.com/gpu" = "1"
            }
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
    namespace = local.llamero.namespace
  }

  spec {
    selector = {
      app = "ollama"
    }

    port {
      name        = "http"
      port        = 11434
      target_port = 11434
    }
  }
}

resource "kubernetes_job" "ollama_init" {
  depends_on = [
    kubernetes_deployment.ollama
  ]

  for_each = { for model in local.llamero.ollama.models : model => model }

  metadata {
    name      = "ollama-init-${replace(replace(each.value, ".", "-"), ":", "-")}"
    namespace = local.llamero.namespace
  }

  spec {
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
            "curl -s http://ollama.${local.llamero.namespace}.svc.cluster.local:11434/api/pull -d '{\"model\": \"${each.value}\"}'"
          ]
        }

        restart_policy = "Never"
      }
    }
  }

  timeouts {
    create = "1h"
    delete = "1h"
  }
}

resource "kubernetes_ingress_v1" "llamero" {
  metadata {
    name      = "llamero"
    namespace = local.llamero.namespace

    annotations = {
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
      "traefik.ingress.kubernetes.io/router.tls"         = "true"
      "cert-manager.io/cluster-issuer"                   = var.cluster_cert_issuer
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = local.llamero.host

      http {

        path {
          path      = "/api"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.llamero_server.metadata[0].name
              port {
                number = 8080
              }
            }
          }
        }

        path {
          path      = "/auth"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.llamero_server.metadata[0].name
              port {
                number = 8080
              }
            }
          }
        }

        path {
          path      = "/healthz"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.llamero_server.metadata[0].name
              port {
                number = 8080
              }
            }
          }
        }

        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.llamero_ui.metadata[0].name
              port {
                number = 3000
              }
            }
          }
        }
      }
    }

    tls {
      secret_name = "llamero-tls"
      hosts       = [local.llamero.host]
    }
  }
}
