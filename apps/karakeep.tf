locals {
  karakeep = {
    namespace = "karakeep"
    host      = "karakeep.${var.base_domain}"

    web = {
      image = "ghcr.io/karakeep-app/karakeep:0.30.0"
      resources = {
        requests = {
          cpu    = "500m"
          memory = "1Gi"
        }
        limits = {
          cpu    = "1"
          memory = "2Gi"
        }
      }
    }

    chrome = {
      image = "gcr.io/zenika-hub/alpine-chrome:124"
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

    meilisearch = {
      image = "getmeili/meilisearch:v1.13.3"
      resources = {
        requests = {
          cpu    = "500m"
          memory = "1Gi"
        }
        limits = {
          cpu    = "1"
          memory = "2Gi"
        }
      }
    }

    storage = {
      data  = "20Gi"
      meili = "16Gi"
    }
  }
}

resource "kubernetes_namespace" "karakeep" {
  metadata {
    name = local.karakeep.namespace
  }
}

resource "random_password" "karakeep_auth_secret" {
  length  = 32
  special = false
}

resource "random_password" "meili_master_key" {
  length  = 36
  special = false
}


resource "random_password" "karakeep_client_id" {
  length  = 32
  special = false
}

resource "random_password" "karakeep_client_secret" {
  length  = 64
  special = true
}

resource "authentik_group" "karakeep_users" {
  depends_on = [helm_release.authentik]
  name       = "karakeep-users"
}

resource "authentik_policy_binding" "karakeep_access" {
  target = authentik_application.karakeep.uuid
  group  = authentik_group.karakeep_users.id
  order  = 0
}

resource "authentik_provider_oauth2" "karakeep" {
  depends_on = [helm_release.authentik]

  name                    = "karakeep"
  client_type             = "public"
  client_id               = random_password.karakeep_client_id.result
  client_secret           = random_password.karakeep_client_secret.result
  authorization_flow      = data.authentik_flow.default_authorization_flow.id
  invalidation_flow       = data.authentik_flow.default_invalidation_flow.id
  logout_method           = "backchannel"
  refresh_token_threshold = "seconds=0"

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "http://localhost:3000/api/auth/callback/custom"
    },
    {
      matching_mode = "strict"
      url           = "https://${local.karakeep.host}/api/auth/callback/custom"
    }
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.openid.id
  ]

  signing_key = data.authentik_certificate_key_pair.generated.id
}

resource "authentik_application" "karakeep" {
  name              = "karakeep"
  slug              = "karakeep-slug"
  protocol_provider = authentik_provider_oauth2.karakeep.id
  meta_icon         = "https://simpleicons.org/icons/keeper.svg"
}

resource "kubernetes_secret" "karakeep_app" {
  metadata {
    name      = "karakeep-app"
    namespace = local.karakeep.namespace
  }

  data = {
    NEXTAUTH_SECRET     = random_password.karakeep_auth_secret.result
    MEILI_MASTER_KEY    = random_password.meili_master_key.result
    OAUTH_CLIENT_ID     = random_password.karakeep_client_id.result
    OAUTH_CLIENT_SECRET = random_password.karakeep_client_secret.result
  }

  type = "Opaque"
}

resource "kubernetes_persistent_volume_claim" "karakeep_data" {
  metadata {
    name      = "karakeep-data"
    namespace = local.karakeep.namespace
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = local.karakeep.storage.data
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "karakeep_meili_data" {
  metadata {
    name      = "karakeep-meili-data"
    namespace = local.karakeep.namespace
  }

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = local.karakeep.storage.meili
      }
    }
  }
}

