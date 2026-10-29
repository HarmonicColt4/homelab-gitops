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
    datastore_id = "local-zfs"
  }

  dynamic "disk" {
    for_each = var.disks
    content {
      datastore_id = "local-zfs"
      import_from  = disk.key == 0 ? proxmox_download_file.talos_linux_cloud_image.id : null
      interface    = "scsi${disk.key}"
      discard      = "on"
      size         = disk.value.size
      ssd          = true
    }
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