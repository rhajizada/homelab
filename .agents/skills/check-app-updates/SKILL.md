---
name: check-app-updates
description: Audit application updates managed by Terraform in this repository. Use this skill whenever the user asks which apps, Helm charts, container images, or app dependencies under apps/ are outdated; requests an upgrade report; or asks about compatibility or breaking changes before updating the homelab. It maps a Terraform file to one logical app, verifies deployed and configured versions, researches authoritative releases, and produces a risk-sorted Markdown update table.
compatibility: Agent Skills-compatible host with repository and internet access. Uses kubectl and helm when cluster credentials are available.
---

## Purpose

Produce a trustworthy update report for the Kubernetes applications defined in `apps/*.tf`.

The repository deliberately mixes deployment styles. A Terraform file is the ownership boundary for one logical application or platform component, not each Terraform resource. For example, `apps/openwebui.tf` is the **Open WebUI** application; its Open WebUI chart, ChromaDB chart, Tika chart, SearXNG deployment, and Playwright deployment are components of that application. Conversely, `apps/code.tf` is a standalone VS Code deployment.

This grouping prevents a report from presenting implementation details as unrelated applications and makes upgrade risk visible in its real context.

## Workflow

### 1. Establish scope and evidence

1. Confirm the target is `apps/*.tf` unless the user provides a narrower path.
2. Record the report date and the git revision if available.
3. Check whether `kubectl` can query the configured cluster and whether `helm` can list releases. Do not change cluster state.
4. If cluster access is unavailable, continue with the Terraform-configured versions and label them **configured, not cluster-verified**. Do not call these deployed versions.
5. Use public, authoritative release sources. Record every source URL used. Do not invent an available version when a registry, chart repository, or release page cannot be queried.

### 2. Build an application inventory from Terraform semantics

Read every selected `.tf` file in full before extracting versions. Do not use a grep result or filename alone as the inventory.

For each file:

1. Treat the file basename as the default logical application boundary. Keep all of its Helm releases, Kubernetes workloads, templates, and support resources under that app.
2. Read the `locals` block and resolve references used by `helm_release`, `kubernetes_deployment`, `kubernetes_stateful_set`, `kubernetes_daemon_set`, and `kubernetes_cron_job` resources. Follow values through nested local objects, such as `local.gitea.actions.version`.
3. Inspect referenced `templatefile()` and `file()` inputs when they can set an image, image tag, chart value, or an upgrade-sensitive configuration.
4. Use `depends_on`, namespace, resource names, and local-object prefixes to identify components. A component may be a Helm release, an application container, a datastore, a search service, browser service, or another deliberate sub-service.
5. Exclude Terraform providers, random resources, secrets, ingress/auth configuration, dashboards, and unversioned helper resources from the application dependency rows unless they directly pin a deployable artifact.
6. Treat init containers and one-shot helper images as support dependencies. Include a pinned helper only when it has an update or compatibility implication; otherwise mention it in the app notes rather than splitting it into its own app.
7. Preserve explicitly independent applications even if they depend on a shared platform release. For example, an application depending on Authentik is not a component of Authentik.

Create a working inventory with these fields before researching updates:

| Field | Meaning |
| --- | --- |
| App | Logical Terraform-file ownership boundary, with a friendly name when clear |
| Component | Helm release or workload/container within that app |
| Type | `Helm chart`, `container image`, `application version`, or `unknown/moving tag` |
| Configured version | Literal resolved chart version, image digest/tag, or app version |
| Deployment locator | Namespace, Helm release name, workload name, and container name when available |
| Source locator | Chart repository/chart or container registry/image |

Do not collapse distinct artifacts with independent version lifecycles. For example, report a Helm chart and an explicitly overridden image tag as separate dependency rows, while keeping them in the same application group.

### 3. Verify the current deployment

Prefer observed cluster state over Terraform configuration, while showing both when they differ.

1. For Helm components, inspect `helm list --all-namespaces --output json` and match the configured release name and namespace. Capture the installed chart version and app version when Helm supplies both.
2. For Kubernetes workloads, inspect the matching Deployment, StatefulSet, DaemonSet, or CronJob with `kubectl get ... -o json`. Match its namespace, workload name, and container name, then capture the running image reference and immutable image digest when exposed in status.
3. Consider a mutable tag (`latest`, `stable`, branch-like tag, or an unversioned image) a moving target. Its exact deployed version is unknown unless an immutable digest or image ID is observed. State that limitation prominently; never present the tag as a precise version.
4. If the observed artifact differs from Terraform, report both and add **configuration drift** to the change list. Do not silently choose either value.
5. Never run `terraform apply`, Helm upgrade/install commands, or mutating `kubectl` commands for this task.

### 4. Discover the latest compatible release

Research each independently versioned artifact from its authoritative publisher:

