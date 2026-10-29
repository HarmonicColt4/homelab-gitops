module "talos_linux" {
  source               = "../../modules/talos"
  talos_version        = var.talos_version
  talos_schematic_file = "${path.root}/${var.talos_schematic_file}"
}

module "talos_linux_vm" {
  source          = "../../modules/proxmox/vm"
  cloud_image_url = module.talos_linux.talos_disk_image_url
  num_cpu_cores   = 4
  num_memory_mib  = 16384
  disks           = var.disks
}