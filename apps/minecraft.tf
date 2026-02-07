locals {
  minecraft = {
    namespace = "minecraft"
    host      = "minecraft.${var.base_domain}"

    gate = {
      image = "ghcr.io/minekube/gate:v0.62.3"
    }

    server = {
      image = "rdall96/minecraft-server:latest"

      storage = {
        world = {
          size         = "4Gi"
          class        = "smb-private"
          access_modes = ["ReadWriteMany"]
        }
        configurations = {
          size         = "128Mi"
          class        = "smb-private"
          access_modes = ["ReadWriteMany"]
        }
      }

      resources = {
        requests = { cpu = "1", memory = "2Gi" }
        limits   = { cpu = "2", memory = "4Gi" }
      }

      env = {
        EULA                   = "true"
        MOTD                   = "Welcome to SoloCupLabs"
        DIFFICULTY             = "easy"
        MAX_PLAYERS            = "20"
        ONLINE_MODE            = "false"
        WHITE_LIST             = "false"
        ENFORCE_SECURE_PROFILE = "false"
      }
    }
  }
}

resource "kubernetes_namespace" "minecraft" {
  metadata {
    name = local.minecraft.namespace
  }
}

resource "kubernetes_persistent_volume_claim" "minecraft_world" {
  depends_on = [kubernetes_namespace.minecraft]

  metadata {
    name      = "minecraft-world"
    namespace = local.minecraft.namespace
  }

  spec {
    storage_class_name = local.minecraft.server.storage.world.class
    access_modes       = local.minecraft.server.storage.world.access_modes

    resources {
      requests = {
        storage = local.minecraft.server.storage.world.size
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "minecraft_configurations" {
  depends_on = [kubernetes_namespace.minecraft]

  metadata {
    name      = "minecraft-configurations"
    namespace = local.minecraft.namespace
  }

  spec {
    storage_class_name = local.minecraft.server.storage.configurations.class
    access_modes       = local.minecraft.server.storage.configurations.access_modes

    resources {
      requests = {
        storage = local.minecraft.server.storage.configurations.size
      }
    }
  }
}

resource "kubernetes_deployment" "minecraft_server" {
  depends_on = [
    kubernetes_namespace.minecraft,
    kubernetes_persistent_volume_claim.minecraft_world,
    kubernetes_persistent_volume_claim.minecraft_configurations,
  ]

  metadata {
    name      = "minecraft-server"
    namespace = local.minecraft.namespace
    labels    = { app = "minecraft-server" }
  }

  spec {
    replicas = 1

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

          dynamic "env" {
            for_each = local.minecraft.server.env
            content {
              name  = env.key
              value = env.value
            }
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
            name       = "world"
            mount_path = "/minecraft/world"
          }

          volume_mount {
            name       = "configurations"
            mount_path = "/minecraft/configurations"
          }
        }

        volume {
          name = "world"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.minecraft_world.metadata[0].name
          }
        }

        volume {
          name = "configurations"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.minecraft_configurations.metadata[0].name
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

resource "kubernetes_config_map" "gate_config" {
  depends_on = [kubernetes_namespace.minecraft]

  metadata {
    name      = "gate-config"
    namespace = local.minecraft.namespace
    labels    = { app = "gate" }
  }

  data = {
    "config.yml" = <<-YAML
      config:
        bind: 0.0.0.0:25565
        onlineMode: false
        forwarding:
          mode: none
        servers:
          survival: minecraft-server.${local.minecraft.namespace}.svc.cluster.local:25565
        try:
          - survival
    YAML
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

