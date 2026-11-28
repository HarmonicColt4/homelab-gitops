# Calibre-Web NextGen

Calibre-Web NextGen (CWNG) runs as a single container in the `calibre-web`
namespace and is exposed at <https://books.teamg.app>. It is the community
fork of Calibre-Web-Automated, `ghcr.io/new-usemame/calibre-web-nextgen`:
same data format as CWA, a faster release cadence, and a `/health` endpoint
that also reports the ingest and metadata-change services.

| Item      | Value                                                                        |
| --------- | ---------------------------------------------------------------------------- |
| Manifests | `fluxcd/apps/calibre-web/`                                                   |
| Image     | `ghcr.io/new-usemame/calibre-web-nextgen:v4.1.74`                            |
| Config    | PVC `calibre-web/calibre-web-config`, 1Gi on `longhorn`, mounted at `/config` |
| Library   | NFS `truenas.home.arpa:/mnt/media/books/library`, mounted at `/calibre-library` |
| Ingest    | PVC `calibre-web/calibre-web-ingest`, 1Gi on `longhorn`, mounted at `/cwa-book-ingest` |
| Edge      | IngressRoute `calibre-web`, Traefik `websecure`, `books.teamg.app`           |
| Run as    | uid/gid `568` (the TrueNAS `apps` user)                                      |

## Why a plain Deployment

The TrueCharts `calibre-web` chart wraps the *stock* Calibre-Web image; CWNG
is a fork image, and both image-update mechanisms in this repo only look at
`deploy.yml`: Renovate (kubernetes manager) and the Gitea
`upgrade-container-image` workflow. A tag pinned in a HelmRelease's values
would be invisible to both, so the deployment is written by hand instead.
Do not also create a TrueCharts `calibre-web` release: it would deploy a
second instance into this namespace and collide.

## The library stays on TrueNAS

The Calibre library is not copied to the cluster; the pod mounts
`/mnt/media/books/library` over NFS (the share exports `/mnt/media/books`).
Two settings in `deploy.yml` follow from that:

- `NETWORK_SHARE_MODE=true` — the documented configuration for NFS/SMB
  libraries. It disables SQLite WAL mode (NFS does not support the shared
  memory it needs; without this you get `database is locked`), skips the
  recursive startup chown (slow on NFS, and unnecessary here), and switches
  the ingest watcher from inotify to polling (inotify events are unreliable
  on NFS client mounts). Books dropped in ingest appear seconds later.
- `PUID`/`PGID` are `568`, the uid/gid of TrueNAS' unprivileged `apps` user,
  which owns every file in the library. The container must run as that user
  to write `metadata.db` and create book folders; the stock default of `1000`
  would be locked out by the 0755 directories.

The older library at `/mnt/media/books/Library` (last touched May 2025) is
not mounted; if it ever gets used again, point the NFS `path` at it instead.

Desktop Calibre on this library is retired, so CWNG keeps one long-lived
SQLite connection and no `DESKTOP_COMPAT_MODE` is set. If desktop Calibre is
revived against this library, add `DESKTOP_COMPAT_MODE=true` alongside
`NETWORK_SHARE_MODE=true` so desktop edits show up without a restart.

If the pod fails to mount the share (`MountVolume` events), add
`mountOptions` to the NFS volume and try `nfsvers=3`, then `nfsvers=4`:

```yaml
nfs:
  server: truenas.home.arpa
  path: /mnt/media/books/library
  mountOptions:
    - nfsvers=3
```

## Ingest

`/cwa-book-ingest` is a drop zone: files placed there are imported and then
**deleted** — never point it at anything that is also used for storage.
From the cluster:

```sh
POD=$(kubectl -n calibre-web get pod -l app=calibre-web \
  -o jsonpath='{.items[0].metadata.name}')
kubectl -n calibre-web cp book.epub "$POD:/cwa-book-ingest/book.epub"
```

Two alternatives: upload from the web UI (needs *Allow Uploads*, below), or
copy a book folder onto the NAS library directly — the metadata-change
service watches `/calibre-library` and imports new books.

## First run

1. Open <https://books.teamg.app> and sign in as `admin` / `admin123`.
2. Change the password (Profile → Account).
3. Admin → Edit Basic Configuration → Feature Configuration: enable
   **Allow Uploads** — metadata fetch and upload need it to write to the
   library.
4. Drop an `.epub` into ingest (or upload one); it appears within seconds.

The existing library's books are already listed on the first page.

## Backups

The `longhorn` StorageClass applies the `default` recurring-job group, so
both PVCs get a snapshot every 30 minutes (96 retained) and a block backup to
`s3://longhorn@garage/` every 4 hours (42 retained). The library itself is on
the `media` pool and covered by its ZFS snapshots. The PVCs carry
`kustomize.toolkit.fluxcd.io/ssa: IfNotPresent`, so pruning the app does not
delete the volumes.

### Resizing

That same annotation makes Flux **create-only** for the PVCs: editing
`storage.yml` to a larger size changes nothing in the cluster. Expand by hand,
then keep `storage.yml` in sync so the next reader sees the truth:

```sh
kubectl -n calibre-web patch pvc calibre-web-config --type=merge \
  -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'
kubectl -n calibre-web get pvc calibre-web-config   # capacity follows online
```

Longhorn has `allowVolumeExpansion`, so this completes while the pod runs.

## Updates

Renovate tracks the image tag in `deploy.yml` and the Gitea
`upgrade-container-image` workflow opens upgrade PRs; CWNG ships frequent
releases, so expect them. Release tags are `v<semver>` (e.g. `v4.1.74`).
The startup probe gates the rollout on `/health`, which also checks the
library database and both background services, so a broken release fails the
pod before it is marked ready.

## Verifying

```sh
kubectl -n calibre-web get pod,svc,ingressroute
kubectl -n calibre-web exec deploy/calibre-web -- curl -sf http://127.0.0.1:8083/health
kubectl -n calibre-web exec deploy/calibre-web -- ls /calibre-library
```

Log in at <https://books.teamg.app> and confirm the existing books are
listed; drop a test `.epub` into ingest and watch it appear.
