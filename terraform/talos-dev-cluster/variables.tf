variable "talos_version" {
  type        = string
  description = "Talos Linux version"
}

variable "talos_system_extensions" {
  type        = list(string)
  description = "Talos Linux system extensions"
}

variable "node_name" {
  type        = string
  default     = "pve"
  description = "Proxmox VE node name"
}

variable "datastore_id" {
  type        = string
  description = "Proxmox VE datastore name"
}