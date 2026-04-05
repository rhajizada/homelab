locals {
  openwebui = {
    repository = "https://helm.openwebui.com"
    chart      = "open-webui"
    version    = "12.13.0"
    namespace  = "openwebui"

    host         = "chat.${var.base_domain}"
    storage_size = "16Gi"
  }
  chromadb = {
    repository   = "https://infracloudio.github.io/charts"
    chart        = "chromadb"
    version      = "0.1.4"
    image_tag    = "1.5.2"
    storage_size = "16Gi"
  }
  tika = {
    repository = "https://apache.jfrog.io/artifactory/tika"
    chart      = "tika"
    version    = "2.9.0"
  }
  searxng = {
    image = "searxng/searxng:latest"
    port  = 8080
  }
  playwright = {
    image   = "mcr.microsoft.com/playwright:v1.58.2-noble"
    version = "1.58.2"
    port    = 3000
  }
}

resource "kubernetes_namespace" "openwebui_namespace" {
  metadata {
    name = local.openwebui.namespace
  }
}

resource "random_password" "openwebui_secret_key" {
  length  = 32
  special = false
}

resource "random_password" "openwebui_pipelines_key" {
  length  = 32
  special = false
}

resource "random_password" "openwebui_searxng_secret_key" {
  length  = 32
  special = false
}

resource "random_password" "openwebui_client_id" {
  length  = 32
  special = false
}

resource "random_password" "openwebui_client_secret" {
  length  = 64
  special = true
}

resource "authentik_group" "openwebui_admin_group" {
  depends_on = [helm_release.authentik]
  name       = "openwebui-admins"
}

resource "authentik_group" "openwebui_user_group" {
  depends_on = [helm_release.authentik]
  name       = "openwebui-users"
}

resource "authentik_provider_oauth2" "openwebui" {
  depends_on = [
    helm_release.authentik,
  ]
  name                    = "openwebui"
  client_type             = "confidential"
  client_id               = random_password.openwebui_client_id.result
  client_secret           = random_password.openwebui_client_secret.result
  authorization_flow      = data.authentik_flow.default_authorization_flow.id
  invalidation_flow       = data.authentik_flow.default_invalidation_flow.id
  logout_method           = "backchannel"
  refresh_token_threshold = "seconds=0"
  allowed_redirect_uris = [
    {
      matching_mode = "strict",
      url           = "https://${local.openwebui.host}/oauth/oidc/callback",
    }
  ]
  property_mappings = [
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.openid.id,
  ]
  signing_key = data.authentik_certificate_key_pair.generated.id
}

resource "authentik_application" "openwebui" {
  name              = "Open WebUI"
  slug              = "openwebui-slug"
  protocol_provider = authentik_provider_oauth2.openwebui.id
  meta_icon         = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/open-webui-light.svg"
}

resource "kubernetes_secret" "openwebui_secret" {
  metadata {
    name      = "openwebui-secret"
    namespace = local.openwebui.namespace
  }

  data = {
    secret = random_password.openwebui_secret_key.result
  }

  type = "Opaque"
}

resource "kubernetes_secret" "openwebui_pipelines_secret" {
  metadata {
    name      = "openwebui-pipelines-secret"
    namespace = local.openwebui.namespace
  }

  data = {
    key = random_password.openwebui_pipelines_key.result
  }

  type = "Opaque"
}

resource "kubernetes_secret" "openwebui_authentik_secret" {
  metadata {
    name      = "openwebui-authentik-secret"
    namespace = local.openwebui.namespace
  }

  data = {
    client_id     = random_password.openwebui_client_id.result
    client_secret = random_password.openwebui_client_secret.result
  }

  type = "Opaque"
}

resource "kubernetes_config_map" "openwebui_searxng_config" {
  depends_on = [kubernetes_namespace.openwebui_namespace]

  metadata {
    name      = "open-webui-searxng-config"
    namespace = local.openwebui.namespace
    labels = {
      app = "open-webui-searxng"
    }
  }

  data = {
    "settings.yml" = <<-YAML
      use_default_settings:
        engines:
          keep_only:
            - duckduckgo
            - duckduckgo images
            - duckduckgo news
            - duckduckgo videos
            - wikipedia
            - wikidata
      general:
        instance_name: "Open WebUI SearXNG"
      search:
        default_lang: "en-US"
        formats:
          - html
          - json
      server:
        bind_address: "0.0.0.0"
        secret_key: "${random_password.openwebui_searxng_secret_key.result}"
        limiter: false
    YAML

    "limiter.toml" = <<-TOML
      [botdetection]
      ipv4_prefix = 32
      ipv6_prefix = 48

      trusted_proxies = [
        '127.0.0.0/8',
        '::1',
        '10.0.0.0/8',
        '172.16.0.0/12',
        '192.168.0.0/16',
        'fd00::/8',
      ]

      [botdetection.ip_limit]
      filter_link_local = false
      link_token = false

      [botdetection.ip_lists]
      block_ip = []
      pass_ip = []
      pass_searxng_org = true
    TOML
  }
}

