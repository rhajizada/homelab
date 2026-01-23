locals {
  bitmagnet = {
    namespace      = "bitmagnet"
    host           = "bitmagnet.${var.base_domain}"
    image          = "ghcr.io/bitmagnet-io/bitmagnet:latest"
    postgres_image = "postgres:16-alpine"
    storage = {
      config   = "2Gi"
      postgres = "64Gi"
    }
    resources = {
      requests = {
        cpu    = "250m"
        memory = "512Mi"
      }
      limits = {
        cpu    = "1"
        memory = "2Gi"
      }
    }
  }
}

resource "authentik_provider_proxy" "bitmagnet" {
  depends_on         = [helm_release.authentik]
  name               = "bitmagnet"
  external_host      = "https://${local.bitmagnet.host}"
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id
  mode               = "forward_single"
}

resource "authentik_application" "bitmagnet" {
  name              = "bitmagnet"
  slug              = "bitmagnet-slug"
  protocol_provider = authentik_provider_proxy.bitmagnet.id
  meta_icon         = "https://simpleicons.org/icons/bittorrent.svg"
}

resource "authentik_group" "bitmagnet_users" {
  depends_on = [helm_release.authentik]
  name       = "bitmagnet-users"
}

resource "authentik_policy_binding" "bitmagnet_access" {
  target = authentik_application.bitmagnet.uuid
  group  = authentik_group.bitmagnet_users.id
  order  = 0
}

resource "authentik_outpost_provider_attachment" "bitmagnet" {
  outpost           = data.authentik_outpost.embedded.id
  protocol_provider = authentik_provider_proxy.bitmagnet.id
}

resource "kubernetes_namespace" "bitmagnet" {
  metadata {
    name = local.bitmagnet.namespace
  }
}

resource "random_password" "bitmagnet_postgres_password" {
  length  = 32
  special = false
}

resource "kubernetes_secret" "bitmagnet_postgres" {
  metadata {
    name      = "bitmagnet-postgres-secret"
    namespace = local.bitmagnet.namespace
  }

  data = {
    POSTGRES_PASSWORD = random_password.bitmagnet_postgres_password.result
  }

  type = "Opaque"
}

resource "kubernetes_persistent_volume_claim" "bitmagnet_config" {
  metadata {
    name      = "bitmagnet-config"
    namespace = local.bitmagnet.namespace
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = local.bitmagnet.storage.config
      }
    }
  }
}

