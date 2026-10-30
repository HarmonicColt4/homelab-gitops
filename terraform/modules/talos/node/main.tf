locals {
  # Common patches applied to every node, in order.
  common_patch_files = [
    for patch in var.common_patches : abspath("${var.patches_dir}/${patch}")
  ]

  # Extra patches applied only to control plane nodes.
  controlplane_patch_files = var.machine_type == "controlplane" ? [
    for patch in var.controlplane_patches : abspath("${var.patches_dir}/${patch}")
  ] : []

  # Per-node patch, e.g. <patches_dir>/<node_name>.yml
  node_patch_file = abspath("${var.patches_dir}/${var.node_name}.yml")

  # Final ordered patch list: common -> control-plane-only -> per-node.
  patch_files = concat(
    local.common_patch_files,
    local.controlplane_patch_files,
    [local.node_patch_file],
  )

  config_patches = [for patch_file in local.patch_files : file(patch_file)]
}

# Generate the node machine configuration by layering the patch files on top of
# the base config produced from the cluster secrets.
data "talos_machine_configuration" "this" {
  cluster_name     = var.cluster_name
  cluster_endpoint = var.cluster_endpoint
  machine_type     = var.machine_type
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version
  config_patches   = local.config_patches
}

# Apply the generated configuration to the node.
resource "talos_machine_configuration_apply" "this" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this.machine_configuration
  node                        = var.node
  endpoint                    = var.node
}

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

import {
  to = talos_machine_secrets.this
  id = var.talos_secrets_file
}
