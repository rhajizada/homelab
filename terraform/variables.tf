variable "proxmox_endpoint" {
  description = "Proxmox host endpoint"
  type        = string
}

variable "proxmox_node_name" {
  description = "Proxmox node name"
  type        = string
}


variable "cluster_name" {
  description = "Talos cluster name"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g dev/staging/prod)"
  type        = string
}

variable "talos_version" {
  description = "Version of Talos to install"
  type        = string
  default     = "v1.9.2"
}

#  please see https://github.com/siderolabs/extensions?tab=readme-ov-file#installing-extensions
variable "talos_extensions" {
  description = "Map of Talos extension name to a specific version"
  type        = map(string)
  default = {
    "intel-ucode"      = "20241112"
    "qemu-guest-agent" = "9.2.0"
  }
}

variable "cluster_node_network_gateway" {
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
    first_hostnum = number
    memory        = number
    network       = string
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
      first_hostnum = 70
      memory        = 4096
      network       = "vmbr0"
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
      first_hostnum = 80
      memory        = 4096
      network       = "vmbr0"
    }
  }
}
