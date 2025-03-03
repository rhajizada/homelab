variable "base_domain" {
  description = "Base domain that will be serving the cluster"
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^([a-zA-Z0-9][-a-zA-Z0-9]*\\.)+[a-zA-Z]{2,}$", var.base_domain)) || var.base_domain == ""
    error_message = "'base_domain' must be a valid domain name or an empty string"
  }
}

variable "k8s_version" {
  type        = string
  description = "Version of Kubenetes to deploy"
  default     = "1.32.1"
  validation {
    condition     = can(regex("^\\d+(\\.\\d+)+", var.k8s_version))
    error_message = "must be a version number"
  }
}

variable "kubeconfig" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "~/.kube/config"

  validation {
    condition     = fileexists(var.kubeconfig)
    error_message = "kubeconfig not found"
  }
}

variable "cluster_cert_issuer" {
  description = "K8s cert-manager cluster issuer"
  type        = string
}
