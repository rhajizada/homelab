output "authentik_bootstrap_password" {
  description = "authentik bootstrap password"
  value       = random_password.authentik_bootstrap_password.result
  sensitive   = true
}
