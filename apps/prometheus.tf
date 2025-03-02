locals {
  prometheus = {
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
  depends_on = [kubernetes_namespace.prometheus_namespace]
  namespace  = local.prometheus.namespace
  name       = "prometheus"
  chart      = "prometheus-community/prometheus"
  version    = local.prometheus.version


  values = [
    templatefile("${path.module}/templates/prometheus.yaml.tmpl", {
      storage_size               = local.prometheus.storage_size
      alert_manager_storage_size = local.prometheus.alert_manager_storage_size
    })
  ]
}
