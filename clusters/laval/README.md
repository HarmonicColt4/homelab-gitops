# Talos Cluster Information

Three talos control plane nodes with workers enabled:

- talos-1
- talos-2
- talos-3

**Endpoint**: `192.168.6.2`

```
export ENDPOINT="192.168.6.2"
```

**Cluster Name**: `talos-cluster-penda`

```
export CLUSTER_NAME="talos-cluster-penda"
```

```
talosctl gen config --with-secrets secrets.yml $CLUSTER_NAME https://$ENDPOINT:6443 --output configs -t controlplane -t talosconfig --with-docs=0 --with-examples=0 -f
```

```
talosctl machineconfig patch configs/controlplane.yaml --patch @patches/common.yml --patch @patches/talos-1.yml --output configs/talos-1.yml
```

```
talosctl apply-config --insecure \
    --nodes 192.168.1.110 \
    --file configs/talos-1.yml
```
