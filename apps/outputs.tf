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
