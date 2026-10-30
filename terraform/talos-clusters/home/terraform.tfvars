talos_version = "v1.14.2"

# Schematic (extensions) YAML, relative to the cluster root.
talos_schematic_file = "../../../talos/clusters/home/extensions/beast.yml"

# Cluster identity and node being configured.
cluster_name     = "teamg"
cluster_endpoint = "https://k8s.home.arpa:6443"
node_name        = "beast"
machine_type     = "worker"

# Talos machine config patches (per-node and common).
patches_dir = "../../../talos/clusters/home/patches"

# Unencrypted secrets sources (gitignored). Decrypt the SOPS secrets first:
#   sops -d ../../../talos/clusters/home/secrets.enc.yml > ../../../talos/clusters/home/secrets.yml
talos_secrets_file = "../../../talos/clusters/home/secrets.yml"

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

# Proxmox PCI resource-mapping names to pass through (e.g. ["gpu"]).
# Empty list attaches no host PCI devices.
pcie_devices = ["gpu"]