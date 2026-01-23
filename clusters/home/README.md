# Talos Cluster Information

Three talos control plane nodes with workers enabled:

- nuc11
- talos-pve
- talos-truenas

**Endpoint**: `k8s.home.arpa`

```
export ENDPOINT="k8s.home.arpa"
```

**Cluster Name**: `teamg`

```
export CLUSTER_NAME="teamg"
```

```
talosctl gen config --with-secrets secrets.yml $CLUSTER_NAME https://$ENDPOINT:6443 --output configs -t controlplane -t talosconfig --with-docs=0 --with-examples=0 -f --install-image factory.talos.dev/metal-installer/<schematic>:<version>
```

```
talosctl machineconfig patch configs/controlplane.yaml --patch @patches/common.yml --patch @patches/<node>.yml --output configs/<node>.yml
```

```
talosctl apply-config --insecure \
    --nodes <node> \
    --file configs/<node>.yml
```

```
curl -X POST \
  --data-binary @extensions.yml \
  https://factory.talos.dev/schematics
```

```
talosctl upgrade \
  --image \
  factory.talos.dev/metal-installer/613e1592b2da41ae5e265e8789429f22e121aab91cb4deb6bc3c0b6262961245:v1.12.1
```
