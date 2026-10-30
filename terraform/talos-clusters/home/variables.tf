variable "talos_version" {
  type        = string
  description = "Talos Linux version"
}

variable "talos_schematic_file" {
  type        = string
  description = "Path to the Talos Image Factory schematic (extensions) YAML file, relative to the cluster root"
  default     = "../../../talos/clusters/home/extensions/nuc11.yml"
}

variable "disks" {
  description = <<-EOT
    Ordered list of disks to attach to the VM. The first entry is the boot disk
    imported from the Talos cloud image; additional entries are extra data disks.
    Interfaces are assigned as `scsi<index>` (scsi0, scsi1, ...).
  EOT
  type = list(object({
    size = number
  }))
}

variable "cluster_name" {
  type        = string
  description = "Talos cluster name"
  default     = "teamg"
}

variable "cluster_endpoint" {
  type        = string
  description = "Talos cluster endpoint"
  default     = "https://k8s.home.arpa:6443"
}

variable "node_name" {
  type        = string
  description = "Node name; selects <patches_dir>/<node_name>.yml as the per-node patch"
  default     = "beast"
}

variable "machine_type" {
  type        = string
  description = "Talos machine type: controlplane or worker"
  default     = "worker"
}

variable "patches_dir" {
  type        = string
  description = "Directory containing the Talos machine config patches"
  default     = "../../../talos/clusters/home/patches"
}

variable "talos_secrets_file" {
  type        = string
  description = "Path to the unencrypted Talos secrets YAML (output of `talosctl gen secrets`)"
  default     = "../../../talos/clusters/home/secrets.yml"
}

variable "node_network_prefix" {
  type        = string
  description = "IPv4 address prefix of the node management network; used to select the node IP from the VM's guest-agent-reported addresses"
  default     = "10.25.25"
}

variable "pcie_devices" {
  description = <<-EOT
    List of Proxmox PCI resource-mapping names to pass through to the VM
    (e.g. ["gpu"]). Each entry is attached as a `hostpci<index>` device with
    PCIe and ROM BAR enabled. Leave empty to attach no host PCI devices.
  EOT
  type        = list(string)
  default     = []
}
