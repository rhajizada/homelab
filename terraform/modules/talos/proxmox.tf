locals {
  control_nodes = [
    for i in range(var.vm_config["control"].count) : {
      name    = "${var.cluster_name}-${var.environment}-ctrl-${i}"
      address = cidrhost(var.cluster_node_network, var.vm_config["control"].first_hostnum + i)
    }
  ]
  worker_nodes = [
    for i in range(var.vm_config["worker"].count) : {
      name    = "${var.cluster_name}-${var.environment}-worker-${i}"
      address = cidrhost(var.cluster_node_network, var.vm_config["worker"].first_hostnum + i)
    }
  ]
}


resource "proxmox_virtual_environment_vm" "talos_control_plane" {
  count           = var.vm_config["control"].count
  name            = local.control_nodes[count.index].name
  node_name       = var.proxmox_node_name
  tags            = sort([var.cluster_name, var.environment, "talos", "control", "terraform"])
  stop_on_destroy = true
  bios            = "ovmf"
  machine         = "q35"
  scsi_hardware   = "virtio-scsi-single"
  operating_system {
    type = "l26"
  }
  cpu {
    type  = "host"
    cores = var.vm_config["control"].cpu
  }
  memory {
    dedicated = var.vm_config["control"].memory
  }
  vga {
    type = "qxl"
  }
  network_device {
    bridge = var.vm_config["control"].network
  }
  tpm_state {
    version = "v2.0"
  }
  efi_disk {
    datastore_id = var.vm_config["control"].efi_disk.datastore_id
    file_format  = var.vm_config["control"].efi_disk.file_format
    type         = var.vm_config["control"].efi_disk.type
  }
  disk {
    datastore_id = var.vm_config["control"].disk.datastore_id
    interface    = var.vm_config["control"].disk.interface
    iothread     = var.vm_config["control"].disk.iothread
    ssd          = var.vm_config["control"].disk.ssd
    discard      = var.vm_config["control"].disk.discard
    size         = var.vm_config["control"].disk.size
    file_format  = var.vm_config["control"].disk.file_format
    file_id      = proxmox_virtual_environment_download_file.talos_nocloud_image.id
  }
  agent {
    enabled = true
    trim    = true
  }
  initialization {
    ip_config {
      ipv4 {
        address = "${local.control_nodes[count.index].address}/24"
        gateway = var.cluster_network_gateway
      }
    }
  }
}

resource "proxmox_virtual_environment_vm" "talos_worker" {
  count           = var.vm_config["worker"].count
  name            = local.worker_nodes[count.index].name
  node_name       = var.proxmox_node_name
  tags            = sort([var.cluster_name, var.environment, "talos", "worker", "terraform"])
  stop_on_destroy = true
  bios            = "ovmf"
  machine         = "q35"
  scsi_hardware   = "virtio-scsi-single"
  operating_system {
    type = "l26"
  }
  cpu {
    type  = "host"
    cores = var.vm_config["worker"].cpu
  }
  memory {
    dedicated = var.vm_config["worker"].memory
  }
  vga {
    type = "qxl"
  }
  network_device {
    bridge = var.vm_config["worker"].network
  }
  tpm_state {
    version = "v2.0"
  }
  efi_disk {
    datastore_id = var.vm_config["worker"].efi_disk.datastore_id
    file_format  = var.vm_config["worker"].efi_disk.file_format
    type         = var.vm_config["worker"].efi_disk.type
  }
  disk {
    datastore_id = var.vm_config["worker"].disk.datastore_id
    interface    = var.vm_config["worker"].disk.interface
    iothread     = var.vm_config["worker"].disk.iothread
    ssd          = var.vm_config["worker"].disk.ssd
    discard      = var.vm_config["worker"].disk.discard
    size         = var.vm_config["worker"].disk.size
    file_format  = var.vm_config["worker"].disk.file_format
    file_id      = proxmox_virtual_environment_download_file.talos_nocloud_image.id
  }
  agent {
    enabled = true
    trim    = true
  }
  initialization {
    ip_config {
      ipv4 {
        address = "${local.worker_nodes[count.index].address}/24"
        gateway = var.cluster_network_gateway
      }
    }
  }
}

