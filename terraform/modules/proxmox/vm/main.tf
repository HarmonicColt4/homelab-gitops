resource "proxmox_download_file" "talos_linux_cloud_image" {
  content_type = "import"
  datastore_id = "local"
  node_name    = var.node_name
  url          = var.cloud_image_url
}

resource "proxmox_virtual_environment_vm" "talos_linux_vm" {
  name        = "talos-linux-vm"
  description = "Talos Linux VM managed by Terraform"
  tags        = ["terraform", "talos"]

  node_name = var.node_name

  machine = "q35"
  bios    = "ovmf"
  agent {
    enabled = true
  }

  cpu {
    cores = var.num_cpu_cores
    type  = "host"
  }

  efi_disk {
    datastore_id = var.datastore_id
  }

  disk {
    datastore_id = var.datastore_id
    import_from  = proxmox_download_file.talos_linux_cloud_image.id
    interface    = "scsi0"
    discard      = "on"
    size         = var.num_disk_size_gb
    ssd          = true
  }

  # hostpci {
  #   device  = "hostpci0"
  #   mapping = "gpu"
  #   pcie    = true
  #   rombar  = true
  # }

  memory {
    dedicated = var.num_memory_mib
    floating  = var.num_memory_mib
  }

  network_device {
    bridge = "vmbr25"
  }

  on_boot = true

  operating_system {
    type = "l26"
  }
}