resource "kubernetes_deployment" "openwebui_searxng" {
  depends_on = [
    kubernetes_namespace.openwebui_namespace,
    kubernetes_config_map.openwebui_searxng_config,
  ]

  metadata {
    name      = "open-webui-searxng"
    namespace = local.openwebui.namespace
    labels = {
      app = "open-webui-searxng"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "open-webui-searxng"
      }
    }

    template {
      metadata {
        labels = {
          app = "open-webui-searxng"
        }
      }

      spec {
        init_container {
          name  = "copy-config"
          image = "busybox:1.36"
          command = [
            "sh",
            "-c",
            "cp /config-src/settings.yml /config-dst/settings.yml && cp /config-src/limiter.toml /config-dst/limiter.toml"
          ]

          volume_mount {
            name       = "config-src"
            mount_path = "/config-src"
          }

          volume_mount {
            name       = "config"
            mount_path = "/config-dst"
          }
        }

        container {
          name  = "searxng"
          image = local.searxng.image

          env {
            name  = "SEARXNG_PORT"
            value = tostring(local.searxng.port)
          }

          env {
            name  = "SEARXNG_BIND_ADDRESS"
            value = "0.0.0.0"
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/searxng"
          }

          port {
            name           = "http"
            container_port = local.searxng.port
          }
        }

        volume {
          name = "config-src"
          config_map {
            name = kubernetes_config_map.openwebui_searxng_config.metadata[0].name
          }
        }

        volume {
          name = "config"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service" "openwebui_searxng" {
  depends_on = [kubernetes_namespace.openwebui_namespace]

  metadata {
    name      = "open-webui-searxng"
    namespace = local.openwebui.namespace
  }

  spec {
    selector = {
      app = "open-webui-searxng"
    }

    port {
      name        = "http"
      port        = local.searxng.port
      target_port = local.searxng.port
    }
  }
}

resource "kubernetes_deployment" "openwebui_playwright" {
  depends_on = [kubernetes_namespace.openwebui_namespace]

  metadata {
    name      = "open-webui-playwright"
    namespace = local.openwebui.namespace
    labels = {
      app = "open-webui-playwright"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "open-webui-playwright"
      }
    }

    template {
      metadata {
        labels = {
          app = "open-webui-playwright"
        }
      }

      spec {
        container {
          name  = "playwright"
          image = local.playwright.image
          command = [
            "/bin/sh",
            "-c",
            "npx -y playwright@${local.playwright.version} run-server --port ${local.playwright.port} --host 0.0.0.0"
          ]

          port {
            name           = "ws"
            container_port = local.playwright.port
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "openwebui_playwright" {
  depends_on = [kubernetes_namespace.openwebui_namespace]

  metadata {
    name      = "open-webui-playwright"
    namespace = local.openwebui.namespace
  }

  spec {
    selector = {
      app = "open-webui-playwright"
    }

    port {
      name        = "ws"
      port        = local.playwright.port
      target_port = local.playwright.port
    }
  }
}

resource "helm_release" "chromadb" {
  depends_on = [
    kubernetes_namespace.openwebui_namespace,
  ]

  name       = "open-webui-chromadb"
  chart      = local.chromadb.chart
  repository = local.chromadb.repository
  version    = local.chromadb.version
  namespace  = local.openwebui.namespace

  timeout = 600

  values = [
    templatefile("${path.module}/templates/chromadb.yaml.tmpl", {
      image_tag    = local.chromadb.image_tag
      storage_size = local.chromadb.storage_size
    })
  ]
}

resource "helm_release" "tika" {
  depends_on = [
    kubernetes_namespace.openwebui_namespace,
  ]

  name       = "open-webui-tika"
  chart      = local.tika.chart
  repository = local.tika.repository
  version    = local.tika.version
  namespace  = local.openwebui.namespace

  timeout = 600

  values = [
    file("${path.module}/templates/tika.yaml")
  ]
}

resource "helm_release" "openwebui" {
  # TODO: Fix regular users require admin approval on sign up and cannot login
  depends_on = [
    kubernetes_service.ollama,
    kubernetes_namespace.openwebui_namespace,
    authentik_application.openwebui,
    kubernetes_secret.openwebui_secret,
    kubernetes_secret.openwebui_authentik_secret,
    kubernetes_secret.openwebui_pipelines_secret,
    kubernetes_service.openwebui_playwright,
    kubernetes_service.openwebui_searxng,
    helm_release.chromadb,
    helm_release.tika
  ]

  name       = "openwebui"
  chart      = local.openwebui.chart
  repository = local.openwebui.repository
  version    = local.openwebui.version
  namespace  = local.openwebui.namespace

  timeout = 1200

  values = [
    templatefile("${path.module}/templates/openwebui.yaml.tmpl", {
      host                 = local.openwebui.host
      cert_issuer          = var.cluster_cert_issuer
      ollama_url           = "http://ollama.${local.llamero.namespace}.svc.cluster.local:11434"
      playwright_ws_url    = "ws://open-webui-playwright.${local.openwebui.namespace}.svc.cluster.local:${local.playwright.port}/"
      searxng_language     = "en-US"
      searxng_query_url    = "http://open-webui-searxng.${local.openwebui.namespace}.svc.cluster.local:${local.searxng.port}/search?q=<query>&format=json"
      storage_size         = local.openwebui.storage_size
      openid_provider_url  = "https://${local.authentik.host}/application/o/openwebui-slug/.well-known/openid-configuration"
      openid_provider_name = "authentik"
    })
  ]
}
