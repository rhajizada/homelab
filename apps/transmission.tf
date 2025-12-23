locals {
  transmission = {
    namespace = "transmission"
    host      = "transmission.${var.base_domain}"
    image     = "linuxserver/transmission:4.0.6"

    storage = {
      config = {
        size         = "256Mi"
        class        = "longhorn"
        access_modes = ["ReadWriteMany"]
      }
      downloads = {
        size         = "256Gi"
        class        = "smb-private"
        access_modes = ["ReadWriteMany"]
      }
      watch = {
        size         = "4Gi"
        class        = "smb-private"
        access_modes = ["ReadWriteMany"]
      }
    }

    resources = {
      requests = { cpu = "500m", memory = "1Gi" }
      limits   = { cpu = "2", memory = "4Gi" }
    }
    env = {
      PUID = "1000"
      PGID = "1000"
      TZ   = "America/New_York"

      TRANSMISSION_DOWNLOAD_DIR           = "/downloads"
      TRANSMISSION_INCOMPLETE_DIR         = "/downloads"
      TRANSMISSION_INCOMPLETE_DIR_ENABLED = "false"
      TRANSMISSION_WATCH_DIR              = "/watch"
      TRANSMISSION_WATCH_DIR_ENABLED      = "true"

      TRANSMISSION_RPC_AUTHENTICATION_REQUIRED = "false"
      TRANSMISSION_RPC_HOST_WHITELIST          = "transmission.${var.base_domain}"
      TRANSMISSION_RPC_HOST_WHITELIST_ENABLED  = "true"
      TRANSMISSION_RPC_WHITELIST_ENABLED       = "false"
    }
  }
}

resource "authentik_provider_proxy" "transmission" {
  depends_on         = [helm_release.authentik]
  name               = "transmission"
  external_host      = "https://${local.transmission.host}"
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id
  mode               = "forward_single"
}

resource "authentik_application" "transmission" {
  name              = "transmission"
  slug              = "transmission"
  protocol_provider = authentik_provider_proxy.transmission.id
  meta_icon         = "https://simpleicons.org/icons/transmission.svg"
}

resource "authentik_group" "transmission_users" {
  depends_on = [helm_release.authentik]
  name       = "transmission-users"
}

resource "authentik_policy_binding" "transmission_access" {
  target = authentik_application.transmission.uuid
  group  = authentik_group.transmission_users.id
  order  = 0
}

resource "authentik_outpost_provider_attachment" "transmission" {
  outpost           = data.authentik_outpost.embedded.id
  protocol_provider = authentik_provider_proxy.transmission.id
}

resource "kubernetes_namespace" "transmission" {
  metadata {
    name = local.transmission.namespace
  }
}

