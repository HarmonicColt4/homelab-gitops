variable "node_name" {
  type        = string
  default     = "pve"
  description = "Proxmox VE node name"
}

variable "datastore_id" {
  type        = string
  description = "Proxmox VE datastore name"
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

variable "num_disk_size_gb" {
  type = number
}