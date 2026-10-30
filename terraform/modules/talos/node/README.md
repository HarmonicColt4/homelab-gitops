# Talos node module

Generates and applies a Talos machine configuration for a single node, layering
the patch files from a cluster's `patches` directory on top of the base config
derived from the cluster secrets.

## Patch ordering

Patches are applied in this order (later patches win):

1. `common_patches` — applied to every node (default: `common/metrics.yml`).
2. `controlplane_patches` — applied only when `machine_type = "controlplane"`
   (default: `common/allow-cp-worker.yml`).
3. `<node_name>.yml` — the per-node patch.

This mirrors the manual workflow documented in
[`talos/clusters/home/README.md`](../../../../talos/clusters/home/README.md).

> **Warning:** `common/allow-cp-worker.yml` removes the control-plane
> `NoSchedule` taint. It is applied **only** to control plane nodes and never to
> a worker.

## Usage

```hcl
module "talos_node" {
  source = "../../modules/talos/node"

  cluster_name       = "teamg"
  cluster_endpoint   = "https://k8s.home.arpa:6443"
  machine_type       = "controlplane"
  talos_secrets_file = "${path.root}/../../../talos/clusters/home/secrets.yml"
  talos_version      = "v1.14.2"

  node        = "10.25.25.10"
  node_name   = "beast"
  patches_dir = "${path.root}/../../../talos/clusters/home/patches"
}
```

## Inputs

| Name                   | Description                                 | Type           | Default                          | Required |
| ---------------------- | ------------------------------------------- | -------------- | -------------------------------- | :------: |
| `cluster_name`         | Talos cluster name                          | `string`       | n/a                              |   yes    |
| `cluster_endpoint`     | Talos cluster endpoint                      | `string`       | n/a                              |   yes    |
| `machine_type`         | `controlplane` or `worker`                  | `string`       | n/a                              |   yes    |
| `talos_secrets_file`   | Path to the unencrypted Talos secrets YAML  | `string`       | n/a                              |   yes    |
| `talos_version`        | Talos Linux version                         | `string`       | n/a                              |   yes    |
| `node`                 | Node address to apply to                    | `string`       | n/a                              |   yes    |
| `patches_dir`          | Directory containing the patches            | `string`       | n/a                              |   yes    |
| `node_name`            | Selects `<patches_dir>/<node_name>.yml`     | `string`       | n/a                              |   yes    |
| `common_patches`       | Patches applied to every node               | `list(string)` | `["common/metrics.yml"]`         |    no    |
| `controlplane_patches` | Patches applied only to control plane nodes | `list(string)` | `["common/allow-cp-worker.yml"]` |    no    |

## Outputs

| Name                         | Description                                          |
| ---------------------------- | ---------------------------------------------------- |
| `machine_configuration`      | Generated, patched machine configuration (sensitive) |
| `machine_configuration_hash` | Hash of the applied machine configuration            |
| `patch_files`                | Ordered list of patch files applied to the node      |
