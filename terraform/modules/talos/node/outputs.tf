output "machine_configuration" {
  value       = data.talos_machine_configuration.this.machine_configuration
  description = "Generated, patched Talos machine configuration for the node"
  sensitive   = true
}

output "machine_configuration_hash" {
  value       = talos_machine_configuration_apply.this.machine_configuration_hash
  description = "Hash of the machine configuration applied to the node"
}

output "patch_files" {
  value       = local.patch_files
  description = "Ordered list of patch files applied to the node"
}
