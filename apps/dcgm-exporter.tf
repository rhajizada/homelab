locals {
  dcgm = {
    repository = "https://nvidia.github.io/dcgm-exporter/helm-charts"
    chart      = "dcgm-exporter"
    version    = "4.1.0"
    namespace  = "dcgm"
  }
}

resource "kubernetes_namespace" "dcgm_namespace" {
  metadata {
    name = local.dcgm.namespace
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

resource "helm_release" "dcgm" {
  depends_on = [
    kubernetes_namespace.dcgm_namespace,
  ]

  name       = "dcgm"
  chart      = local.dcgm.chart
  repository = local.dcgm.repository
  version    = local.dcgm.version
  namespace  = local.dcgm.namespace

  timeout = 600

  values = [
    file("${path.module}/templates/dcgm-exporter.yaml.tmpl")
  ]
}