| Artifact | Preferred source | What to capture |
| --- | --- | --- |
| Helm chart | Chart repository `index.yaml`, `helm show chart --repo <url> <chart>`, or publisher release notes | Latest chart version and its `appVersion` when available |
| Docker Hub image | Official image page/API and upstream releases | Latest supported stable tag; avoid treating `latest` as a version |
| GHCR or another registry | Registry tags/releases, then the upstream project release notes | Latest stable immutable release tag or digest when the project publishes one |
| Image pinned to a commit SHA | Upstream repository commits/releases | Whether the commit is behind; name the target release only with evidence |
| Application version supplied separately from image | The application's official releases | Latest supported version and its required image/configuration compatibility |

Rules:

1. Prefer stable releases over prereleases, nightly builds, and release candidates unless the configured value intentionally uses that channel.
2. Respect explicit release channels. Compare a `stable-*` tag with the latest appropriate stable channel, not arbitrary numeric tags.
3. Distinguish chart version from chart `appVersion`; a chart update can package a different application version and can also change defaults independently.
4. For a major-version target, read the intermediate major migration guides too. A change from v1 to v3 is not adequately assessed from only v3 release notes.
5. If an artifact is unpinned or cannot be authoritatively enumerated, use `unverified` for the next version and explain the evidence gap. Do not guess based on search snippets.

### 5. Assess upgrade compatibility

Read official changelogs, migration guides, chart release notes, and upgrade documentation for every version range. Link the supporting sources.

Assign exactly one category to each dependency, using evidence rather than version-number heuristics alone:

| Category | Meaning | Typical evidence |
| --- | --- | --- |
| 1. Routine | No documented breaking changes in the target range; only compatible patch/minor changes or chart maintenance. | Release notes explicitly say compatible, or no breaking/migration notes for a bounded patch range. |
| 2. Review required | Compatibility is uncertain, upgrade spans a meaningful minor/major range, a chart changes values/defaults, a moving tag obscures the current state, or release notes call for operator review. | Deprecated values, changed defaults, renamed settings, runtime/version prerequisites, or incomplete version evidence. |
| 3. Breaking or migration | Official documentation identifies a breaking change, migration, schema/storage action, CRD/API transition, downtime requirement, or incompatible configuration change. | Required migration commands, removed settings, database upgrade caveats, Kubernetes compatibility break, or major upgrade guide. |

Use category 2 when evidence is incomplete. Category 1 is appropriate only when the version comparison and release-note coverage are both clear. A major version is at least category 2 until documented otherwise, but can be category 3 only when a concrete breaking/migration requirement is identified.

For each row, write a concise change list that includes the actionable reason for its category. Cite release-note links next to material claims. Do not claim an upgrade is safe solely because it is a patch update.

### 6. Produce the Markdown report

Use this format. Keep all rows sorted from category 1 to category 3, then by application and component. Grouping rows visually under the same app is encouraged, but do not disturb the risk ordering.

```markdown
# Application Update Report

Generated: YYYY-MM-DD
Scope: `apps/*.tf` at `<git revision or unavailable>`
Deployment evidence: `<cluster verified | configured only; reason>`

## Summary

| Category | Updates | Meaning |
| --- | ---: | --- |
| 1. Routine | N | No documented breaking change in the reviewed range |
| 2. Review required | N | Validate values, compatibility, or uncertain version evidence |
| 3. Breaking or migration | N | Plan explicit migration or disruptive compatibility work |

## Update Matrix

| Risk | App | Component | Type | Current deployed | Terraform configured | Next available | Change list | Sources |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1. Routine | Example app | web | container image | `1.2.0` | `1.2.0` | `1.2.3` | Patch fixes only; no breaking changes documented. | [release notes](https://example.invalid) |

## Needs Attention

- List configuration drift, unpinned/moving tags, inaccessible registries, release-note gaps, and assumptions.

## Upgrade Order

1. List category 1 items first, then category 2, then category 3.
2. Within an app, state dependency ordering when it matters, such as a chart before its dependent workload.
3. For category 3, name the migration guide, backup/checkpoint, and expected validation needed before applying.
```

Use `not observed`, `unverified`, or `moving tag` instead of a fabricated version. If no updates are found, still include the inventory rows and say so clearly.

## Repository-specific examples

- `apps/openwebui.tf`: one **Open WebUI** application with Open WebUI, ChromaDB, Tika, SearXNG, and Playwright components. Its `busybox` init container is support infrastructure, not a sixth app.
- `apps/llamero.tf`: one **Llamero** application with PostgreSQL, Redis, server, worker, scheduler, UI, and Ollama components.
- `apps/gitea.tf`: one **Gitea** application with the Gitea and Actions Helm chart components.
- `apps/code.tf`: one **VS Code** standalone workload.
- `apps/kube_prometheus.tf`, `apps/csi_driver_smb.tf`, and `apps/dcgm_exporter.tf`: platform components. Keep them as logical applications in the report, and clearly mark their cluster-wide compatibility risk when relevant.
