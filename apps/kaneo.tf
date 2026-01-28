locals {
  kaneo = {
    namespace = "kaneo"
    host      = "kaneo.${var.base_domain}"
    tag       = ""

    postgres = {
      image   = "postgres:16"
      storage = "4Gi"
    }

    api = {
      image = "ghcr.io/usekaneo/api:2.1.23"
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

    web = {
      image = "ghcr.io/usekaneo/web:2.1.23"
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
  }
}

resource "kubernetes_namespace" "kaneo" {
  metadata {
    name = local.kaneo.namespace
  }
}

resource "random_password" "kaneo_auth_secret" {
  length  = 32
  special = false
}

resource "random_password" "kaneo_postgres_password" {
  length  = 32
  special = false
}

resource "random_password" "kaneo_client_id" {
  length  = 32
  special = false
}

resource "random_password" "kaneo_client_secret" {
  length  = 64
  special = true
}

resource "authentik_group" "kaneo_users" {
  depends_on = [helm_release.authentik]
  name       = "kaneo-users"
}

resource "authentik_policy_binding" "kaneo_access" {
  target = authentik_application.kaneo.uuid
  group  = authentik_group.kaneo_users.id
  order  = 0
}

resource "authentik_provider_oauth2" "kaneo" {
  depends_on = [helm_release.authentik]

  name                    = "kaneo"
  client_type             = "confidential"
  client_id               = random_password.kaneo_client_id.result
  client_secret           = random_password.kaneo_client_secret.result
  authorization_flow      = data.authentik_flow.default_authorization_flow.id
  invalidation_flow       = data.authentik_flow.default_invalidation_flow.id
  logout_method           = "backchannel"
  refresh_token_threshold = "seconds=0"

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "http://localhost:8080/api/auth/oauth2/callback/custom"
    },
    {
      matching_mode = "strict"
      url           = "https://${local.kaneo.host}/api/auth/oauth2/callback/custom"
    }
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.openid.id
  ]

  signing_key = data.authentik_certificate_key_pair.generated.id
}

resource "authentik_application" "kaneo" {
  name              = "kaneo"
  slug              = "kaneo-slug"
  protocol_provider = authentik_provider_oauth2.kaneo.id
  meta_icon         = "https://simpleicons.org/icons/jira.svg"
}

resource "kubernetes_secret" "kaneo_app" {
  metadata {
    name      = "kaneo-app-secret"
    namespace = local.kaneo.namespace
  }

  data = {
    POSTGRES_PASSWORD          = random_password.kaneo_postgres_password.result
    AUTH_SECRET                = random_password.kaneo_auth_secret.result
    CUSTOM_OAUTH_CLIENT_ID     = random_password.kaneo_client_id.result
    CUSTOM_OAUTH_CLIENT_SECRET = random_password.kaneo_client_secret.result
    DATABASE_URL               = "postgresql://kaneo:${random_password.kaneo_postgres_password.result}@kaneo-postgres.${local.kaneo.namespace}.svc.cluster.local:5432/kaneo"
  }

  type = "Opaque"
}

