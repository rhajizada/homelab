locals {
  image = {
    file_name = "${var.ubuntu_version}-server-cloudimg-amd64.img",
    url       = "https://cloud-images.ubuntu.com/${var.ubuntu_version}/current/${var.ubuntu_version}-server-cloudimg-amd64.img"
  }
}

resource "proxmox_virtual_environment_download_file" "ubuntu_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.proxmox_node_name

  file_name = local.image.file_name
  url       = local.image.url
}
