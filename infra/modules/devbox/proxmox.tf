locals {
  devbox_node = {
    name = "${var.cluster_name}-${var.environment}-devbox"
  }
}

resource "tls_private_key" "root_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "random_password" "admin_password" {
  length  = 24
  special = false
}

resource "proxmox_virtual_environment_file" "devbox_user_data" {

  depends_on = [
    tls_private_key.root_ssh
  ]
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node_name

  source_raw {
    data = <<-EOF
      #cloud-config
      hostname: ${local.devbox_node.name}
      users:
        - name: ${var.admin_user}
          groups:
            - sudo
          shell: /bin/bash
          ssh_authorized_keys:
            - ${tls_private_key.root_ssh.public_key_openssh}
          sudo: ALL=(ALL) NOPASSWD:ALL
          lock_passwd: true
      ssh_pwauth: false
      runcmd:
        - pacman -Sy --noconfirm
        - pacman -S --noconfirm qemu-guest-agent avahi-daemon
        - systemctl enable --now qemu-guest-agent
        - systemctl enable --now avahi-daemon
        - echo "done" > /tmp/cloud-config.done
      EOF

    file_name = "devbox-user-data-cloud-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "devbox_node" {
  depends_on = [
    proxmox_virtual_environment_file.devbox_user_data
  ]

  name            = local.devbox_node.name
  node_name       = var.proxmox_node_name
  tags            = sort([var.cluster_name, var.environment, "ubuntu", "devbox", "terraform"])
  stop_on_destroy = true
  bios            = "ovmf"
  machine         = "q35"
  scsi_hardware   = "virtio-scsi-single"

  operating_system {
    type = "l26"
  }

  cpu {
    type  = "host"
    cores = var.vm_config.cpu
  }

  memory {
    dedicated = var.vm_config.memory
  }

  vga {
    type = "qxl"
  }

  network_device {
    bridge = var.vm_config.network
  }

  tpm_state {
    version = "v2.0"
  }

  efi_disk {
    datastore_id = var.vm_config.efi_disk.datastore_id
    file_format  = var.vm_config.efi_disk.file_format
    type         = var.vm_config.efi_disk.type
  }

  disk {
    datastore_id = var.vm_config.disk.datastore_id
    interface    = var.vm_config.disk.interface
    iothread     = var.vm_config.disk.iothread
    ssd          = var.vm_config.disk.ssd
    discard      = var.vm_config.disk.discard
    size         = var.vm_config.disk.size
    file_format  = var.vm_config.disk.file_format
    file_id      = var.arch_image
  }

  agent {
    enabled = true
    trim    = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.ip_address}/24"
        gateway = var.cluster_network_gateway
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.devbox_user_data.id
  }
}