resource "kubernetes_stateful_set" "kaneo_postgres" {
  metadata {
    name      = "kaneo-postgres"
    namespace = local.kaneo.namespace
    labels = {
      app = "kaneo-postgres"
    }
  }

  spec {
    service_name = "kaneo-postgres"
    replicas     = 1

    selector {
      match_labels = {
        app = "kaneo-postgres"
      }
    }

    template {
      metadata {
        labels = {
          app = "kaneo-postgres"
        }
      }

      spec {
        container {
          name  = "postgres"
          image = local.kaneo.postgres.image

          port {
            name           = "postgres"
            container_port = 5432
          }

          env {
            name  = "POSTGRES_DB"
            value = "kaneo"
          }

          env {
            name  = "POSTGRES_USER"
            value = "kaneo"
          }

          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }

          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.kaneo_app.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
          }

          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "kaneo", "-d", "kaneo"]
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
          }

          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "kaneo", "-d", "kaneo"]
            }
            initial_delay_seconds = 20
            period_seconds        = 20
            timeout_seconds       = 5
          }

          volume_mount {
            name       = "postgres-data"
            mount_path = "/var/lib/postgresql/data"
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
            storage = local.kaneo.postgres.storage
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "kaneo_postgres" {
  metadata {
    name      = "kaneo-postgres"
    namespace = local.kaneo.namespace
  }

  spec {
    selector = {
      app = "kaneo-postgres"
    }

    port {
      name        = "postgres"
      port        = 5432
      target_port = 5432
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_deployment" "kaneo_api" {
  depends_on = [
    kubernetes_secret.kaneo_app,
    kubernetes_service.kaneo_postgres,
  ]

  metadata {
    name      = "kaneo-api"
    namespace = local.kaneo.namespace
    labels = {
      app = "kaneo-api"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "kaneo-api"
      }
    }

    template {
      metadata {
        labels = {
          app = "kaneo-api"
        }
      }

      spec {
        container {
          name  = "api"
          image = local.kaneo.api.image

          resources {
            limits   = local.kaneo.api.resources.limits
            requests = local.kaneo.api.resources.requests
          }

          port {
            name           = "http"
            container_port = 1337
          }

          env {
            name  = "KANEO_CLIENT_URL"
            value = "https://${local.kaneo.host}"
          }

          env {
            name  = "KANEO_API_URL"
            value = "https://${local.kaneo.host}"
          }

          env {
            name = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.kaneo_app.metadata[0].name
                key  = "DATABASE_URL"
              }
            }
          }

          env {
            name = "AUTH_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.kaneo_app.metadata[0].name
                key  = "AUTH_SECRET"
              }
            }
          }

          env {
            name  = "DISABLE_GUEST_ACCESS"
            value = "true"
          }

          env {
            name  = "DISABLE_REGISTRATION"
            value = "false"
          }

          env {
            name = "CUSTOM_OAUTH_CLIENT_ID"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.kaneo_app.metadata[0].name
                key  = "CUSTOM_OAUTH_CLIENT_ID"
              }
            }
          }

          env {
            name = "CUSTOM_OAUTH_CLIENT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.kaneo_app.metadata[0].name
                key  = "CUSTOM_OAUTH_CLIENT_SECRET"
              }
            }
          }

          env {
            name  = "CUSTOM_OAUTH_AUTHORIZATION_URL"
            value = "https://${local.authentik.host}/application/o/authorize/"
          }

          env {
            name  = "CUSTOM_OAUTH_TOKEN_URL"
            value = "https://${local.authentik.host}/application/o/token/"
          }

          env {
            name  = "CUSTOM_OAUTH_USER_INFO_URL"
            value = "https://${local.authentik.host}/application/o/userinfo/"
          }

          env {
            name  = "CUSTOM_OAUTH_SCOPES"
            value = "openid,profile,email"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "kaneo_api" {
  metadata {
    name      = "kaneo-api"
    namespace = local.kaneo.namespace
  }

  spec {
    selector = {
      app = "kaneo-api"
    }

    port {
      name        = "http"
      port        = 1337
      target_port = 1337
    }
  }
}

resource "kubernetes_deployment" "kaneo_web" {
  depends_on = [
    kubernetes_secret.kaneo_app,
    kubernetes_service.kaneo_api,
  ]

  metadata {
    name      = "kaneo-web"
    namespace = local.kaneo.namespace
    labels = {
      app = "kaneo-web"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "kaneo-web"
      }
    }

    template {
      metadata {
        labels = {
          app = "kaneo-web"
        }
      }

      spec {
        container {
          name  = "web"
          image = local.kaneo.web.image

          resources {
            limits   = local.kaneo.web.resources.limits
            requests = local.kaneo.web.resources.requests
          }

          port {
            name           = "http"
            container_port = 5173
          }

          env {
            name  = "KANEO_CLIENT_URL"
            value = "https://${local.kaneo.host}"
          }

          env {
            name  = "KANEO_API_URL"
            value = "https://${local.kaneo.host}"
          }

          env {
            name = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.kaneo_app.metadata[0].name
                key  = "DATABASE_URL"
              }
            }
          }

          env {
            name = "AUTH_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.kaneo_app.metadata[0].name
                key  = "AUTH_SECRET"
              }
            }
          }

          env {
            name  = "DISABLE_GUEST_ACCESS"
            value = "true"
          }

          env {
            name  = "DISABLE_REGISTRATION"
            value = "false"
          }

          env {
            name = "CUSTOM_OAUTH_CLIENT_ID"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.kaneo_app.metadata[0].name
                key  = "CUSTOM_OAUTH_CLIENT_ID"
              }
            }
          }

          env {
            name = "CUSTOM_OAUTH_CLIENT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.kaneo_app.metadata[0].name
                key  = "CUSTOM_OAUTH_CLIENT_SECRET"
              }
            }
          }

          env {
            name  = "CUSTOM_OAUTH_AUTHORIZATION_URL"
            value = "https://${local.authentik.host}/application/o/authorize/"
          }

          env {
            name  = "CUSTOM_OAUTH_TOKEN_URL"
            value = "https://${local.authentik.host}/application/o/token/"
          }

          env {
            name  = "CUSTOM_OAUTH_USER_INFO_URL"
            value = "https://${local.authentik.host}/application/o/userinfo/"
          }

          env {
            name  = "CUSTOM_OAUTH_SCOPES"
            value = "openid,profile,email"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "kaneo_web" {
  metadata {
    name      = "kaneo-web"
    namespace = local.kaneo.namespace
  }

  spec {
    selector = {
      app = "kaneo-web"
    }

    port {
      name        = "http"
      port        = 5173
      target_port = 5173
    }
  }
}

resource "kubernetes_ingress_v1" "kaneo" {
  depends_on = [
    kubernetes_service.kaneo_api,
    kubernetes_service.kaneo_web,
  ]

  metadata {
    name      = "kaneo"
    namespace = local.kaneo.namespace
    annotations = {
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
      "traefik.ingress.kubernetes.io/router.tls"         = "true"
      "cert-manager.io/cluster-issuer"                   = var.cluster_cert_issuer
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = local.kaneo.host

      http {
        path {
          path      = "/api"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.kaneo_api.metadata[0].name
              port {
                number = 1337
              }
            }
          }
        }

        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.kaneo_web.metadata[0].name
              port {
                number = 5173
              }
            }
          }
        }
      }
    }

    tls {
      secret_name = "kaneo-tls"
      hosts       = [local.kaneo.host]
    }
  }
}
