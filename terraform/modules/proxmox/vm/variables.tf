variable "node_name" {
  type        = string
  default     = "pve"
  description = "Proxmox VE node name"
}

variable "cloud_image_url" {
  type        = string
  description = "URL for VM cloud image"
}

variable "num_cpu_cores" {
  type = number
}

variable "num_memory_mib" {
  type = number
}

variable "disks" {
  description = <<-EOT
    Ordered list of disks to attach to the VM. The first entry is used as the
    boot disk and is imported from the cloud image; any additional entries are
    attached as extra data disks. Interfaces are assigned as `scsi<index>`
    (scsi0, scsi1, ...).
  EOT
  type = list(object({
    size = number
  }))

  validation {
    condition     = length(var.disks) > 0
    error_message = "At least one disk must be provided."
  }
}