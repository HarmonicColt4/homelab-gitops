# Talos Cluster Information

Three talos control plane nodes with workers enabled:

- talos-1
- talos-2
- talos-3

**Endpoint**: `192.168.6.9`

```
export ENDPOINT="192.168.6.9"
```

**Cluster Name**: `talos-cluster-penda`

```
export CLUSTER_NAME="talos-cluster-penda"
```

```
talosctl gen config --with-secrets secrets.yml $CLUSTER_NAME https://$ENDPOINT:6443 --output configs -t controlplane -t talosconfig --with-docs=0 --with-examples=0 -f
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

## Cilium

```
helm install \
    cilium \
    cilium/cilium \
    --version 1.18.6 \
    --namespace kube-system \
    --set ipam.mode=kubernetes \
    --set kubeProxyReplacement=true \
    --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --set cgroup.autoMount.enabled=false \
    --set cgroup.hostRoot=/sys/fs/cgroup \
    --set k8sServiceHost=localhost \
    --set k8sServicePort=7445 \
    --set=gatewayAPI.enabled=true \
    --set=gatewayAPI.enableAlpn=true \
    --set=gatewayAPI.enableAppProtocol=true
```
