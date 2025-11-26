locals {
  vscode = {
    namespace    = "vscode"
    host         = "code.${var.base_domain}"
    image        = "gitpod/openvscode-server:1.105.1"
    storage_size = "32Gi"
  }
}

resource "authentik_provider_proxy" "vscode" {
  name               = "vscode"
  external_host      = "https://${local.vscode.host}"
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id
  mode               = "forward_single"
}

resource "authentik_application" "vscode" {
  name              = "VSCode"
  slug              = "vscode-slug"
  protocol_provider = authentik_provider_proxy.vscode.id
  meta_icon         = "https://simpleicons.org/icons/vscodium.svg"
}

resource "authentik_group" "vscode_users" {
  name = "vscode-users"
}

resource "authentik_policy_binding" "vscode_access" {
  target = authentik_application.vscode.uuid
  group  = authentik_group.vscode_users.id
  order  = 0
}

data "authentik_outpost" "embedded" {
  depends_on = [helm_release.authentik]
  name       = "authentik Embedded Outpost"
}

resource "authentik_outpost_provider_attachment" "vscode" {
  outpost           = data.authentik_outpost.embedded.id
  protocol_provider = authentik_provider_proxy.vscode.id
}

resource "kubernetes_namespace" "vscode" {
  metadata {
    name = local.vscode.namespace
  }
}

resource "kubernetes_persistent_volume_claim" "vscode" {
  metadata {
    name      = "openvscode-workspace"
    namespace = local.vscode.namespace
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = local.vscode.storage_size
      }
    }
  }
}

resource "kubernetes_deployment" "vscode" {
  metadata {
    name      = "openvscode"
    namespace = local.vscode.namespace
    labels = {
      app = "openvscode"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "openvscode"
      }
    }
    template {
      metadata {
        labels = {
          app = "openvscode"
        }
      }
      spec {
        container {
          name  = "openvscode"
          image = local.vscode.image
          args  = ["--host=0.0.0.0", "--port=3000"]
          port {
            container_port = 3000
          }
          volume_mount {
            name       = "workspace"
            mount_path = "/home/workspace"
          }
        }
        volume {
          name = "workspace"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.vscode.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "vscode" {
  metadata {
    name      = "openvscode"
    namespace = local.vscode.namespace
  }
  spec {
    selector = {
      app = "openvscode"
    }
    port {
      port        = 3000
      target_port = 3000
    }
  }
}

resource "kubernetes_service" "vscode_outpost" {
  metadata {
    name      = "openvscode-outpost"
    namespace = local.vscode.namespace
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

resource "kubernetes_manifest" "vscode_forward_auth" {
  depends_on = [authentik_outpost_provider_attachment.vscode]

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "vscode-authentik-forward-auth"
      namespace = local.vscode.namespace
    }
    spec = {
      forwardAuth = {
        # Use same-namespace ExternalName to avoid cross-namespace middleware references
        address            = "http://${kubernetes_service.vscode_outpost.metadata[0].name}.${local.vscode.namespace}.svc.cluster.local:9000/outpost.goauthentik.io/auth/traefik"
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

resource "kubernetes_manifest" "vscode_ingressroute" {
  depends_on = [kubernetes_manifest.vscode_forward_auth]

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "openvscode"
      namespace = local.vscode.namespace
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        {
          kind     = "Rule"
          match    = "Host(`${local.vscode.host}`)"
          priority = 10
          services = [
            {
              name = kubernetes_service.vscode.metadata[0].name
              port = 3000
            }
          ]
          middlewares = [
            {
              name      = kubernetes_manifest.vscode_forward_auth.manifest.metadata.name
              namespace = local.vscode.namespace
            }
          ]
        }
      ]
      tls = {
        secretName = "vscode-tls"
      }
    }
  }
}

resource "kubernetes_manifest" "vscode_outpost_ingressroute" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "openvscode-outpost"
      namespace = local.vscode.namespace
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        {
          kind     = "Rule"
          match    = "Host(`${local.vscode.host}`) && PathPrefix(`/outpost.goauthentik.io/`)"
          priority = 15
          services = [
            {
              name = kubernetes_service.vscode_outpost.metadata[0].name
              port = 9000
            }
          ]
        }
      ]
      tls = {
        secretName = "vscode-tls"
      }
    }
  }
}
