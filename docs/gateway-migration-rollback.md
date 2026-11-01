# Gateway API Migration — Rollback Procedure & Incident Record

Status: **ROLLED BACK** to pre-Gateway-migration state (`50606ef5`).
Last updated: 2026-11-01.

This document covers (a) how to roll back the Traefik → Cilium Gateway API
migration, and (b) the record of the rollback that was actually performed.

---

## 1. Key references

| Item                         | Value                                                                                                               |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| Migration commit             | `91480c66114c70096f42ace757aea6dedc892e44` (_feat(ingress): migrate Traefik IngressRoute to Cilium Gateway API_)    |
| Pre-migration tag            | `pre-gateway-migration-20261101-153650` → commit `50606ef5`                                                         |
| Pre-migration backup branch  | `backup/pre-gateway-migration`                                                                                      |
| Forward-fix safety branch    | `backup/gateway-forwardfix-20261101` → commit `840b50bf`                                                            |
| Rollback backups (host /tmp) | `/tmp/ingressroutes-backup.yaml`, `/tmp/traefik-backup.yaml`, `/tmp/gatewayapi-backup.yaml`, `/tmp/crds-backup.txt` |
| Traefik VIP                  | `10.25.25.11`                                                                                                       |
| TrueNAS standalone CEC VIP   | `10.25.25.12`                                                                                                       |

`840b50bf` is the _forward-fix_ attempt (vendored `CiliumEnvoyConfig` CRD). It
is preserved on `backup/gateway-forwardfix-20261101` for a future retry; it is
**not** part of `main` after the rollback.

---

## 2. Rollback procedure

Choose **one** of the two methods below. Both return the tree to the exact
pre-migration state.

### 2.1 Method A — reset to the pre-migration tag (history rewrite)

```sh
git fetch --tags origin
git reset --hard pre-gateway-migration-20261101-153650
git push --force-with-lease origin main
```

### 2.2 Method B — revert the migration commit (preserves history)

```sh
git revert --no-edit 91480c66114c70096f42ace757aea6dedc892e44
git push origin main
```

> If the forward-fix commit `840b50bf` is also on `main`, revert it first:
> `git revert --no-edit 840b50bf 91480c66`.

### 2.3 Re-reconcile Flux

```sh
NOW=$(date +%s)
kubectl -n flux-system annotate gitrepository/flux-system \
  reconcile.fluxcd.io/requestedAt="$NOW" --overwrite
for ks in infra-controllers infra-configs apps truecharts-apps infra-iam; do
  kubectl -n flux-system annotate kustomization/$ks \
    reconcile.fluxcd.io/requestedAt="$NOW" --overwrite
done
```

### 2.4 Manual cleanup / restoration (only if Flux data was lost)

- **Restore IngressRoutes** — they are Git-managed under
  `fluxcd/infrastructure/configs/traefik/ingress-routes/` and per-app
  `ingress-route.yml` files. If needed, re-apply from
  `/tmp/ingressroutes-backup.yaml`.
- **Restore Traefik** — manifests still exist in the repo at
  `fluxcd/infrastructure/controllers/traefik/` and
  `fluxcd/infrastructure/configs/traefik/`. Ensure **both** are re-added to
  `fluxcd/infrastructure/controllers/kustomization.yml` and
  `fluxcd/infrastructure/configs/kustomization.yml` respectively.
- **Restore DNS** — if DNS was cut over, revert the records (see §5).

### 2.5 VIP `10.25.25.11` conflict note

`10.25.25.11` is claimed by exactly one object at a time:

- **Migration state**: the Cilium Gateway's generated LoadBalancer Service.
- **Rollback state**: the Traefik `LoadBalancer` Service in namespace `traefik`.

If both try to claim it, LB-IPAM marks the pool `CONFLICTING` and one Service
stays `<pending>`. Confirm only one owner before/after a switch:

```sh
kubectl get svc -A | grep -E '10\.25\.25\.11|10\.25\.25\.12'
kubectl get ciliumloadbalancerippool ip-pool \
  -o jsonpath='{.status.conditions}' ; echo
```

---

## 3. Rollback actually performed (2026-11-01)

