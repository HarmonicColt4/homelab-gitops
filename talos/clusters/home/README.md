# Talos Cluster Information

Single talos control plane node with workers enabled:

- hedy

**Endpoint**: `k8s.home.arpa`
**Cluster Name**: `teamg`

```
export ENDPOINT="k8s.home.arpa"
export CLUSTER_NAME="teamg"
```

## Get schematic

```
curl -X POST --data-binary @extensions.yml https://factory.talos.dev/schematics
```

## Config

```
talosctl gen config --with-secrets secrets.yml $CLUSTER_NAME https://$ENDPOINT:6443 --output configs --with-docs=0 --with-examples=0 -f
```

## Control Plane

```
talosctl machineconfig patch configs/controlplane.yaml --patch @patches/common-cp.yml --patch @patches/<node>.yml --output configs/<node>.yml
```

## Worker

```
talosctl machineconfig patch configs/worker.yaml --patch @patches/common-worker.yml --patch @patches/<node>.yml --output configs/<node>.yml
```

## Apply Configs

```
talosctl apply-config --insecure --nodes <node> --file configs/<node>.yml
```

## Talos upgrade

```
talosctl upgrade --image factory.talos.dev/metal-installer/613e1592b2da41ae5e265e8789429f22e121aab91cb4deb6bc3c0b6262961245:v1.12.1
```
