locals {
  image = {
    file_name = "ubuntu-${var.ubuntu_version}-server-cloudimg-amd64.img",
    url       = "https://cloud-images.ubuntu.com/releases/${var.ubuntu_version}/release/ubuntu-${var.ubuntu_version}-server-cloudimg-amd64.img"
  }
}

resource "proxmox_virtual_environment_download_file" "ubuntu_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.proxmox_secondary_node

  file_name = local.image.file_name
  url       = local.image.url
}
