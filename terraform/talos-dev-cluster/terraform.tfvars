talos_version           = "v1.14.2"
talos_system_extensions = ["qemu-guest-agent", "siderolabs/iscsi-tools", "util-linux-tools"]

# First entry is the boot disk (imported from the Talos cloud image).
# Add further entries for extra data disks; `interface` defaults to scsi<index>.
disks = [
  {
    size = 100
  },
  {
    size = 300
  }
]