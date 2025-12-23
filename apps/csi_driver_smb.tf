locals {
  smb = {
    namespace     = "csi-driver-smb"
    release_name  = "csi-driver-smb"
    chart         = "csi-driver-smb"
    repository    = "https://raw.githubusercontent.com/kubernetes-csi/csi-driver-smb/master/charts"
    chart_version = "1.19.1"
    secret_name   = "smbcreds"
  }

  storage_classes = [
    for share in var.samba_credentials.shares : {
      share            = trim(share, "/")
      name             = "smb-${replace(replace(trim(share, "/"), "/", "-"), " ", "-")}"
      source           = "//${var.samba_credentials.address}/${trim(share, "/")}"
      secret_name      = local.smb.secret_name
      secret_namespace = local.smb.namespace
      reclaim_policy   = "Delete"
    }
  ]
}

resource "kubernetes_namespace" "smb" {
  metadata {
    name = local.smb.namespace
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

resource "kubernetes_secret" "smbcreds" {
  metadata {
    name      = local.smb.secret_name
    namespace = local.smb.namespace
  }

  data = {
    username = var.samba_credentials.username
    password = var.samba_credentials.password
  }

  type = "Opaque"
}

resource "helm_release" "csi_smb" {
  depends_on = [
    kubernetes_namespace.smb,
    kubernetes_secret.smbcreds,
  ]

  name       = local.smb.release_name
  chart      = local.smb.chart
  repository = local.smb.repository
  version    = local.smb.chart_version
  namespace  = local.smb.namespace

  timeout = 600

  values = [
    templatefile("${path.module}/templates/csi-driver-smb.yaml.tmpl", {
      storage_classes = local.storage_classes
    })
  ]
}

