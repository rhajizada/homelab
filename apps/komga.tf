locals {
  komga = {
    namespace = "komga"
    host      = "komga.${var.base_domain}"
    image     = "gotson/komga:1.24.3"
    port      = 25600

    storage = {
      config = {
        size         = "512Mi"
        class        = "longhorn"
        access_modes = ["ReadWriteOnce"]
      }
      books = {
        size         = "16Gi"
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

    env = {
      TZ                = "America/New_York"
      JAVA_TOOL_OPTIONS = "-Xmx2g"
    }
  }
}

resource "kubernetes_namespace" "komga" {
  metadata {
    name = local.komga.namespace
  }
}

resource "random_password" "komga_client_id" {
  length  = 32
  special = false
}

resource "random_password" "komga_client_secret" {
  length  = 64
  special = false
}

resource "authentik_property_mapping_provider_scope" "komga_email" {
  depends_on = [helm_release.authentik]
  name       = "authentik komga OAuth Mapping: OpenID 'email'"
  expression = <<EOF
return {
    "email": request.user.email,
    "email_verified": True,
}
EOF
  scope_name = "email"
}

resource "authentik_group" "komga_users" {
  depends_on = [helm_release.authentik]
  name       = "komga-users"
}

resource "authentik_provider_oauth2" "komga" {
  depends_on = [
    helm_release.authentik,
    authentik_property_mapping_provider_scope.komga_email,
  ]

  name                    = "komga"
  client_type             = "confidential"
  client_id               = random_password.komga_client_id.result
  client_secret           = random_password.komga_client_secret.result
  authorization_flow      = data.authentik_flow.default_authorization_flow.id
  invalidation_flow       = data.authentik_flow.default_invalidation_flow.id
  logout_method           = "backchannel"
  refresh_token_threshold = "seconds=0"

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://${local.komga.host}/login/oauth2/code/authentik"
    }
  ]

  property_mappings = [
    authentik_property_mapping_provider_scope.komga_email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.openid.id,
  ]

  signing_key = data.authentik_certificate_key_pair.generated.id
}

resource "authentik_application" "komga" {
  name              = "Komga"
  slug              = "komga-slug"
  protocol_provider = authentik_provider_oauth2.komga.id
  meta_icon         = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/komga.svg"
}

resource "authentik_policy_binding" "komga_access" {
  target = authentik_application.komga.uuid
  group  = authentik_group.komga_users.id
  order  = 0
}

resource "kubernetes_secret" "komga_config" {
  depends_on = [kubernetes_namespace.komga]

  metadata {
    name      = "komga-config"
    namespace = local.komga.namespace
  }

  data = {
    "application.yml" = <<-YAML
      komga:
        oauth2-account-creation: true
        oidc-email-verification: true
      server:
        forward-headers-strategy: framework
        servlet:
          session:
            cookie:
              same-site: lax
      spring:
        security:
          oauth2:
            client:
              registration:
                authentik:
                  provider: authentik
                  client-id: "${random_password.komga_client_id.result}"
                  client-secret: "${random_password.komga_client_secret.result}"
                  client-name: "authentik"
                  scope: "openid,email,profile"
                  client-authentication-method: "client_secret_basic"
                  authorization-grant-type: "authorization_code"
                  redirect-uri: "{baseScheme}://{baseHost}{basePort}{basePath}/login/oauth2/code/{registrationId}"
              provider:
                authentik:
                  user-name-attribute: "sub"
                  issuer-uri: "https://${local.authentik.host}/application/o/komga-slug/"
    YAML
  }

  type = "Opaque"
}

resource "kubernetes_persistent_volume_claim" "komga_config" {
  depends_on = [kubernetes_namespace.komga]

  metadata {
    name      = "komga-config"
    namespace = local.komga.namespace
  }

  spec {
    storage_class_name = local.komga.storage.config.class
    access_modes       = local.komga.storage.config.access_modes

    resources {
      requests = {
        storage = local.komga.storage.config.size
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "komga_books" {
  depends_on = [kubernetes_namespace.komga]

  metadata {
    name      = "komga-books"
    namespace = local.komga.namespace
  }

  spec {
    storage_class_name = local.komga.storage.books.class
    access_modes       = local.komga.storage.books.access_modes

    resources {
      requests = {
        storage = local.komga.storage.books.size
      }
    }
  }
}

resource "kubernetes_deployment" "komga" {
  depends_on = [
    kubernetes_namespace.komga,
    kubernetes_secret.komga_config,
    kubernetes_persistent_volume_claim.komga_config,
    kubernetes_persistent_volume_claim.komga_books,
    authentik_application.komga,
  ]

  metadata {
    name      = "komga"
    namespace = local.komga.namespace
    labels    = { app = "komga" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "komga" }
    }

    template {
      metadata {
        labels = { app = "komga" }
      }

      spec {
        security_context {
          fs_group = 1000
        }

        container {
          name  = "komga"
          image = local.komga.image

          security_context {
            run_as_user  = 1000
            run_as_group = 1000
          }

          port {
            name           = "http"
            container_port = local.komga.port
          }

          dynamic "env" {
            for_each = local.komga.env
            content {
              name  = env.key
              value = env.value
            }
          }

          resources {
            requests = local.komga.resources.requests
            limits   = local.komga.resources.limits
          }

          readiness_probe {
            http_get {
              path = "/"
              port = local.komga.port
            }

            initial_delay_seconds = 15
            period_seconds        = 10
            timeout_seconds       = 5
          }

          liveness_probe {
            http_get {
              path = "/"
              port = local.komga.port
            }

            initial_delay_seconds = 30
            period_seconds        = 20
            timeout_seconds       = 5
          }

          volume_mount {
            name       = "config"
            mount_path = "/config"
          }

          volume_mount {
            name       = "application-config"
            mount_path = "/config/application.yml"
            sub_path   = "application.yml"
          }

          volume_mount {
            name       = "books"
            mount_path = "/data"
          }
        }

        volume {
          name = "config"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.komga_config.metadata[0].name
          }
        }

        volume {
          name = "application-config"

          secret {
            secret_name = kubernetes_secret.komga_config.metadata[0].name
          }
        }

        volume {
          name = "books"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.komga_books.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "komga" {
  depends_on = [kubernetes_namespace.komga]

  metadata {
    name      = "komga"
    namespace = local.komga.namespace
  }

  spec {
    selector = { app = "komga" }

    port {
      name        = "http"
      port        = 80
      target_port = local.komga.port
    }
  }
}

resource "kubernetes_ingress_v1" "komga" {
  depends_on = [
    kubernetes_namespace.komga,
    kubernetes_service.komga,
  ]

  metadata {
    name      = "komga"
    namespace = local.komga.namespace
    annotations = {
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
      "traefik.ingress.kubernetes.io/router.tls"         = "true"
      "cert-manager.io/cluster-issuer"                   = var.cluster_cert_issuer
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = local.komga.host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.komga.metadata[0].name

              port {
                number = 80
              }
            }
          }
        }
      }
    }

    tls {
      hosts       = [local.komga.host]
      secret_name = "komga-tls"
    }
  }
}
