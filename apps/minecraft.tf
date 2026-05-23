locals {
  minecraft = {
    namespace     = "minecraft"
    host          = "minecraft.${var.base_domain}"
    admin_host    = "mrcon.${var.base_domain}"
    admin_ws_host = "mrcon-ws.${var.base_domain}"

    gate = {
      image = "ghcr.io/minekube/gate:v0.64.0"
    }

    server = {
      image = "itzg/minecraft-server:stable-java25-jdk"

      storage = {
        data = {
          size         = "16Gi"
          class        = "longhorn"
          access_modes = ["ReadWriteMany"]
        }
      }

      resources = {
        requests = { cpu = "1", memory = "2Gi" }
        limits   = { cpu = "2", memory = "4Gi" }
      }

      env = {
        EULA                   = "TRUE"
        TYPE                   = "PAPER"
        SKIP_DOWNLOAD_DEFAULTS = "true"
        LOG_LEVEL              = "debug"
        INIT_MEMORY            = "1G"
        MAX_MEMORY             = "4G"
        USE_MEOWICE_FLAGS      = "true"
        ENABLE_RCON            = "true"
        VIEW_DISTANCE          = "15"
        SIMULATION_DISTANCE    = "15"
        MOTD                   = "\u00A76SoloCupLabs \u00A77- Survival"
        DIFFICULTY             = "hard"
        MAX_PLAYERS            = "20"
        ONLINE_MODE            = "true"
        ENABLE_WHITELIST       = "true"
        ENFORCE_SECURE_PROFILE = "true"
      }
    }

    rcon = {
      image = "itzg/rcon:latest"

      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
    }
  }
}

resource "random_password" "minecraft_rcon_password" {
  length  = 32
  special = false
}

resource "random_password" "minecraft_rcon_web_password" {
  length  = 32
  special = false
}

resource "kubernetes_namespace" "minecraft" {
  metadata {
    name = local.minecraft.namespace
  }
}

resource "kubernetes_persistent_volume_claim" "minecraft_data" {
  depends_on = [kubernetes_namespace.minecraft]

  metadata {
    name      = "minecraft-data"
    namespace = local.minecraft.namespace
  }

  spec {
    storage_class_name = local.minecraft.server.storage.data.class
    access_modes       = local.minecraft.server.storage.data.access_modes

    resources {
      requests = {
        storage = local.minecraft.server.storage.data.size
      }
    }
  }
}

resource "kubernetes_secret" "minecraft_rcon_auth" {
  depends_on = [kubernetes_namespace.minecraft]

  metadata {
    name      = "minecraft-rcon-auth"
    namespace = local.minecraft.namespace
  }

  data = {
    "rcon-password" = random_password.minecraft_rcon_password.result
    "rwa-username"  = "admin"
    "rwa-password"  = random_password.minecraft_rcon_web_password.result
  }

  type = "Opaque"
}

