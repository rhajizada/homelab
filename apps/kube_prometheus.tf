locals {
  monitoring = {
    repository = "https://prometheus-community.github.io/helm-charts"
    chart      = "kube-prometheus-stack"
    version    = "82.16.0"
    namespace  = "monitoring"
    host       = "grafana.${var.base_domain}"
    groups     = ["grafana-editors", "grafana-admins"]

    grafana = {
      admin = {
        username = "admin"
      }
    }

    prometheus = {
      storage_size = "8Gi"
    }

    alertmanager = {
      storage_size = "2Gi"
    }
  }
}

resource "kubernetes_namespace" "monitoring_namespace" {
  metadata {
    name = local.monitoring.namespace
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

resource "random_password" "grafana_admin_password" {
  length  = 16
  special = false
}

resource "random_password" "grafana_client_id" {
  length  = 32
  special = false
}

resource "random_password" "grafana_client_secret" {
  length  = 64
  special = true
}

resource "authentik_group" "grafana_groups" {
  depends_on = [helm_release.authentik]
  for_each   = toset(local.monitoring.groups)
  name       = each.value
}

resource "authentik_provider_oauth2" "grafana" {
  depends_on = [
    helm_release.authentik
  ]

  name                    = "grafana"
  client_type             = "confidential"
  client_id               = random_password.grafana_client_id.result
  client_secret           = random_password.grafana_client_secret.result
  authorization_flow      = data.authentik_flow.default_authorization_flow.id
  invalidation_flow       = data.authentik_flow.default_invalidation_flow.id
  logout_method           = "backchannel"
  refresh_token_threshold = "seconds=0"

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://${local.monitoring.host}/login/generic_oauth"
    }
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
    data.authentik_property_mapping_provider_scope.openid.id,
  ]

  signing_key = data.authentik_certificate_key_pair.generated.id
}

resource "authentik_application" "grafana" {
  name              = "Grafana"
  slug              = "grafana-slug"
  protocol_provider = authentik_provider_oauth2.grafana.id
  meta_icon         = "https://simpleicons.org/icons/grafana.svg"
}

resource "kubernetes_secret" "grafana_admin_secret" {
  metadata {
    name      = "grafana-admin-secret"
    namespace = local.monitoring.namespace
  }

  data = {
    user     = local.monitoring.grafana.admin.username
    password = random_password.grafana_admin_password.result
  }

  type = "Opaque"
}

resource "kubernetes_secret" "grafana_authentik_secret" {
  metadata {
    name      = "grafana-authentik-secret"
    namespace = local.monitoring.namespace
  }

  data = {
    client_id     = random_password.grafana_client_id.result
    client_secret = random_password.grafana_client_secret.result
  }

  type = "Opaque"
}

resource "helm_release" "kube_prometheus_stack" {
  depends_on = [
    kubernetes_namespace.monitoring_namespace,
    kubernetes_secret.grafana_admin_secret,
    kubernetes_secret.grafana_authentik_secret,
    authentik_application.grafana,
  ]

  name       = "kube-prometheus-stack"
  repository = local.monitoring.repository
  chart      = local.monitoring.chart
  version    = local.monitoring.version
  namespace  = local.monitoring.namespace

  values = [
    templatefile("${path.module}/templates/kube-prometheus-stack.yaml.tmpl", {
      oauth_name                = "authentik"
      oauth_slug                = "grafana-slug"
      oauth_scopes              = "openid profile email"
      authentik_host            = local.authentik.host
      host                      = local.monitoring.host
      cert_issuer               = var.cluster_cert_issuer
      prometheus_storage_size   = local.monitoring.prometheus.storage_size
      alertmanager_storage_size = local.monitoring.alertmanager.storage_size
    })
  ]
}
