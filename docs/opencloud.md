# OpenCloud

OpenCloud runs as a single all-in-one container in the `opencloud` namespace and
is exposed at <https://cloud.teamg.app>. It used to run as a TrueNAS app on
`truenas.home.arpa:30259`; this deployment replaced it.

| Item      | Value                                                              |
| --------- | ------------------------------------------------------------------ |
| Manifests | `fluxcd/apps/opencloud/`                                           |
| Image     | `opencloudeu/opencloud-rolling:9.2.0`                              |
| Data      | PVC `opencloud/opencloud-data`, 100Gi on `longhorn`, mounted at `/var/lib/opencloud` |
| Config    | Secret `opencloud/opencloud-config-*`, mounted at `/etc/opencloud` |
| Search    | `apache/tika:3.3.3.1-full` sidecar on `9998`                       |
| Edge      | IngressRoute `opencloud`, Traefik `websecure`, `cloud.teamg.app`   |
| Run as    | uid/gid `568`                                                      |

## Why a plain Deployment

OpenCloud bundles every service (proxy, idm, idp, nats, search, storage-users,
thumbnails, web) into one binary, so a single replica is the whole deployment.
`strategy: Recreate` is required because the data volume is `ReadWriteOnce`.
The upstream community Helm charts are archived and the supported ones are
behind a commercial subscription, so the Deployment is written by hand.

`PROXY_TLS` is `false`: Traefik terminates TLS and the proxy speaks plain HTTP
on `:9200`. The proxy still announces `OC_URL=https://cloud.teamg.app`, which it
also uses as the OIDC issuer, so that request hairpins through Traefik.

## The data volume is not portable

`STORAGE_USERS_DRIVER=posix` keeps file metadata in **extended attributes**
(`user.oc.blobid`, `user.oc.cs.md5`, `user.oc.name`, …) on the stored files, and
the metadata store contains relative symlinks. Anything that copies this volume
must preserve xattrs and links:

```sh
rsync -aHX --numeric-ids /var/lib/opencloud/ <destination>/
```

Never put this data on NFS or SMB — both drop or rewrite `user.*` xattrs and the
file tree becomes unreadable to OpenCloud. That is why the migration to the
cluster copied the dataset onto a Longhorn volume instead of mounting the
TrueNAS share.

## Configuration

`/etc/opencloud` is a Secret (`secrets/opencloud.enc.yml`, `secrets/csp.enc.yml`)
that an initContainer copies into an `emptyDir`, so the app has a writable config
directory without writing into the data volume. Editing the config:

```sh
sops -d fluxcd/apps/opencloud/secrets/opencloud.enc.yml > /tmp/opencloud.yaml
$EDITOR /tmp/opencloud.yaml
sops -e /tmp/opencloud.yaml > fluxcd/apps/opencloud/secrets/opencloud.enc.yml
```

The generator has no `disableNameSuffixHash`, so a config change alters the
Secret name, the pod template, and the pod rolls.

`csp.yaml` is loaded through `PROXY_CSP_CONFIG_FILE_LOCATION` and adds the
origins the web extensions need: `raw.githubusercontent.com/opencloud-eu/awesome-apps/`
and `update.opencloud.eu` for the app catalogue, `embed.diagrams.net` for draw.io
iframes, `tile.openstreetmap.org` for the maps tiles.

## Web extensions

Extensions are static JS bundles served from a filesystem path, set with
`WEB_ASSET_APPS_PATH=/opt/web-extensions`. A sidecar cannot provide them (the
variable is a path, not a URL), so each extension is an initContainer that copies
its release image into an `emptyDir`:

```yaml
- name: extension-unzip
  image: opencloudeu/web-extensions:unzip-2.2.3
  command:
    - /bin/sh
    - -c
    - mkdir -p /extensions/unzip && cp -R /usr/share/nginx/html/apps/unzip/. /extensions/unzip/
```

To update one, bump its tag: the pod template changes, the pod rolls, the files
are re-copied. To add one, copy an initContainer block and add the app id. Note
`cast` ships its payload at `/usr/share/nginx/html/cast`, not under `apps/`.

`external-sites`, `importer` and `maps` accept extra configuration in
`/var/lib/opencloud/config/apps.yaml`; it is unset, which is the same state the
TrueNAS app shipped.

## Full-text search

`SEARCH_EXTRACTOR_TYPE=tika` sends non-plaintext files (PDF, DOCX, …) to the Tika
sidecar, which extracts their text for the search index. Without it, search
covers filenames and metadata only. Tika is stateless and keeps nothing; it is
resource-capped separately because it parses untrusted uploads.

## Admin account

The admin user is `admin`; the password is the one from the TrueNAS deployment,
stored as a hash in `idm/idm.boltdb`. `IDM_ADMIN_PASSWORD` / `admin_password` in
the config only matter when IDM is initialised for the first time, so changing
them here does nothing on an existing installation. Change the password in the
web UI instead.

## Backups

The `longhorn` StorageClass applies the `default` recurring-job group, so the
volume gets a snapshot every 30 minutes (96 retained) and a block backup to
`s3://longhorn@garage/` every 4 hours (42 retained). No per-app job is needed.
The PVC carries `kustomize.toolkit.fluxcd.io/ssa: IfNotPresent` so pruning the
app does not delete the volume.

### Resizing

That same annotation makes Flux **create-only** for the PVC: editing
`storage.yml` to a larger size changes nothing in the cluster. Expand by hand,
then keep `storage.yml` in sync so the next reader sees the truth:

```sh
kubectl -n opencloud patch pvc opencloud-data --type=merge \
  -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'
kubectl -n opencloud get pvc opencloud-data   # capacity follows online
```

Longhorn has `allowVolumeExpansion`, so this completes while the pod runs.

## Verifying

```sh
kubectl -n opencloud get pod,svc,ingressroute
kubectl -n opencloud exec deploy/opencloud -- curl -sf http://127.0.0.1:9200/healthz
kubectl -n opencloud exec deploy/opencloud -- ls /opt/web-extensions
```

Log in at <https://cloud.teamg.app>, then check that a PDF is found by a word
inside it (Tika) and that the extension apps appear in the app menu.

## Migration note

The data was copied from `/mnt/media/opencloud` on TrueNAS with
`rsync -aHX --numeric-ids` through a temporary rsync daemon pod on a 2.5G node.
The TrueNAS app was stopped first, and remains installed but stopped: starting it
again (`midclt call app.start opencloud`) after removing the cluster IngressRoute
is the rollback path. `media/opencloud` still has its daily ZFS snapshots.
