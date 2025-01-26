locals {
  image = {
    file_name = "Arch-Linux-x86_64-cloudimg.img",
    url       = "https://geo.mirror.pkgbuild.com/images/v${var.archlinux_version}/Arch-Linux-x86_64-cloudimg.qcow2"
  }
}

resource "proxmox_virtual_environment_download_file" "archlinux_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.proxmox_node_name

  file_name = local.image.file_name
  url       = local.image.url
}

