output "authentik_bootstrap_password" {
  description = "authentik bootstrap password"
  value       = random_password.authentik_bootstrap_password.result
  sensitive   = true
}

output "gitea_admin_credentials" {
  description = "gitea admin user credentials"
  value = {
    username = local.gitea.admin.username
    email    = local.gitea.admin.email
    password = random_password.gitea_admin_password.result
  }
  sensitive = true
}

output "grafana_admin_credentials" {
  description = "grafana admin user credentials"
  value = {
    username = local.grafana.admin.username
    password = random_password.grafana_admin_password.result
  }
  sensitive = true
}

output "harbor_admin_password" {
  description = "harbor admin password"
  value       = random_password.harbor_admin_password.result
  sensitive   = true
}

output "minio_admin_credentials" {
  description = "minio admin user credentials"
  value = {
    username = local.minio.admin.username
    password = random_password.minio_admin_password.result
  }
  sensitive = true
}

output "argocd_admin_password" {
  description = "argocd admin password"
  value       = random_password.argocd_admin_password.result
  sensitive   = true
}


output "gazette_oauth_credentials" {
  description = "Gazette OAuth credentials"
  value = {
    client_id     = authentik_provider_oauth2.gazette.client_id
    client_secret = authentik_provider_oauth2.gazette.client_secret
  }
  sensitive = true
}
