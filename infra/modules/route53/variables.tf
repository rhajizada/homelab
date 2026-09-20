variable "base_domain" {
  description = "Base domain name to create a hosted zone for"
  type        = string
}

variable "cluster_name" {
  description = "Cluster name"
  type        = string
}

variable "dns_name" {
  description = "DNS name to assign to cluster public IP"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g dev/staging/prod)"
  type        = string
}

variable "custom_records" {
  description = "Custom DNS records to create in the hosted zone using subdomain labels relative to base_domain"
  type = list(object({
    name          = string
    type          = string
    ttl           = number
    records       = optional(list(string), [])
    use_public_ip = optional(bool, false)
  }))
  default = []

  validation {
    condition = alltrue([
      for record in var.custom_records : record.use_public_ip || length(record.records) > 0
    ])
    error_message = "Custom DNS records must specify records unless use_public_ip is true."
  }
}
