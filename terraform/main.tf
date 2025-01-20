
locals {
  payload            = jsondecode(file("${path.module}/payload.json"))
  talos_schematic_id = jsondecode(data.http.talos_schematic_request.response_body).id
}

data "http" "talos_schematic_request" {
  url    = "https://factory.talos.dev/schematics"
  method = "POST"

  request_headers = {
    "Content-Type" = "application/json"
  }

  request_body = jsonencode(local.payload)
}

resource "proxmox_virtual_environment_download_file" "talos_nocloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.proxmox_node

  file_name = "talos-${var.talos_version}-nocloud-amd64.img"
  url       = "https://factory.talos.dev/image/${local.talos_schematic_id}/v${var.talos_version}/nocloud-amd64.iso"
}
