variable "proxmox_endpoint" {
  description = "Proxmox host endpoint"
  type        = string
}

variable "proxmox_node_name" {
  description = "Proxmox node name"
  type        = string
}


variable "cluster_name" {
  description = "Cluster name"
  type        = string
}

variable "dns_name" {
  description = "VPN server dns"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name (e.g dev/staging/prod)"
  type        = string
}

variable "ubuntu_version" {
  description = "Version of Ubuntu to deploy for VPN VM"
  type        = string
  default     = "noble"
}

variable "cluster_network_gateway" {
  description = "The IP network gateway of the cluster nodes"
  type        = string
  default     = "192.168.1.1"
}

variable "cluster_node_network" {
  description = "The IP network of the cluster nodes"
  type        = string
  default     = "192.168.1.1/24"
}

variable "vm_config" {
  description = "Configuration for VPN node VMs"
  type = object({
    cpu = number
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
    ip      = string
  })
  default = {
    cpu = 1
    disk = {
      datastore_id = "local-lvm"
      interface    = "scsi0"
      iothread     = true
      ssd          = true
      discard      = "on"
      size         = 16
      file_format  = "raw"
    }
    efi_disk = {
      datastore_id = "local-lvm"
      file_format  = "raw"
      type         = "4m"
    }
    memory  = 2048
    network = "vmbr0"
    ip      = "192.168.1.80"
  }
}
