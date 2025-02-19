locals {
  longhorn = {
    version = "1.8.0"
  }
}

data "helm_template" "longhorn" {
  namespace    = "longhorn-system"
  name         = "longhorn"
  chart        = "longhorn/longhorn"
  version      = local.longhorn.version
  kube_version = var.k8s_version

  values = [file("${path.module}/templates/longhorn.yaml")]
}
