locals {
  openwebui = {
    repository = "https://helm.openwebui.com"
    chart      = "open-webui"
    version    = "8.18.0"
    namespace  = "openwebui"

    host         = "chat.${var.base_domain}"
    storage_size = "16Gi"
  }
  chromadb = {
    repository   = "https://infracloudio.github.io/charts"
    chart        = "chromadb"
    version      = "0.1.4"
    storage_size = "16Gi"
  }
  tika = {
    repository = "https://apache.jfrog.io/artifactory/tika"
    chart      = "tika"
    version    = "2.9.0"
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

resource "random_password" "openwebui_client_id" {
  length  = 32
  special = false
}

resource "random_password" "openwebui_client_secret" {
  length  = 64
  special = true
}

resource "authentik_group" "openwebui_admin_group" {
  name = "openwebui-admins"
}

resource "authentik_group" "openwebui_user_group" {
  name = "openwebui-users"
}

resource "authentik_provider_oauth2" "openwebui" {
  depends_on = [
    helm_release.authentik,
  ]
  name               = "openwebui"
  client_type        = "confidential"
  client_id          = random_password.openwebui_client_id.result
  client_secret      = random_password.openwebui_client_secret.result
  authorization_flow = data.authentik_flow.default_authorization_flow.id
  invalidation_flow  = data.authentik_flow.default_invalidation_flow.id
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
  meta_icon         = "https://simpleicons.org/icons/langchain.svg"
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
      storage_size         = local.openwebui.storage_size
      openid_provider_url  = "https://${local.authentik.host}/application/o/openwebui-slug/.well-known/openid-configuration"
      openid_provider_name = "authentik"
      openid_redirect_uri  = "https://${local.openwebui.host}/oauth/oidc/callback"
    })
  ]
}
