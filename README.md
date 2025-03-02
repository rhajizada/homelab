# homelab

This repository contains the complete Terraform configuration for bootstrapping
my homelab environment. It automates every step—from provisioning Proxmox VMs
and bootstrapping a Talos-based Kubernetes cluster to deploying Kubernetes
applications using Infrastructure-as-Code (IaC) principles.

## Overview

The homelab setup is organized into two main layers:

- **Infrastructure (infra):**
  This layer uses Terraform modules to provision Proxmox VMs, set up a [Talos Linux](https://www.talos.dev/) based Kubernetes cluster, and configure essential networking. Key components include:
  - **VM Provisioning:**
    An Ubuntu 24.04 Server image is used to create VMs on Proxmox. CloudInit templates perform initial configuration tasks (e.g., installing necessary agents like the qemu-guest-agent).
  - **Kubernetes Cluster Bootstrap:**
    Talos VMs are used to establish both control and worker nodes. A kube VIP ensures high availability of the Kubernetes API, while MetalLB allocates a dedicated IP for load balancing.
  - **Networking & DNS:**
    A designated CIDR range is used to automatically assign IP addresses for the DNS and VPN servers, the kube VIP, MetalLB, and Talos nodes.
  - **DNS & Certificate Management:**
    - **CoreDNS** is deployed as the local DNS server. It mirrors AWS Route53 records to support automatic certificate challenges via cert-manager.
    - **Cert-manager** obtains certificates through ACME (using Route53 for DNS challenges) to secure the cluster.
    - **Traefik** is deployed as the ingress controller on Kubernetes, routing wildcard DNS queries to the appropriate services.
  - **Storage:**
    **Longhorn** is used for persistent storage, enabling dynamic provisioning and volume management across the cluster.
  - **AWS Integration:**
    AWS is used in two key areas:
    - **Terraform Backend:**
      An AWS S3 bucket securely stores Terraform state files.
    - **Route53 for DNS:**
      Cert-manager leverages AWS Route53 (along with provided IAM credentials) to perform DNS challenges and update DNS records automatically.

- **Kubernetes Applications (apps):**
  Once the cluster is bootstrapped, configurations in the `apps` folder deploy various Kubernetes applications (e.g., authentik, gitea, grafana, harbor, minio, and prometheus) into the cluster.

## Topology

- **Note:**
  The router is configured to route all DNS traffic to the dedicated DNS network and forward VPN traffic to the VPN node.

- **VM Provisioning & Cluster Bootstrapping:**
  Terraform provisions VMs for:
  - **DNS Server:** Runs CoreDNS.
  - **VPN Server:** Provides secure remote access.
  - **Kubernetes Cluster Nodes:**
    - **Talos Control Nodes:** Equipped with a kube VIP for high availability of the Kubernetes API.
    - **Talos Worker Nodes:** Automatically assigned IP addresses from a specified CIDR range.
  
- **Ingress & Storage:**
  - **Traefik** manages inbound traffic by routing wildcard DNS domains to services deployed on Kubernetes.
  - **Longhorn** provides the storage backend for the cluster.

## Taskfile Workflow

This project leverages [Taskfile](https://github.com/go-task/task) (go-task) to streamline Terraform workflows. Each major directory (`apps` and `infra`) includes its own Taskfile, while a root Taskfile is also available to coordinate commands across both layers.

### Available Tasks

**Apps Tasks:**

- `apps:init`: Prepare your working directory for app-level commands.
- `apps:validate`: Validate the app configuration.
- `apps:plan`: Generate an execution plan for app deployments.
- `apps:apply`: Create or update app infrastructure.
- `apps:destroy`: Tear down the app infrastructure.
- `apps:format`: Reformat app configuration files.
- `apps:scale-runners`: Scale Gitea action runners (0-10).
- `apps:secrets`: Display bootstrap/admin credentials for a specified app.

**Infra Tasks:**

- `infra:init`: Prepare your working directory for infrastructure commands.
- `infra:validate`: Validate the infrastructure configuration.
- `infra:plan`: Generate an execution plan for infrastructure changes.
- `infra:apply`: Create or update the infrastructure.
- `infra:destroy`: Tear down the infrastructure.
- `infra:format`: Reformat infrastructure configuration files.
- `infra:ssh`: Generate an SSH key and connect to a specified node (VPN or DNS).
- `infra:kubeconfig`: Generate a kubeconfig file.
- `infra:talosconfig`: Generate a Talos configuration file.
- `infra:kubeseal`: Generate a kubeseal certificate.
- `infra:wireguard`: Generate a WireGuard client configuration.

For more details on Taskfile, visit the [Taskfile GitHub repository](https://github.com/go-task/task).

## Configuration

Before deploying the homelab, you must set up several user variables. These can be defined in a `.env` file or directly in your Terraform variable files.

### Infrastructure Variables

Key variables for the **infra** layer include:

- **Proxmox & Cluster Settings:**
  - `proxmox_endpoint`: Proxmox host endpoint.
  - `proxmox_primary_node`: Proxmox primary node name.
  - `proxmox_secondary_node`: Proxmox secondary node name.
  - `cluster_name`: Name of the Kubernetes cluster.
  - `cluster_ip_range`: Range of IPs available for cluster VMs in CIDR format.  
    *Note:* This range must have enough usable IPs to cover all Talos nodes and additional services.
  - `cluster_node_network`: The IP network of the cluster nodes (default: `192.168.1.1/24`).
  - `cluster_network_gateway`: Gateway for the cluster nodes (default: `192.168.1.1`).

- **DNS & Certificate Management:**
  - `base_domain`: Base domain for serving the cluster (must be a valid domain name or an empty string).
  - `acme_email`: Email to use for ACME registration.
  - `acme_server`: ACME server URL for certificate issuance (default: `https://acme-staging-v02.api.letsencrypt.org/directory`).

- **Kubernetes & Talos Settings:**
  - `talos_version`: Version of Talos to deploy (default: `v1.9.2`).
  - `k8s_version`: Version of Kubernetes to deploy (default: `1.32`).
  - `talos_extensions`: Map of Talos extension names to versions (e.g., `"intel-ucode": "20241112"`, `"iscsi-tools": "v0.1.6"`, `"qemu-guest-agent": "9.2.0"`).
  - `talos_vm_config`: Configuration for Talos control and worker VMs (includes CPU, memory, disk, and network settings).

- **VPN & DNS VM Configurations:**
  - `ubuntu_version`: Version of Ubuntu to deploy for the VPN VM (default: `"noble"`).
  - `vpn_vm_config`: Configuration for VPN node VMs.
  - `dns_vm_config`: Configuration for DNS node VMs.

- **Environment:**
  - `environment`: Environment name (e.g., `dev`, `staging`, `prod`).

### Apps Variables

Key variables for the **apps** layer include:

- `base_domain`: Base domain for serving the cluster.
- `k8s_version`: Version of Kubernetes to deploy.
- `kubeconfig`: Path to your kubeconfig file (default: `~/.kube/config`; the file must exist).
- `cluster_cert_issuer`: The Kubernetes cert-manager cluster issuer to use for certificate challenges.

## AWS Integration

This homelab configuration integrates with AWS for two key purposes:

- **Terraform Backend:**
  An AWS S3 bucket is used to securely store Terraform state files. Configure your AWS S3 backend settings in your Terraform configuration or via environment variables.
  
- **Route53 for DNS:**
  Cert-manager leverages AWS Route53 to perform DNS challenges and update DNS records automatically. Ensure you provide the necessary AWS IAM credentials and the Route53 hosted zone ID in your configuration.

## Getting Started

1. **Clone the Repository:**

   ```sh
   git clone https://github.com/yourusername/homelab.git
   cd homelab
   ```

2. Create a .env file (or configure variables directly) with the required parameters:

```
PROXMOX_VE_USERNAME="root@pam"
PROXMOX_VE_PASSWORD=""
```

3. Install `terraform` or `tofu` (please configure `TF` variable in `Taskfile.yaml` accordingly)
4. Setup `terraform` environment:

```
task infra:init
task apps:init
```

5. Deploy:

```
task infra:apply
task infra:kubeconfig symlink=true
task apps:apply

```
