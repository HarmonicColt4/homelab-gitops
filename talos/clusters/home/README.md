# Talos Cluster Information

One control plane node and two worker nodes:

- `rpi5` — control plane
- `hedy` — worker
- `beast` — worker

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

The control plane patch set is [`patches/common/metrics.yml`](patches/common/metrics.yml),
[`patches/cilium.yml`](patches/cilium.yml) and
[`patches/common/allow-cp-worker.yml`](patches/common/allow-cp-worker.yml), then the per-node patch.

```
talosctl machineconfig patch configs/controlplane.yaml --patch @patches/common/metrics.yml --patch @patches/cilium.yml --patch @patches/common/allow-cp-worker.yml --patch @patches/<node>.yml --output configs/<node>.yml
```

> **Warning:** [`patches/common/allow-cp-worker.yml`](patches/common/allow-cp-worker.yml) removes the
> control-plane `NoSchedule` taint so the control plane can also run workloads. Apply it **only** to
> control plane nodes (currently `rpi5`) — **never** to a worker node. A worker must not carry the
> control-plane role.

## Worker

The worker patch set is [`patches/common/metrics.yml`](patches/common/metrics.yml), then the per-node patch.
It does **not** include `allow-cp-worker.yml` or `cilium.yml` (both are control-plane-only).

```
talosctl machineconfig patch configs/worker.yaml --patch @patches/common/metrics.yml --patch @patches/<node>.yml --output configs/<node>.yml
```

For `hedy` specifically:

```
talosctl machineconfig patch configs/worker.yaml --patch @patches/common/metrics.yml --patch @patches/hedy.yml --output configs/hedy.yml
```

For `beast` specifically:

```
talosctl machineconfig patch configs/worker.yaml --patch @patches/common/metrics.yml --patch @patches/beast.yml --output configs/beast.yml
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

## Historical: hedy migration

`hedy` was migrated from control plane to worker. The current state is a single control plane
(`rpi5`) with workers `hedy` and `beast`. The old migration steps are no longer applicable.

## Migrating to Cilium (kube-proxy replacement)

The cluster runs Cilium as its CNI with kube-proxy replacement. The default Talos
CNI (flannel) and kube-proxy are disabled by
[`patches/cilium.yml`](patches/cilium.yml).

`KubeFlannelCNIConfig` and `KubeProxyConfig` are cluster-level documents that
only exist in the **control plane** machine config, so this patch is applied to
the control plane (`rpi5`) only — **never** to a worker. Workers need no CNI
change: disabling flannel/kube-proxy on the control plane removes the
`kube-flannel` and `kube-proxy` DaemonSets cluster-wide.

Cilium itself is deployed by Flux from
[`fluxcd/infrastructure/controllers/cilium`](../../../fluxcd/infrastructure/controllers/cilium).

> **Warning:** This is a disruptive, scheduled-maintenance operation. Removing
> flannel and kube-proxy before Cilium is running causes a short cluster-wide
> network outage. `rpi5` is the only control-plane/etcd member, so rebooting it
> also takes the control plane down.

Cutover order:

1. Apply the updated control plane machine config to `rpi5` (the manual
   `talosctl machineconfig patch` workflow above, including `patches/cilium.yml`).
   Workers (`hedy`, `beast`) need no change.
2. Merge the Cilium manifests so Flux installs Cilium (or `kubectl apply` the
   rendered manifest) immediately after the config change.
3. Restart workloads so pods obtain Cilium IPs.
4. Validate: `cilium status`, `cilium connectivity test`, `kubectl get nodes`,
   DNS, Traefik ingress, Longhorn and CNPG health.
5. **Take over LoadBalancer IPs with Cilium.** Cilium now owns the LB IP pool
   ([`fluxcd/infrastructure/configs/cilium-lb.yml`](../../../fluxcd/infrastructure/configs/cilium-lb.yml))
   and announces the VIPs over L2 (`l2announcements.enabled` in the Cilium
   HelmRelease). Every LoadBalancer Service has been re-annotated from
   `metallb.io/loadBalancerIPs` / `metallb.io/allow-shared-ip` to
   `lbipam.cilium.io/ips` / `lbipam.cilium.io/sharing-key`. Confirm each VIP is
   assigned and reachable (`kubectl get svc -A`, `cilium status`).
6. **Remove MetalLB.** Once Cilium is announcing every VIP, delete the MetalLB
   controller manifests and the `IPAddressPool`/`L2Advertisement` config. The
   MetalLB entries have already been dropped from the Flux kustomizations, so
   the remaining step is to delete the live MetalLB resources (and the
   `metallb-system` namespace) from the cluster.

> **Warning — the LB swap must be atomic.** MetalLB's speaker and Cilium's L2
> announcer must **never** ARP for the same VIP at the same time. If both are
> active for a given address, the two nodes answer ARP for the same IP and
> traffic is black-holed or flapped. Perform the annotation swap and the MetalLB
> teardown in a single maintenance window: re-annotate the Services and let
> Cilium claim the IPs, then immediately remove MetalLB before it re-claims
> them. Do not leave both controllers running against the same pool.

Rollback: revert the control plane machine config (re-enable flannel +
kube-proxy) and remove the Cilium manifests, then restart workloads. This
requires a second disruption window, so keep the pre-change config ready.