resource "kubernetes_deployment" "minecraft_server" {
  depends_on = [
    kubernetes_namespace.minecraft,
    kubernetes_persistent_volume_claim.minecraft_data,
    kubernetes_secret.minecraft_rcon_auth,
  ]

  metadata {
    name      = "minecraft-server"
    namespace = local.minecraft.namespace
    labels    = { app = "minecraft-server" }
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = { app = "minecraft-server" }
    }

    template {
      metadata { labels = { app = "minecraft-server" } }

      spec {

        container {
          name  = "minecraft-server"
          image = local.minecraft.server.image

          security_context {
            run_as_user  = 0
            run_as_group = 0
          }

          port {
            name           = "minecraft"
            container_port = 25565
            protocol       = "TCP"
          }

          port {
            name           = "rcon"
            container_port = 25575
            protocol       = "TCP"
          }

          dynamic "env" {
            for_each = local.minecraft.server.env
            content {
              name  = env.key
              value = env.value
            }
          }

          env {
            name  = "RCON_PASSWORD_FILE"
            value = "/run/secrets/minecraft-rcon/rcon-password"
          }

          resources {
            limits   = local.minecraft.server.resources.limits
            requests = local.minecraft.server.resources.requests
          }

          readiness_probe {
            tcp_socket { port = 25565 }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 18
          }

          liveness_probe {
            tcp_socket { port = 25565 }
            initial_delay_seconds = 120
            period_seconds        = 20
            timeout_seconds       = 3
            failure_threshold     = 6
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }

          volume_mount {
            name       = "rcon-auth"
            mount_path = "/run/secrets/minecraft-rcon"
            read_only  = true
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.minecraft_data.metadata[0].name
          }
        }

        volume {
          name = "rcon-auth"
          secret {
            secret_name = kubernetes_secret.minecraft_rcon_auth.metadata[0].name
            items {
              key  = "rcon-password"
              path = "rcon-password"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "minecraft_server" {
  depends_on = [kubernetes_namespace.minecraft]

  metadata {
    name      = "minecraft-server"
    namespace = local.minecraft.namespace
  }

  spec {
    selector = { app = "minecraft-server" }

    port {
      name        = "minecraft"
      port        = 25565
      target_port = 25565
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_service" "minecraft_server_rcon" {
  depends_on = [kubernetes_namespace.minecraft]

  metadata {
    name      = "minecraft-server-rcon"
    namespace = local.minecraft.namespace
  }

  spec {
    selector = { app = "minecraft-server" }

    port {
      name        = "rcon"
      port        = 25575
      target_port = 25575
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_deployment" "minecraft_rcon_admin" {
  depends_on = [
    kubernetes_namespace.minecraft,
    kubernetes_secret.minecraft_rcon_auth,
    kubernetes_service.minecraft_server_rcon,
  ]

  metadata {
    name      = "minecraft-rcon-admin"
    namespace = local.minecraft.namespace
    labels    = { app = "minecraft-rcon-admin" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "minecraft-rcon-admin" }
    }

    template {
      metadata { labels = { app = "minecraft-rcon-admin" } }

      spec {
        container {
          name  = "minecraft-rcon-admin"
          image = local.minecraft.rcon.image

          port {
            name           = "http"
            container_port = 4326
            protocol       = "TCP"
          }

          port {
            name           = "websocket"
            container_port = 4327
            protocol       = "TCP"
          }

          env {
            name  = "RWA_ADMIN"
            value = "TRUE"
          }

          env {
            name  = "RWA_GAME"
            value = "minecraft"
          }

          env {
            name  = "RWA_SERVER_NAME"
            value = "survival"
          }

          env {
            name  = "RWA_RCON_HOST"
            value = "${kubernetes_service.minecraft_server_rcon.metadata[0].name}.${local.minecraft.namespace}.svc.cluster.local"
          }

          env {
            name  = "RWA_RCON_PORT"
            value = "25575"
          }

          env {
            name  = "RWA_WEBSOCKET_URL_SSL"
            value = "wss://${local.minecraft.admin_ws_host}"
          }

          env {
            name = "RWA_USERNAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.minecraft_rcon_auth.metadata[0].name
                key  = "rwa-username"
              }
            }
          }

          env {
            name = "RWA_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.minecraft_rcon_auth.metadata[0].name
                key  = "rwa-password"
              }
            }
          }

          env {
            name = "RWA_RCON_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.minecraft_rcon_auth.metadata[0].name
                key  = "rcon-password"
              }
            }
          }

          resources {
            limits   = local.minecraft.rcon.resources.limits
            requests = local.minecraft.rcon.resources.requests
          }

          readiness_probe {
            http_get {
              path = "/"
              port = "http"
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 3
          }

          liveness_probe {
            http_get {
              path = "/"
              port = "http"
            }
            initial_delay_seconds = 30
            period_seconds        = 20
            timeout_seconds       = 3
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "minecraft_rcon_admin" {
  depends_on = [kubernetes_namespace.minecraft]

  metadata {
    name      = "minecraft-rcon-admin"
    namespace = local.minecraft.namespace
  }

  spec {
    selector = { app = "minecraft-rcon-admin" }

    port {
      name        = "http"
      port        = 4326
      target_port = 4326
      protocol    = "TCP"
    }

    port {
      name        = "websocket"
      port        = 4327
      target_port = 4327
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_ingress_v1" "minecraft_rcon_admin" {
  metadata {
    name      = "minecraft-rcon-admin"
    namespace = local.minecraft.namespace
    annotations = {
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
      "traefik.ingress.kubernetes.io/router.tls"         = "true"
      "cert-manager.io/cluster-issuer"                   = var.cluster_cert_issuer
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = local.minecraft.admin_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.minecraft_rcon_admin.metadata[0].name
              port {
                number = 4326
              }
            }
          }
        }
      }
    }

    tls {
      secret_name = "minecraft-admin-tls"
      hosts       = [local.minecraft.admin_host]
    }
  }
}

resource "kubernetes_ingress_v1" "minecraft_rcon_admin_websocket" {
  metadata {
    name      = "minecraft-rcon-admin-websocket"
    namespace = local.minecraft.namespace
    annotations = {
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
      "traefik.ingress.kubernetes.io/router.tls"         = "true"
      "cert-manager.io/cluster-issuer"                   = var.cluster_cert_issuer
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = local.minecraft.admin_ws_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.minecraft_rcon_admin.metadata[0].name
              port {
                number = 4327
              }
            }
          }
        }
      }
    }

    tls {
      secret_name = "minecraft-admin-ws-tls"
      hosts       = [local.minecraft.admin_ws_host]
    }
  }
}

resource "kubernetes_config_map" "gate_config" {
  depends_on = [kubernetes_namespace.minecraft]

  metadata {
    name      = "gate-config"
    namespace = local.minecraft.namespace
    labels    = { app = "gate" }
  }

  data = {
    "config.yml" = templatefile("${path.module}/templates/minecraft-gate-config.yaml.tmpl", {
      host      = local.minecraft.host
      namespace = local.minecraft.namespace
    })
  }
}

resource "kubernetes_deployment" "gate" {
  depends_on = [
    kubernetes_namespace.minecraft,
    kubernetes_config_map.gate_config,
    kubernetes_service.minecraft_server,
  ]

  metadata {
    name      = "gate"
    namespace = local.minecraft.namespace
    labels    = { app = "gate" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "gate" }
    }

    template {
      metadata { labels = { app = "gate" } }

      spec {
        container {
          name  = "gate"
          image = local.minecraft.gate.image

          port {
            name           = "minecraft"
            container_port = 25565
            protocol       = "TCP"
          }

          readiness_probe {
            tcp_socket { port = 25565 }
            initial_delay_seconds = 3
            period_seconds        = 10
            timeout_seconds       = 3
          }

          liveness_probe {
            tcp_socket { port = 25565 }
            initial_delay_seconds = 10
            period_seconds        = 20
            timeout_seconds       = 3
          }

          volume_mount {
            name       = "config"
            mount_path = "/config.yml"
            sub_path   = "config.yml"
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.gate_config.metadata[0].name
          }
        }
      }
    }
  }
}


resource "kubernetes_service" "gate" {
  depends_on = [kubernetes_namespace.minecraft]

  metadata {
    name      = "gate"
    namespace = local.minecraft.namespace
  }

  spec {
    type     = "NodePort"
    selector = { app = "gate" }

    port {
      name        = "minecraft"
      port        = 25565
      target_port = 25565
      node_port   = 32565
      protocol    = "TCP"
    }
  }
}
