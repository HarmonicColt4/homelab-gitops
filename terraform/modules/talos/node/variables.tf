variable "cluster_name" {
  type        = string
  description = "Talos cluster name"
}

variable "cluster_endpoint" {
  type        = string
  description = "Talos cluster endpoint, e.g. https://k8s.home.arpa:6443"
}

variable "machine_type" {
  type        = string
  description = "Talos machine type: controlplane or worker"

  validation {
    condition     = contains(["controlplane", "worker"], var.machine_type)
    error_message = "machine_type must be either \"controlplane\" or \"worker\"."
  }
}

variable "talos_secrets_file" {
  type        = string
  description = "Path to the unencrypted Talos secrets YAML (output of `talosctl gen secrets`)"
  sensitive   = true
}

variable "talos_version" {
  type        = string
  description = "Talos Linux version"
}

variable "node" {
  type        = string
  description = "Node address (IP or hostname) the configuration is applied to"
}

variable "patches_dir" {
  type        = string
  description = "Directory containing the Talos machine config patches (per-node and common)"
}

variable "node_name" {
  type        = string
  description = "Node name; selects <patches_dir>/<node_name>.yml as the per-node patch"
}

variable "common_patches" {
  type        = list(string)
  default     = ["common/metrics.yml"]
  description = "Patch files, relative to patches_dir, applied to every node in order"
}

variable "controlplane_patches" {
  type        = list(string)
  default     = ["common/allow-cp-worker.yml"]
  description = "Patch files, relative to patches_dir, applied only to control plane nodes"
}