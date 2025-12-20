# Repository Guidelines

## Project Structure & Module Organization
`infra/` hosts the Terraform root module for provisioning Proxmox VMs, Talos nodes, networking, and AWS integrations. Layer-specific code lives under `infra/modules/{talos,dns,vpn,route53}`; extend modules rather than editing root `main.tf`. `apps/` deploys post-bootstrap Kubernetes workloads and is organised by application (`authentik.tf`, `grafana.tf`, etc.), with reusable manifests in `apps/templates/` and runner tooling under `apps/scripts/`. Shared diagrams and reference assets live in `assets/`. The root `Taskfile.yaml` fans out to `infra/Taskfile.yaml` and `apps/Taskfile.yaml` so automation stays consistent across environments.

## Build, Test, and Development Commands
Use Task for all workflows. Typical flow:
- `task infra:init` / `task apps:init` to install providers and backends.
- `task infra:plan` or `task apps:plan` to review changes.
- `task infra:apply` or `task apps:apply` to reconcile state.
- `task infra:kubeconfig symlink=true` and `task infra:talosconfig` to generate client configs.
- `task apps:secrets app=<name>` to inspect bootstrap credentials when validating a rollout.

## Coding Style & Naming Conventions
Follow standard Terraform formatting: two-space indentation, one resource per block, and descriptive snake_case names (`proxmox_vm_dns`). Run `task infra:format` and `task apps:format` before committing; these wrap `terraform fmt`. Keep environment overrides in `*.tfvars` files named `dev.tfvars` or `prod.tfvars`, and avoid committing inline secrets. When adding modules, place shared locals and variables in `variables.tf` and `outputs.tf` to mirror the existing layout.

## Testing Guidelines
Always lint before plans: `task infra:validate` and `task apps:validate` run `terraform validate` with the configured backends. For behavioural tests, rely on `task infra:plan -- TF_VAR_env=...` and ensure outputs match expectations. Capture applied changes by exporting `TF_LOG` when diagnosing provider issues, and rotate test credentials after use.

## Commit & Pull Request Guidelines
Commits use short, imperative subjects (e.g., "migrate states to new bucket"). Group infrastructure and application changes separately so plans stay reviewable. Every PR should include: summary of the change, expected plan diff snippets or screenshots, linked tracking issues, and any follow-up tasks. Request review from an owner of the affected layer and confirm `task *:plan` runs clean against both `dev.tfvars` and `prod.tfvars`.

## Security & Configuration Tips
Store AWS and Proxmox credentials in local environment files or your secrets manager; never hard-code them in Terraform. Rotate Talos machine secrets after sharing, and purge generated artifacts (`talosconfig`, `wireguard` bundles) from the repo. When testing new services, prefer staging values in `dev.tfvars` and promote them through PR review before touching production configurations.
