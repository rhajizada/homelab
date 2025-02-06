variable "proxmox_endpoint" {
  description = "Proxmox host endpoint"
  type        = string
}

variable "proxmox_node_name" {
  description = "Proxmox node name"
  type        = string
}

variable "base_domain" {
  description = "Base domain that will be serving the cluster"
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^([a-zA-Z0-9][-a-zA-Z0-9]*\\.)+[a-zA-Z]{2,}$", var.base_domain)) || var.base_domain == ""
    error_message = "'base_domain' must be a valid domain name or an empty string."
  }
}

variable "cluster_name" {
  description = "Cluster name"
  type        = string
}

variable "cluster_node_network" {
  description = "The IP network of the cluster nodes"
  type        = string
}

variable "cluster_network_gateway" {
  description = "The IP network gateway of the cluster nodes"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g dev/staging/prod)"
  type        = string
}

variable "extensions" {
  description = "Map of Talos extension name to a specific version"
  type        = map(string)
  default = {
    "intel-ucode"      = "20241112"
    "iscsi-tools"      = "v0.1.6"
    "qemu-guest-agent" = "9.2.0"
  }
}

variable "talos_version" {
  description = "Version of Talos to deploy"
  type        = string
}

variable "k8s_version" {
  type        = string
  description = "Version of Kubenetes to deploy"
  default     = "1.32.1"
  validation {
    condition     = can(regex("^\\d+(\\.\\d+)+", var.k8s_version))
    error_message = "Must be a version number."
  }
}

variable "k8s_vip" {
  description = "Talos Kubernetes VIP"
  type        = string
}


variable "k8s_lb_ip" {
  description = "Kubernetes load balancer IP"
  type        = string
}

variable "control_node_ips" {
  description = "List of control node IP adresses"
  type        = list(any)
}

variable "worker_node_ips" {
  description = "List of worker node IP adresses"
  type        = list(any)
}

variable "vm_config" {
  description = "Configuration for worker and control node VMs"
  type = map(object({
    count = number
    cpu   = number
    disk = object({
      datastore_id = string
      interface    = string
      iothread     = bool
      ssd          = bool
      discard      = string
      size         = number
      file_format  = string
    })
    efi_disk = object({
      datastore_id = string
      file_format  = string
      type         = string
    })
    memory  = number
    network = string
  }))
  default = {
    control = {
      count = 1
      cpu   = 2
      disk = {
        datastore_id = "local-lvm"
        interface    = "scsi0"
        iothread     = true
        ssd          = true
        discard      = "on"
        size         = 64
        file_format  = "raw"
      }
      efi_disk = {
        datastore_id = "local-lvm"
        file_format  = "raw"
        type         = "4m"
      }
      memory  = 4096
      network = "vmbr0"
    }
    worker = {
      count = 1
      cpu   = 2
      disk = {
        datastore_id = "local-lvm"
        interface    = "scsi0"
        iothread     = true
        ssd          = true
        discard      = "on"
        size         = 64
        file_format  = "raw"
      }
      efi_disk = {
        datastore_id = "local-lvm"
        file_format  = "raw"
        type         = "4m"
      }
      memory  = 4096
      network = "vmbr0"
  } }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_iam_credentials" {
  description = "AWS IAM user credentials for cert-manager"
  type = object({
    access_key_id     = string
    secret_access_key = string
  })
}

variable "aws_route53_zone_id" {
  description = "AWS Route 53 hosted zone id"
  type        = string
}

variable "acme_email" {
  description = "Email to use for ACME registration"
  type        = string
}

variable "acme_server" {
  description = "ACME server URL to use for certificate issuance"
  type        = string
}
