locals {
  tags = {
    cluster = var.cluster_name
    env     = var.environment
  }
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
