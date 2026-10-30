module "talos_linux_schematic" {
  source               = "../../modules/talos/schematic"
  talos_version        = var.talos_version
  talos_schematic_file = "${path.root}/${var.talos_schematic_file}"
}

module "talos_linux_vm" {
  source          = "../../modules/proxmox/vm"
  cloud_image_url = module.talos_linux_schematic.talos_disk_image_url
  num_cpu_cores   = 4
  num_memory_mib  = 16384
  disks           = var.disks
  pcie_devices    = var.pcie_devices
}

module "talos_node" {
  source = "../../modules/talos/node"

  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = var.machine_type
  talos_secrets_file = var.talos_secrets_file
  talos_version      = var.talos_version
  # Node management IP: the guest-agent-reported IPv4 address within the
  # management network prefix. This excludes loopback, link-local (169.254.0.0/16)
  # and Kubernetes pod IPs, which the guest agent also reports.
  node = one([
    for addr in flatten(module.talos_linux_vm.ipv4_addresses) :
    addr if startswith(addr, var.node_network_prefix)
  ])
  patches_dir = var.patches_dir
  node_name   = var.node_name
}
