locals {
  vane = {
    namespace = "vane"
    host      = "vane.${var.base_domain}"
    image     = "itzcrazykns1337/vane:latest"
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

moved {
  from = authentik_provider_proxy.perplexica
  to   = authentik_provider_proxy.vane
}

moved {
  from = authentik_application.perplexica
  to   = authentik_application.vane
}

moved {
  from = authentik_group.perplexica_users
  to   = authentik_group.vane_users
}

moved {
  from = authentik_policy_binding.perplexica_access
  to   = authentik_policy_binding.vane_access
}

moved {
  from = authentik_outpost_provider_attachment.perplexica
  to   = authentik_outpost_provider_attachment.vane
}

moved {
  from = kubernetes_namespace.perplexica
  to   = kubernetes_namespace.vane
}

moved {
  from = kubernetes_persistent_volume_claim.perplexica_data
  to   = kubernetes_persistent_volume_claim.vane_data
}

moved {
  from = kubernetes_persistent_volume_claim.perplexica_uploads
  to   = kubernetes_persistent_volume_claim.vane_uploads
}

moved {
  from = kubernetes_deployment.perplexica
  to   = kubernetes_deployment.vane
}

moved {
  from = kubernetes_service.perplexica
  to   = kubernetes_service.vane
}

moved {
  from = kubernetes_service.perplexica_outpost
  to   = kubernetes_service.vane_outpost
}

moved {
  from = kubernetes_manifest.perplexica_forward_auth
  to   = kubernetes_manifest.vane_forward_auth
}

moved {
  from = kubernetes_ingress_v1.perplexica
  to   = kubernetes_ingress_v1.vane
}

moved {
  from = kubernetes_ingress_v1.perplexica_outpost
  to   = kubernetes_ingress_v1.vane_outpost
}

resource "authentik_provider_proxy" "vane" {
  depends_on         = [helm_release.authentik]
  name               = "vane"
  external_host      = "https://${local.vane.host}"
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id
  mode               = "forward_single"
}

resource "authentik_application" "vane" {
  name              = "Vane"
  slug              = "vane-slug"
  protocol_provider = authentik_provider_proxy.vane.id
  meta_icon         = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/perplexity-dark.svg"
}

resource "authentik_group" "vane_users" {
  depends_on = [helm_release.authentik]
  name       = "vane-users"
}

resource "authentik_policy_binding" "vane_access" {
  target = authentik_application.vane.uuid
  group  = authentik_group.vane_users.id
  order  = 0
}

resource "authentik_outpost_provider_attachment" "vane" {
  outpost           = data.authentik_outpost.embedded.id
  protocol_provider = authentik_provider_proxy.vane.id
}

resource "kubernetes_namespace" "vane" {
  metadata {
    name = local.vane.namespace
  }
}

resource "kubernetes_persistent_volume_claim" "vane_data" {
  metadata {
    name      = "vane-data"
    namespace = local.vane.namespace
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = local.vane.storage.data
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "vane_uploads" {
  metadata {
    name      = "vane-uploads"
    namespace = local.vane.namespace
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = local.vane.storage.data
      }
    }
  }
}

resource "kubernetes_deployment" "vane" {
  metadata {
    name      = "vane"
    namespace = local.vane.namespace
    labels = {
      app = "vane"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "vane"
      }
    }
    template {
      metadata {
        labels = {
          app = "vane"
        }
      }
      spec {
        container {
          name  = "vane"
          image = local.vane.image
          port {
            name           = "http"
            container_port = 3000
          }
          resources {
            limits   = local.vane.resources.limits
            requests = local.vane.resources.requests
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
            claim_name = kubernetes_persistent_volume_claim.vane_data.metadata[0].name
          }
        }
        volume {
          name = "uploads"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.vane_uploads.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "vane" {
  metadata {
    name      = "vane"
    namespace = local.vane.namespace
  }
  spec {
    selector = {
      app = "vane"
    }
    port {
      port        = 3000
      target_port = 3000
    }
  }
}

resource "kubernetes_service" "vane_outpost" {
  metadata {
    name      = "vane-outpost"
    namespace = local.vane.namespace
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

resource "kubernetes_manifest" "vane_forward_auth" {
  depends_on = [authentik_outpost_provider_attachment.vane]

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "vane-authentik-forward-auth"
      namespace = local.vane.namespace
    }
    spec = {
      forwardAuth = {
        address            = "http://${kubernetes_service.vane_outpost.metadata[0].name}.${local.vane.namespace}.svc.cluster.local:9000/outpost.goauthentik.io/auth/traefik"
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

resource "kubernetes_ingress_v1" "vane" {
  depends_on = [kubernetes_manifest.vane_forward_auth]

  metadata {
    name      = "vane"
    namespace = local.vane.namespace
    annotations = {
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
      "traefik.ingress.kubernetes.io/router.tls"         = "true"
      "traefik.ingress.kubernetes.io/router.middlewares" = "${local.vane.namespace}-${kubernetes_manifest.vane_forward_auth.manifest.metadata.name}@kubernetescrd"
      "cert-manager.io/cluster-issuer"                   = var.cluster_cert_issuer
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = local.vane.host

      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.vane.metadata[0].name
              port {
                number = 3000
              }
            }
          }
        }
      }
    }

    tls {
      secret_name = "vane-tls"
      hosts       = [local.vane.host]
    }
  }
}

resource "kubernetes_ingress_v1" "vane_outpost" {
  metadata {
    name      = "vane-outpost"
    namespace = local.vane.namespace
    annotations = {
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
      "traefik.ingress.kubernetes.io/router.tls"         = "true"
      "cert-manager.io/cluster-issuer"                   = var.cluster_cert_issuer
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = local.vane.host

      http {
        path {
          path      = "/outpost.goauthentik.io/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.vane_outpost.metadata[0].name
              port {
                number = 9000
              }
            }
          }
        }
      }
    }

    tls {
      secret_name = "vane-tls"
      hosts       = [local.vane.host]
    }
  }
}
