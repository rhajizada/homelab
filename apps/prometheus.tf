locals {
  prometheus = {
    repository                 = "https://prometheus-community.github.io/helm-charts"
    chart                      = "prometheus"
    version                    = "27.5.1"
    namespace                  = "prometheus"
    storage_size               = "8Gi"
    alert_manager_storage_size = "2Gi"
  }
}

resource "kubernetes_namespace" "prometheus_namespace" {
  metadata {
    name = local.prometheus.namespace
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

resource "helm_release" "prometheus" {
  depends_on = [
    kubernetes_namespace.prometheus_namespace
  ]

  name       = "prometheus"
  repository = local.prometheus.repository
  chart      = local.prometheus.chart
  version    = local.prometheus.version
  namespace  = local.prometheus.namespace

  values = [
    templatefile("${path.module}/templates/prometheus.yaml.tmpl", {
      storage_size               = local.prometheus.storage_size
      alert_manager_storage_size = local.prometheus.alert_manager_storage_size
    })
  ]
}