Trigger: the forward-fix deployed the CEC CRD successfully, but the operator
elected to abort and return to Traefik immediately ("rollback to pre gateway
now").

Executed:

1. Preserved forward-fix work:
   `git branch backup/gateway-forwardfix-20261101 840b50bf` and pushed it.
2. `git reset --hard pre-gateway-migration-20261101-153650` → `50606ef5`.
3. `git push --force-with-lease origin main` → `+ 840b50bf...50606ef5 main
-> main (forced update)`.
4. Re-annotated `gitrepository/flux-system`, `kustomization/infra-controllers`,
   `infra-configs`, `apps`, `truecharts-apps`, `infra-iam`.
5. Unblocked a stuck namespace (see §4), then re-annotated `infra-controllers`
   and `infra-configs`.

Result:

- All Flux Kustomizations `Ready=True` at revision `50606ef5`.
- Traefik HelmRelease `Ready=True` (`traefik@42.2.0`), 3/3 pods Running.
- `Service/traefik` EXTERNAL-IP `10.25.25.11` (ports 80/443).
- 30 `IngressRoute` objects present (served by Traefik).
- `Namespace/gateway` pruned; `CiliumEnvoyConfig` CRD and Gateway API CRDs
  pruned; `cilium-config` `enable-envoy-api`/`enable-gateway-api` reverted.
- 10 standard `*.cilium.io` CRDs remain (unchanged, pre-existing).

---

## 4. Known gotcha — `traefik` namespace stuck `Terminating`

When the migration pruned Traefik, `Namespace/traefik` wedged in `Terminating`
because two **orphaned Services** (`pikvm`, `truenas-penda`) carried a
`tailscale.com/finalizer` from a Tailscale operator that was no longer running.
The namespace could not finalize, so the rollback could not recreate it
(`timeout waiting for: [Namespace/traefik status: 'Terminating']`).

Fix (targeted, safe — these Services are _not_ in the desired Git state):

```sh
kubectl -n traefik patch svc pikvm        --type=merge -p '{"metadata":{"finalizers":null}}'
kubectl -n traefik patch svc truenas-penda --type=merge -p '{"metadata":{"finalizers":null}}'
```

The namespace then terminated and Flux recreated it. If this recurs, inspect
`kubectl get ns traefik -o json` → `.status.conditions` (look for
`NamespaceFinalizersRemaining`).

---

## 5. DNS

DNS for `teamg.app` is Cloudflare-managed (cert-manager ClusterIssuer uses
Cloudflare DNS-01; the `cloudflareddns` app exists). Credentials are
SOPS-encrypted and were **not** available in plaintext, so **no DNS changes
were made** at any point; no previous values needed restoring.

If a future migration cuts DNS over, the intended targets were:

- `garage.teamg.app`, `git.teamg.app`, `jellyfin.teamg.app`,
  `cloud.teamg.app`, `qbit.teamg.app` → `10.25.25.12`
- all other `*.teamg.app` and apex `teamg.app` → `10.25.25.11`

Record the prior values before changing them.

---

## 6. Why the forward-fix was attempted (for the future retry)

`infra-configs` failed with
`no matches for kind "CiliumEnvoyConfig" in version "cilium.io/v2"` — the
`ciliumenvoyconfigs.cilium.io` CRD was never installed.

Root cause: **the Cilium 1.20.4 Helm chart ships no CRDs at all** (its package
has no `crds/` directory and no CRD templates; the upstream tree
`install/kubernetes/cilium/crds/` does not exist for tag `v1.20.4`).
Consequently the chart value `envoyConfig.enabled` — documented as "Enable
CiliumEnvoyConfig CRD" — is a **no-op for CRD installation**.

Forward-fix that worked (preserved on `backup/gateway-forwardfix-20261101`,
commit `840b50bf`): vendor the upstream CRD into
`fluxcd/infrastructure/configs/gateway-api/ciliumenvoyconfigs.yml` and add it
to that kustomization. Verified: after reconcile, the CEC CRD was created and
`CiliumEnvoyConfig/gateway/truenas-external` + `Service/truenas-external`
(VIP `10.25.25.12`) came up.

To retry the migration, cherry-pick / restore `840b50bf` on top of `91480c66`
and re-run the verification steps.
