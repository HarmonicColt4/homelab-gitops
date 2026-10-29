talos_version = "v1.14.2"

# Schematic (extensions) YAML, relative to the cluster root.
talos_schematic_file = "../../../talos/clusters/home/extensions/beast.yml"

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