resource "kubernetes_deployment" "karakeep_chrome" {
  depends_on = [
    kubernetes_namespace.karakeep
  ]

  metadata {
    name      = "karakeep-chrome"
    namespace = local.karakeep.namespace
    labels = {
      app = "karakeep-chrome"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "karakeep-chrome"
      }
    }

    template {
      metadata {
        labels = {
          app = "karakeep-chrome"
        }
      }

      spec {
        container {
          name  = "chrome"
          image = local.karakeep.chrome.image
          args = [
            "--no-sandbox",
            "--disable-gpu",
            "--disable-dev-shm-usage",
            "--remote-debugging-address=0.0.0.0",
            "--remote-debugging-port=9222",
            "--hide-scrollbars"
          ]
          port {
            name           = "debug"
            container_port = 9222
          }
          resources {
            limits   = local.karakeep.chrome.resources.limits
            requests = local.karakeep.chrome.resources.requests
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "karakeep_chrome" {
  metadata {
    name      = "karakeep-chrome"
    namespace = local.karakeep.namespace
  }

  spec {
    selector = {
      app = "karakeep-chrome"
    }

    port {
      name        = "debug"
      port        = 9222
      target_port = 9222
    }
  }
}

resource "kubernetes_deployment" "karakeep_meilisearch" {
  depends_on = [
    kubernetes_secret.karakeep_app,
    kubernetes_persistent_volume_claim.karakeep_meili_data
  ]

  metadata {
    name      = "karakeep-meilisearch"
    namespace = local.karakeep.namespace
    labels = {
      app = "karakeep-meilisearch"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "karakeep-meilisearch"
      }
    }

    template {
      metadata {
        labels = {
          app = "karakeep-meilisearch"
        }
      }

      spec {
        container {
          name  = "meilisearch"
          image = local.karakeep.meilisearch.image
          port {
            name           = "http"
            container_port = 7700
          }
          env {
            name = "MEILI_MASTER_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.karakeep_app.metadata[0].name
                key  = "MEILI_MASTER_KEY"
              }
            }
          }
          env {
            name  = "MEILI_NO_ANALYTICS"
            value = "true"
          }
          resources {
            limits   = local.karakeep.meilisearch.resources.limits
            requests = local.karakeep.meilisearch.resources.requests
          }
          volume_mount {
            name       = "meili-data"
            mount_path = "/meili_data"
          }
        }

        volume {
          name = "meili-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.karakeep_meili_data.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "karakeep_meilisearch" {
  metadata {
    name      = "karakeep-meilisearch"
    namespace = local.karakeep.namespace
  }

  spec {
    selector = {
      app = "karakeep-meilisearch"
    }

    port {
      name        = "http"
      port        = 7700
      target_port = 7700
    }
  }
}

resource "kubernetes_deployment" "karakeep_web" {
  depends_on = [
    kubernetes_secret.karakeep_app,
    kubernetes_service.karakeep_meilisearch,
    kubernetes_service.karakeep_chrome,
    kubernetes_persistent_volume_claim.karakeep_data
  ]

  metadata {
    name      = "karakeep-web"
    namespace = local.karakeep.namespace
    labels = {
      app = "karakeep-web"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "karakeep-web"
      }
    }

    template {
      metadata {
        labels = {
          app = "karakeep-web"
        }
      }

      spec {
        container {
          name  = "karakeep"
          image = local.karakeep.web.image
          port {
            name           = "http"
            container_port = 3000
          }
          env {
            name = "NEXTAUTH_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.karakeep_app.metadata[0].name
                key  = "NEXTAUTH_SECRET"
              }
            }
          }
          env {
            name  = "NEXTAUTH_URL"
            value = "https://${local.karakeep.host}"
          }
          env {
            name  = "DATA_DIR"
            value = "/data"
          }
          env {
            name  = "MEILI_ADDR"
            value = "http://karakeep-meilisearch.${local.karakeep.namespace}.svc.cluster.local:7700"
          }
          env {
            name = "MEILI_MASTER_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.karakeep_app.metadata[0].name
                key  = "MEILI_MASTER_KEY"
              }
            }
          }
          env {
            name  = "BROWSER_WEB_URL"
            value = "http://karakeep-chrome.${local.karakeep.namespace}.svc.cluster.local:9222"
          }
          env {
            name  = "OLLAMA_BASE_URL"
            value = "http://ollama.${local.llamero.namespace}.svc.cluster.local:11434"
          }
          env {
            name  = "INFERENCE_TEXT_MODEL"
            value = "llama3.1:8b"
          }
          env {
            name  = "INFERENCE_IMAGE_MODEL"
            value = "llava:7b"
          }
          env {
            name  = "EMBEDDING_TEXT_MODEL"
            value = "nomic-embed-text:latest"
          }
          env {
            name  = "DISABLE_SIGNUPS"
            value = "false"
          }
          env {
            name  = "DISABLE_PASSWORD_AUTH"
            value = "true"
          }
          env {
            name  = "EMAIL_VERIFICATION_REQUIRED"
            value = "false"
          }
          env {
            name  = "OAUTH_WELLKNOWN_URL"
            value = "https://${local.authentik.host}/application/o/karakeep-slug/.well-known/openid-configuration"
          }
          env {
            name = "OAUTH_CLIENT_ID"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.karakeep_app.metadata[0].name
                key  = "OAUTH_CLIENT_ID"
              }
            }
          }
          env {
            name = "OAUTH_CLIENT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.karakeep_app.metadata[0].name
                key  = "OAUTH_CLIENT_SECRET"
              }
            }
          }
          env {
            name  = "OAUTH_SCOPE"
            value = "openid email profile"
          }
          env {
            name  = "OAUTH_PROVIDER_NAME"
            value = "authentik"
          }
          env {
            name  = "OAUTH_ALLOW_DANGEROUS_EMAIL_ACCOUNT_LINKING"
            value = "false"
          }
          env {
            name  = "OAUTH_TIMEOUT"
            value = "3500"
          }
          resources {
            limits   = local.karakeep.web.resources.limits
            requests = local.karakeep.web.resources.requests
          }
          liveness_probe {
            http_get {
              path = "/"
              port = "http"
            }
            initial_delay_seconds = 20
            period_seconds        = 20
            timeout_seconds       = 5
          }
          readiness_probe {
            http_get {
              path = "/"
              port = "http"
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
          }
          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.karakeep_data.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "karakeep_web" {
  metadata {
    name      = "karakeep-web"
    namespace = local.karakeep.namespace
  }

  spec {
    selector = {
      app = "karakeep-web"
    }

    port {
      name        = "http"
      port        = 3000
      target_port = 3000
    }
  }
}

resource "kubernetes_ingress_v1" "karakeep" {
  metadata {
    name      = "karakeep"
    namespace = local.karakeep.namespace
    annotations = {
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
      "traefik.ingress.kubernetes.io/router.tls"         = "true"
      "cert-manager.io/cluster-issuer"                   = var.cluster_cert_issuer
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = local.karakeep.host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.karakeep_web.metadata[0].name
              port {
                number = 3000
              }
            }
          }
        }
      }
    }

    tls {
      secret_name = "karakeep-tls"
      hosts       = [local.karakeep.host]
    }
  }
}
