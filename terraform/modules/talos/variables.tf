variable "talos_version" {
  type        = string
  description = "Talos Linux version"
}

variable "talos_schematic_file" {
  type        = string
  description = "Path to the Talos Image Factory schematic YAML file describing system extensions and other customizations"
}