resource "kubernetes_persistent_volume_claim" "transmission_config" {
  depends_on = [kubernetes_namespace.transmission]

  metadata {
    name      = "transmission-config"
    namespace = local.transmission.namespace
  }

  spec {
    storage_class_name = local.transmission.storage.config.class
    access_modes       = local.transmission.storage.config.access_modes

    resources {
      requests = {
        storage = local.transmission.storage.config.size
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "transmission_downloads" {
  depends_on = [kubernetes_namespace.transmission]

  metadata {
    name      = "transmission-downloads"
    namespace = local.transmission.namespace
  }

  spec {
    storage_class_name = local.transmission.storage.downloads.class
    access_modes       = local.transmission.storage.downloads.access_modes

    resources {
      requests = {
        storage = local.transmission.storage.downloads.size
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "transmission_watch" {
  depends_on = [kubernetes_namespace.transmission]

  metadata {
    name      = "transmission-watch"
    namespace = local.transmission.namespace
  }

  spec {
    storage_class_name = local.transmission.storage.watch.class
    access_modes       = local.transmission.storage.watch.access_modes

    resources {
      requests = {
        storage = local.transmission.storage.watch.size
      }
    }
  }
}

resource "kubernetes_deployment" "transmission" {
  depends_on = [
    kubernetes_namespace.transmission,
    kubernetes_persistent_volume_claim.transmission_config,
    kubernetes_persistent_volume_claim.transmission_downloads,
    kubernetes_persistent_volume_claim.transmission_watch,
  ]

  metadata {
    name      = "transmission"
    namespace = local.transmission.namespace
    labels    = { app = "transmission" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "transmission" }
    }

    template {
      metadata { labels = { app = "transmission" } }

      spec {
        security_context {
          fs_group = 1000
        }

        init_container {
          name  = "init-transmission-settings"
          image = "alpine:3.20"

          security_context {
            run_as_user  = 1000
            run_as_group = 1000
          }

          command = [
            "sh",
            "-c",
            <<-EOT
              set -euo pipefail
              mkdir -p /config
              cat >/config/settings.json <<'JSON'
              {
                "port-forwarding-enabled": false,
                "idle-seeding-limit-enabled": true,
                "idle-seeding-limit": 1,
                "speed-limit-up-enabled": true,
                "speed-limit-up": 1,
                "download-dir": "/downloads",
                "incomplete-dir": "/downloads",
                "incomplete-dir-enabled": false,
                "watch-dir-enabled": true,
                "watch-dir": "/watch",
                "rpc-authentication-required": false,
                "rpc-host-whitelist": "${local.transmission.host}",
                "rpc-host-whitelist-enabled": true,
                "rpc-whitelist-enabled": false
              }
JSON
            EOT
          ]

          volume_mount {
            name       = "config"
            mount_path = "/config"
          }
        }

        container {
          name  = "transmission"
          image = local.transmission.image

          security_context {
            run_as_user  = 1000
            run_as_group = 1000
          }

          port {
            name           = "http"
            container_port = 9091
          }

          dynamic "env" {
            for_each = local.transmission.env
            content {
              name  = env.key
              value = env.value
            }
          }

          resources {
            limits   = local.transmission.resources.limits
            requests = local.transmission.resources.requests
          }

          readiness_probe {
            tcp_socket { port = 9091 }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 3
          }

          liveness_probe {
            tcp_socket { port = 9091 }
            initial_delay_seconds = 15
            period_seconds        = 20
            timeout_seconds       = 3
          }

          volume_mount {
            name       = "config"
            mount_path = "/config"
          }

          volume_mount {
            name       = "downloads"
            mount_path = "/downloads"
          }

          volume_mount {
            name       = "watch"
            mount_path = "/watch"
          }
        }

        volume {
          name = "config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.transmission_config.metadata[0].name
          }
        }

        volume {
          name = "downloads"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.transmission_downloads.metadata[0].name
          }
        }

        volume {
          name = "watch"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.transmission_watch.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "transmission" {
  depends_on = [kubernetes_namespace.transmission]

  metadata {
    name      = "transmission"
    namespace = local.transmission.namespace
  }

  spec {
    selector = { app = "transmission" }

    port {
      name        = "http"
      port        = 9091
      target_port = 9091
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_service" "transmission_outpost" {
  depends_on = [kubernetes_namespace.transmission]

  metadata {
    name      = "transmission-outpost"
    namespace = local.transmission.namespace
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

resource "kubernetes_manifest" "transmission_forward_auth" {
  depends_on = [
    authentik_outpost_provider_attachment.transmission,
    kubernetes_service.transmission_outpost,
  ]

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "transmission-authentik-forward-auth"
      namespace = local.transmission.namespace
    }
    spec = {
      forwardAuth = {
        address            = "http://transmission-outpost.${local.transmission.namespace}.svc.cluster.local:9000/outpost.goauthentik.io/auth/traefik"
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

resource "kubernetes_ingress_v1" "transmission" {
  depends_on = [kubernetes_manifest.transmission_forward_auth]

  metadata {
    name      = "transmission"
    namespace = local.transmission.namespace
    annotations = {
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
      "traefik.ingress.kubernetes.io/router.tls"         = "true"
      "traefik.ingress.kubernetes.io/router.middlewares" = "${local.transmission.namespace}-${kubernetes_manifest.transmission_forward_auth.manifest["metadata"]["name"]}@kubernetescrd"
      "cert-manager.io/cluster-issuer"                   = var.cluster_cert_issuer
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = local.transmission.host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.transmission.metadata[0].name
              port { number = 9091 }
            }
          }
        }
      }
    }

    tls {
      secret_name = "transmission-tls"
      hosts       = [local.transmission.host]
    }
  }
}

resource "kubernetes_ingress_v1" "transmission_outpost" {
  depends_on = [kubernetes_service.transmission_outpost]

  metadata {
    name      = "transmission-outpost"
    namespace = local.transmission.namespace
    annotations = {
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
      "traefik.ingress.kubernetes.io/router.tls"         = "true"
      "cert-manager.io/cluster-issuer"                   = var.cluster_cert_issuer
    }
  }

  spec {
    ingress_class_name = "traefik"
    rule {
      host = local.transmission.host
      http {
        path {
          path      = "/outpost.goauthentik.io/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.transmission_outpost.metadata[0].name
              port { number = 9000 }
            }
          }
        }
      }
    }

    tls {
      secret_name = "transmission-tls"
      hosts       = [local.transmission.host]
    }
  }
}
