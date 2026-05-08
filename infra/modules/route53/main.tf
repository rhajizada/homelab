data "aws_region" "this" {}

locals {
  tags = {
    cluster = var.cluster_name
    env     = var.environment
  }

  custom_records = [
    for record in var.custom_records : merge(record, {
      fqdn = record.name == "" || record.name == "@" ? var.base_domain : "${record.name}.${var.base_domain}"
    })
  ]
}

data "http" "current_ip" {
  url = "https://api.ipify.org?format=json"
}

resource "aws_route53_zone" "main" {
  name = var.base_domain
  tags = local.tags
}

resource "aws_route53_record" "vpn" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.dns_name
  type    = "A"
  ttl     = 300
  records = [jsondecode(data.http.current_ip.response_body).ip]
}

resource "aws_route53_record" "custom" {
  for_each = {
    for record in local.custom_records : "${record.fqdn}:${record.type}" => record
  }

  zone_id = aws_route53_zone.main.zone_id
  name    = each.value.fqdn
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.records
}

resource "aws_route53domains_registered_domain" "domain" {
  domain_name = var.base_domain

  dynamic "name_server" {
    for_each = aws_route53_zone.main.name_servers
    content {
      name = name_server.value
    }
  }
}
