variable "talos_version" {
  type        = string
  description = "Talos Linux version"
}

variable "talos_system_extensions" {
  type        = list(string)
  description = "Talos Linux system extensions"
}