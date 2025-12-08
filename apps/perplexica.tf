locals {
  perplexica = {
    namespace = "perplexica"
    host      = "perplexica.${var.base_domain}"
    image     = "itzcrazykns1337/perplexica:v1.11.2"
    storage = {
      data    = "8Gi"
      uploads = "8Gi"
    }
    resources = {
      requests = {
        cpu    = "500m"
        memory = "512Mi"
      }
      limits = {
        cpu    = "2"
        memory = "2Gi"
      }
    }
  }
}

resource "authentik_provider_proxy" "perplexica" {
  name               = "perplexica"
  external_host      = "https://${local.perplexica.host}"
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id
  mode               = "forward_single"
}

resource "authentik_application" "perplexica" {
  name              = "Perplexica"
  slug              = "perplexica-slug"
  protocol_provider = authentik_provider_proxy.perplexica.id
  meta_icon         = "https://simpleicons.org/icons/perplexity.svg"
}

resource "authentik_group" "perplexica_users" {
  name = "perplexica-users"
}

resource "authentik_policy_binding" "perplexica_access" {
  target = authentik_application.perplexica.uuid
  group  = authentik_group.perplexica_users.id
  order  = 0
}

resource "authentik_outpost_provider_attachment" "perplexica" {
  outpost           = data.authentik_outpost.embedded.id
  protocol_provider = authentik_provider_proxy.perplexica.id
}

resource "kubernetes_namespace" "perplexica" {
  metadata {
    name = local.perplexica.namespace
  }
}

resource "kubernetes_persistent_volume_claim" "perplexica_data" {
  metadata {
    name      = "perplexica-data"
    namespace = local.perplexica.namespace
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = local.perplexica.storage.data
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "perplexica_uploads" {
  metadata {
    name      = "perplexica-uploads"
    namespace = local.perplexica.namespace
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = local.perplexica.storage.data
      }
    }
  }
}

resource "kubernetes_deployment" "perplexica" {
  metadata {
    name      = "perplexica"
    namespace = local.perplexica.namespace
    labels = {
      app = "perplexica"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "perplexica"
      }
    }
    template {
      metadata {
        labels = {
          app = "perplexica"
        }
      }
      spec {
        container {
          name  = "perplexica"
          image = local.perplexica.image
          port {
            name           = "http"
            container_port = 3000
          }
          resources {
            limits   = local.perplexica.resources.limits
            requests = local.perplexica.resources.requests
          }
          liveness_probe {
            http_get {
              path = "/"
              port = "http"
            }
            initial_delay_seconds = 10
            period_seconds        = 20
            timeout_seconds       = 5
          }
          readiness_probe {
            http_get {
              path = "/"
              port = "http"
            }
            initial_delay_seconds = 5
            period_seconds        = 15
            timeout_seconds       = 3
          }
          volume_mount {
            name       = "data"
            mount_path = "/home/perplexica/data"
          }
          volume_mount {
            name       = "uploads"
            mount_path = "/home/perplexica/uploads"
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.perplexica_data.metadata[0].name
          }
        }
        volume {
          name = "uploads"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.perplexica_uploads.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "perplexica" {
  metadata {
    name      = "perplexica"
    namespace = local.perplexica.namespace
  }
  spec {
    selector = {
      app = "perplexica"
    }
    port {
      port        = 3000
      target_port = 3000
    }
  }
}

resource "kubernetes_service" "perplexica_outpost" {
  metadata {
    name      = "perplexica-outpost"
    namespace = local.perplexica.namespace
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

resource "kubernetes_manifest" "perplexica_forward_auth" {
  depends_on = [authentik_outpost_provider_attachment.perplexica]

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "perplexica-authentik-forward-auth"
      namespace = local.perplexica.namespace
    }
    spec = {
      forwardAuth = {
        address            = "http://${kubernetes_service.perplexica_outpost.metadata[0].name}.${local.perplexica.namespace}.svc.cluster.local:9000/outpost.goauthentik.io/auth/traefik"
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

resource "kubernetes_ingress_v1" "perplexica" {
  depends_on = [kubernetes_manifest.perplexica_forward_auth]

  metadata {
    name      = "perplexica"
    namespace = local.perplexica.namespace
    annotations = {
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
      "traefik.ingress.kubernetes.io/router.tls"         = "true"
      "traefik.ingress.kubernetes.io/router.middlewares" = "${local.perplexica.namespace}-${kubernetes_manifest.perplexica_forward_auth.manifest.metadata.name}@kubernetescrd"
      "cert-manager.io/cluster-issuer"                   = var.cluster_cert_issuer
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = local.perplexica.host

      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.perplexica.metadata[0].name
              port {
                number = 3000
              }
            }
          }
        }
      }
    }

    tls {
      secret_name = "perplexica-tls"
      hosts       = [local.perplexica.host]
    }
  }
}

resource "kubernetes_ingress_v1" "perplexica_outpost" {
  metadata {
    name      = "perplexica-outpost"
    namespace = local.perplexica.namespace
    annotations = {
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
      "traefik.ingress.kubernetes.io/router.tls"         = "true"
      "cert-manager.io/cluster-issuer"                   = var.cluster_cert_issuer
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = local.perplexica.host

      http {
        path {
          path      = "/outpost.goauthentik.io/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.perplexica_outpost.metadata[0].name
              port {
                number = 9000
              }
            }
          }
        }
      }
    }

    tls {
      secret_name = "perplexica-tls"
      hosts       = [local.perplexica.host]
    }
  }
}
