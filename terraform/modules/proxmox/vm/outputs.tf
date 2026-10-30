output "ipv4_addresses" {
  value       = proxmox_virtual_environment_vm.talos_linux_vm.ipv4_addresses
  description = "IPv4 addresses reported by the QEMU guest agent, per network device"
}
