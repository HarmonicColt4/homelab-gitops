# Talos Cluster Information

Two control plane nodes with workers enabled:

- hedy
- rpi5

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

## Kubernetes upgrade

Keep every control plane node on the same Kubernetes minor version. Upgrade with:

```
talosctl upgrade-k8s --to <version>
```

> **Warning:** A mixed-version control plane breaks components that watch APIs only served
> by the newer version. For example, the v1.37 kube-scheduler watches `DeviceTaintRule`
> (`resource.k8s.io/v1`), which a v1.36 API server does not serve. Because the scheduler
> reaches the API through the shared endpoint (KubePrism/VIP), it can land on the older
> API server, the informer never syncs, and the scheduler stays unready (`/readyz` 500).
