variable "talos_version" {
  type        = string
  description = "Talos Linux version"
}

variable "talos_system_extensions" {
  type        = list(string)
  description = "Talos Linux system extensions"
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