resource "kubernetes_stateful_set" "bitmagnet_postgres" {
  metadata {
    name      = "bitmagnet-postgres"
    namespace = local.bitmagnet.namespace
    labels = {
      app = "bitmagnet-postgres"
    }
  }
  spec {
    service_name = "bitmagnet-postgres"
    replicas     = 1
    selector {
      match_labels = {
        app = "bitmagnet-postgres"
      }
    }
    template {
      metadata {
        labels = {
          app = "bitmagnet-postgres"
        }
      }
      spec {
        container {
          name  = "postgres"
          image = local.bitmagnet.postgres_image
          port {
            name           = "postgres"
            container_port = 5432
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.bitmagnet_postgres.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
          }
          env {
            name  = "POSTGRES_DB"
            value = "bitmagnet"
          }
          env {
            name  = "POSTGRES_USER"
            value = "postgres"
          }
          env {
            name  = "PGUSER"
            value = "postgres"
          }
          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }
          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "postgres"]
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
          }
          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "postgres"]
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
            storage = local.bitmagnet.storage.postgres
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "bitmagnet_postgres" {
  metadata {
    name      = "bitmagnet-postgres"
    namespace = local.bitmagnet.namespace
  }
  spec {
    selector = {
      app = "bitmagnet-postgres"
    }
    port {
      name        = "postgres"
      port        = 5432
      target_port = 5432
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_deployment" "bitmagnet" {
  depends_on = [
    kubernetes_service.bitmagnet_postgres,
    kubernetes_persistent_volume_claim.bitmagnet_config,
  ]

  metadata {
    name      = "bitmagnet"
    namespace = local.bitmagnet.namespace
    labels = {
      app = "bitmagnet"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "bitmagnet"
      }
    }
    template {
      metadata {
        labels = {
          app = "bitmagnet"
        }
      }
      spec {
        container {
          name  = "bitmagnet"
          image = local.bitmagnet.image
          args = [
            "worker",
            "run",
            "--keys=http_server",
            "--keys=queue_server",
            "--keys=dht_crawler",
          ]
          port {
            name           = "http"
            container_port = 3333
          }
          port {
            name           = "bittorrent-tcp"
            container_port = 3334
            protocol       = "TCP"
          }
          port {
            name           = "bittorrent-udp"
            container_port = 3334
            protocol       = "UDP"
          }
          env {
            name  = "POSTGRES_HOST"
            value = kubernetes_service.bitmagnet_postgres.metadata[0].name
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.bitmagnet_postgres.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
          }
          env {
            name  = "POSTGRES_USER"
            value = "postgres"
          }
          env {
            name  = "POSTGRES_DB"
            value = "bitmagnet"
          }
          resources {
            limits   = local.bitmagnet.resources.limits
            requests = local.bitmagnet.resources.requests
          }
          readiness_probe {
            http_get {
              path = "/"
              port = "http"
            }
            initial_delay_seconds = 10
            period_seconds        = 15
            timeout_seconds       = 5
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
          volume_mount {
            name       = "config"
            mount_path = "/root/.config/bitmagnet"
          }
        }
        volume {
          name = "config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.bitmagnet_config.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "bitmagnet" {
  metadata {
    name      = "bitmagnet"
    namespace = local.bitmagnet.namespace
  }
  spec {
    selector = {
      app = "bitmagnet"
    }
    port {
      name        = "http"
      port        = 3333
      target_port = 3333
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_service" "bitmagnet_bittorrent" {
  metadata {
    name      = "bitmagnet-bittorrent"
    namespace = local.bitmagnet.namespace
  }
  spec {
    selector = {
      app = "bitmagnet"
    }
    port {
      name        = "bittorrent-tcp"
      port        = 3334
      target_port = 3334
      protocol    = "TCP"
    }
    port {
      name        = "bittorrent-udp"
      port        = 3334
      target_port = 3334
      protocol    = "UDP"
    }
  }
}

resource "kubernetes_service" "bitmagnet_outpost" {
  metadata {
    name      = "bitmagnet-outpost"
    namespace = local.bitmagnet.namespace
  }
  spec {
    type          = "ExternalName"
    external_name = "ak-outpost-authentik-embedded-outpost.authentik.svc.cluster.local"
    port {
      name        = "http"
      port        = 9000
      target_port = 9000
    }
  }
}

resource "kubernetes_manifest" "bitmagnet_forward_auth" {
  depends_on = [authentik_outpost_provider_attachment.bitmagnet]

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "bitmagnet-authentik-forward-auth"
      namespace = local.bitmagnet.namespace
    }
    spec = {
      forwardAuth = {
        address            = "http://${kubernetes_service.bitmagnet_outpost.metadata[0].name}.${local.bitmagnet.namespace}.svc.cluster.local:9000/outpost.goauthentik.io/auth/traefik"
        trustForwardHeader = true
        authResponseHeaders = [
          "X-authentik-username",
          "X-authentik-email",
          "X-authentik-groups",
          "X-authentik-entitlements",
          "X-authentik-jwt",
          "X-authentik-meta-provider",
        ]
        authResponseHeadersRegex = "^Set-Cookie$"
      }
    }
  }
}

resource "kubernetes_ingress_v1" "bitmagnet" {
  depends_on = [kubernetes_manifest.bitmagnet_forward_auth]

  metadata {
    name      = "bitmagnet"
    namespace = local.bitmagnet.namespace
    annotations = {
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
      "traefik.ingress.kubernetes.io/router.tls"         = "true"
      "traefik.ingress.kubernetes.io/router.middlewares" = "${local.bitmagnet.namespace}-${kubernetes_manifest.bitmagnet_forward_auth.manifest.metadata.name}@kubernetescrd"
      "cert-manager.io/cluster-issuer"                   = var.cluster_cert_issuer
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = local.bitmagnet.host

      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.bitmagnet.metadata[0].name
              port {
                number = 3333
              }
            }
          }
        }
      }
    }

    tls {
      secret_name = "bitmagnet-tls"
      hosts       = [local.bitmagnet.host]
    }
  }
}

resource "kubernetes_ingress_v1" "bitmagnet_outpost" {
  metadata {
    name      = "bitmagnet-outpost"
    namespace = local.bitmagnet.namespace
    annotations = {
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
      "traefik.ingress.kubernetes.io/router.tls"         = "true"
      "cert-manager.io/cluster-issuer"                   = var.cluster_cert_issuer
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = local.bitmagnet.host

      http {
        path {
          path      = "/outpost.goauthentik.io/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.bitmagnet_outpost.metadata[0].name
              port {
                number = 9000
              }
            }
          }
        }
      }
    }

    tls {
      secret_name = "bitmagnet-tls"
      hosts       = [local.bitmagnet.host]
    }
  }
}
