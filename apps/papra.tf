locals {
  papra = {
    namespace = "papra"
    host      = "papra.${var.base_domain}"
    image     = "ghcr.io/papra-hq/papra:26.4.0-rootless"
    port      = 1221

    storage = {
      app_data = {
        size         = "8Gi"
        class        = "longhorn"
        access_modes = ["ReadWriteOnce"]
      }
      documents = {
        size         = "256Gi"
        class        = "smb-private"
        access_modes = ["ReadWriteMany"]
      }
    }

    resources = {
      requests = {
        cpu    = "500m"
        memory = "1Gi"
      }
      limits = {
        cpu    = "2"
        memory = "4Gi"
      }
    }
  }
}

resource "kubernetes_namespace" "papra" {
  metadata {
    name = local.papra.namespace
  }
}

resource "random_password" "papra_auth_secret" {
  length  = 64
  special = false
}

resource "random_password" "papra_database_encryption_key" {
  length  = 64
  special = false
}

resource "random_password" "papra_client_id" {
  length  = 32
  special = false
}

resource "random_password" "papra_client_secret" {
  length  = 64
  special = true
}

resource "authentik_group" "papra_users" {
  depends_on = [helm_release.authentik]
  name       = "papra-users"
}

resource "authentik_provider_oauth2" "papra" {
  depends_on = [
    helm_release.authentik,
  ]

  name                    = "papra"
  client_type             = "confidential"
  client_id               = random_password.papra_client_id.result
  client_secret           = random_password.papra_client_secret.result
  authorization_flow      = data.authentik_flow.default_authorization_flow.id
  invalidation_flow       = data.authentik_flow.default_invalidation_flow.id
  logout_method           = "backchannel"
  refresh_token_threshold = "seconds=0"

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://${local.papra.host}/api/auth/oauth2/callback/authentik"
    }
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.openid.id,
  ]

  signing_key = data.authentik_certificate_key_pair.generated.id
}

resource "authentik_application" "papra" {
  name              = "Papra"
  slug              = "papra-slug"
  protocol_provider = authentik_provider_oauth2.papra.id
  meta_icon         = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/papra.svg"
}

resource "authentik_policy_binding" "papra_access" {
  target = authentik_application.papra.uuid
  group  = authentik_group.papra_users.id
  order  = 0
}

resource "kubernetes_secret" "papra_app" {
  depends_on = [kubernetes_namespace.papra]

  metadata {
    name      = "papra-app"
    namespace = local.papra.namespace
  }

  data = {
    APP_BASE_URL                         = "https://${local.papra.host}"
    PORT                                 = tostring(local.papra.port)
    SERVER_HOSTNAME                      = "0.0.0.0"
    SERVER_SERVE_PUBLIC_DIR              = "true"
    AUTH_SECRET                          = random_password.papra_auth_secret.result
    AUTH_FIRST_USER_AS_ADMIN             = "true"
    AUTH_IS_REGISTRATION_ENABLED         = "false"
    AUTH_IS_PASSWORD_RESET_ENABLED       = "false"
    AUTH_IS_EMAIL_VERIFICATION_REQUIRED  = "false"
    AUTH_SHOW_LEGAL_LINKS                = "false"
    AUTH_PROVIDERS_EMAIL_IS_ENABLED      = "false"
    AUTH_IP_ADDRESS_HEADERS              = "x-forwarded-for"
    AUTH_PROVIDERS_CUSTOMS               = jsonencode([{ providerId = "authentik", providerName = "Authentik", type = "oidc", discoveryUrl = "https://${local.authentik.host}/application/o/papra-slug/.well-known/openid-configuration", clientId = random_password.papra_client_id.result, clientSecret = random_password.papra_client_secret.result, scopes = ["openid", "profile", "email"], pkce = true }])
    DATABASE_URL                         = "file:/app/app-data/db/db.sqlite"
    DATABASE_ENCRYPTION_KEY              = random_password.papra_database_encryption_key.result
    TASKS_PERSISTENCE_DRIVER             = "libsql"
    TASKS_PERSISTENCE_DRIVERS_LIBSQL_URL = "file:/app/app-data/tasks-db.sqlite"
    DOCUMENT_STORAGE_DRIVER              = "filesystem"
    DOCUMENT_STORAGE_FILESYSTEM_ROOT     = "/documents"
    DOCUMENT_STORAGE_MAX_UPLOAD_SIZE     = "0"
    DOCUMENTS_OCR_LANGUAGES              = "aze,eng,rus"
  }

  type = "Opaque"
}

