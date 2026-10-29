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