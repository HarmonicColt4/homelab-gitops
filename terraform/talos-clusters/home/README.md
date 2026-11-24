# Talos cluster — home

Terraform root module that provisions the Talos Linux VM for the `home` cluster on Proxmox VE.

> **Legacy:** Proxmox VE is no longer in use. `beast` runs Talos Linux bare metal and is
> installed/applied with the manual `talosctl` workflow in
> [`talos/clusters/home/README.md`](../../../talos/clusters/home/README.md). This root module and
> [`modules/proxmox/vm`](../../modules/proxmox/vm) are kept for reference only; the
> [`modules/talos/node`](../../modules/talos/node) module still applies machine config to any node
> address.

## Prerequisites

- Terraform `1.17.2`
- A `garage` AWS profile for the S3 state backend (see [`version.tf`](version.tf))
- Proxmox VE API credentials (see below)

## Proxmox provider configuration

The `bpg/proxmox` provider is intentionally **not** configured in code — credentials are injected
via environment variables so no secrets are committed. Export them before running Terraform:

```sh
# API endpoint (Proxmox VE web UI)
export PROXMOX_VE_ENDPOINT="https://pve.home.arpa:8006/"

# API token (preferred) — format: user@realm!token-id=secret
export PROXMOX_VE_API_TOKEN="terraform@pve!provider=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Accept self-signed certificates (homelab)
export PROXMOX_VE_INSECURE="true"
```

Alternatively, authenticate with a username and password:

```sh
export PROXMOX_VE_USERNAME="terraform@pve"
export PROXMOX_VE_PASSWORD="..."
```

Some operations (for example file uploads) use SSH; if required, also set:

```sh
export PROXMOX_VE_SSH_USERNAME="root"
export PROXMOX_VE_SSH_PRIVATE_KEY="$(cat ~/.ssh/id_ed25519)"
```

> Never commit these values. Use a secret manager or your shell's environment.

## State backend

State is stored in the Garage S3 bucket `terraform` under `talos-clusters/home/terraform.state`,
using the `garage` profile from `~/.aws/config` and `~/.aws/credentials`.

## Usage

```sh
terraform init
terraform plan
terraform apply
```

## Variables

| Name                   | Description                                                                                |
| ---------------------- | ------------------------------------------------------------------------------------------ |
| `talos_version`        | Talos Linux version                                                                        |
| `talos_schematic_file` | Path to the Talos Image Factory schematic (extensions) YAML file, relative to cluster root |
| `disks`                | Ordered disks; the first is the boot disk imported from the cloud image                    |