resource "kubernetes_persistent_volume_claim" "papra_app_data" {
  depends_on = [kubernetes_namespace.papra]

  metadata {
    name      = "papra-app-data"
    namespace = local.papra.namespace
  }

  spec {
    storage_class_name = local.papra.storage.app_data.class
    access_modes       = local.papra.storage.app_data.access_modes

    resources {
      requests = {
        storage = local.papra.storage.app_data.size
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "papra_documents" {
  depends_on = [kubernetes_namespace.papra]

  metadata {
    name      = "papra-documents"
    namespace = local.papra.namespace
  }

  spec {
    storage_class_name = local.papra.storage.documents.class
    access_modes       = local.papra.storage.documents.access_modes

    resources {
      requests = {
        storage = local.papra.storage.documents.size
      }
    }
  }
}

resource "kubernetes_deployment" "papra" {
  depends_on = [
    kubernetes_secret.papra_app,
    kubernetes_persistent_volume_claim.papra_app_data,
    kubernetes_persistent_volume_claim.papra_documents,
    authentik_application.papra,
  ]

  metadata {
    name      = "papra"
    namespace = local.papra.namespace
    labels = {
      app = "papra"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "papra"
      }
    }

    template {
      metadata {
        labels = {
          app = "papra"
        }
      }

      spec {
        security_context {
          run_as_user  = 1000
          run_as_group = 1000
          fs_group     = 1000
        }

        container {
          name              = "papra"
          image             = local.papra.image
          image_pull_policy = "IfNotPresent"

          port {
            name           = "http"
            container_port = local.papra.port
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.papra_app.metadata[0].name
            }
          }

          resources {
            limits   = local.papra.resources.limits
            requests = local.papra.resources.requests
          }

          liveness_probe {
            http_get {
              path = "/"
              port = "http"
            }
            initial_delay_seconds = 30
            period_seconds        = 20
            timeout_seconds       = 5
          }

          readiness_probe {
            http_get {
              path = "/"
              port = "http"
            }
            initial_delay_seconds = 15
            period_seconds        = 10
            timeout_seconds       = 5
          }

          volume_mount {
            name       = "app-data"
            mount_path = "/app/app-data"
          }

          volume_mount {
            name       = "documents"
            mount_path = "/documents"
          }
        }

        volume {
          name = "app-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.papra_app_data.metadata[0].name
          }
        }

        volume {
          name = "documents"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.papra_documents.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "papra" {
  metadata {
    name      = "papra"
    namespace = local.papra.namespace
  }

  spec {
    selector = {
      app = "papra"
    }

    port {
      name        = "http"
      port        = local.papra.port
      target_port = local.papra.port
    }
  }
}

resource "kubernetes_ingress_v1" "papra" {
  depends_on = [kubernetes_service.papra]

  metadata {
    name      = "papra"
    namespace = local.papra.namespace
    annotations = {
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
      "traefik.ingress.kubernetes.io/router.tls"         = "true"
      "cert-manager.io/cluster-issuer"                   = var.cluster_cert_issuer
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = local.papra.host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.papra.metadata[0].name
              port {
                number = local.papra.port
              }
            }
          }
        }
      }
    }

    tls {
      secret_name = "papra-tls"
      hosts       = [local.papra.host]
    }
  }
}
