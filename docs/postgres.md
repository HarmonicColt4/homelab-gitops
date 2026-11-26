# PostgreSQL (CloudNativePG)

Two CNPG clusters serve the whole cluster. The operator is the upstream
`cloudnative-pg` chart in `cnpg-system`, with the Barman Cloud plugin
(`plugin-barman-cloud`) providing backups to Garage.

| Cluster     | Namespace  | Used by                                            |
| ----------- | ---------- | -------------------------------------------------- |
| `shared-db` | `postgres` | home-assistant, seerr, vaultwarden, paperless-ngx   |
| `immich-cnpg-main` | `immich` | immich only (`vectorchord` image, high WAL churn) |

| Item       | Value                                                                 |
| ---------- | --------------------------------------------------------------------- |
| Manifests  | `fluxcd/apps/truecharts/postgres/`                                     |
| Operator   | `fluxcd/infrastructure/controllers/cnpg/` (`cloudnative-pg` 0.29.2)    |
| Storage    | `longhorn`, 2Gi data + 1Gi WAL per instance, `resizeInUseVolumes` on   |
| HA         | 2 instances, `podAntiAffinityType: required` (one per worker)          |
| Backups    | Garage `s3://shared-db`, 30d retention, daily 00:00 + continuous WAL   |

## Layout

- `cluster.yml` — the `Cluster` itself. Plain text: role passwords come from
  Secrets, so nothing sensitive lives here.
- `roles.yml` — one `DatabaseRole` per app, each with a `passwordSecret`.
- `databases.yml` — one `Database` per app, owned by the matching role. `C`
  collation, which (unlike glibc locales) cannot break when the base image
  ships a newer glibc.
- `objectstore.yml` — the Garage `ObjectStore`. One store serves both archiving
  and recovery.
- `scheduledbackup.yml` — daily base backup.
- `secrets/db-roles.enc.yml`, `secrets/garage.enc.yml` — SOPS-encrypted.
- `recovery/cluster.yml` — **not reconciled** (see below).

`DatabaseRole`/`Database` are declared separately from the `Cluster` so a
rebuilt cluster gets its roles and databases back from Git instead of from a
manual `psql` session. Both use `retain` reclaim policies: deleting a manifest
never drops a role or a database.

## Application connections

Apps connect to `shared-db-rw.postgres.svc.cluster.local:5432`. Each app keeps
its own database name and role, so only host and credentials change when moving
an app onto the shared cluster. Credentials are copied into the app namespace
as a SOPS-encrypted `<app>-db` Secret (a `secretKeyRef` cannot cross
namespaces).

## Backups

The plugin archives WAL continuously and takes a base backup daily at 00:00.
`retentionPolicy: 30d` prunes the object store; old per-app prefixes
(`s3://home-assistant`, `s3://seerr`, `s3://vaultwarden`,
`s3://paperless-ngx`) are **not** pruned automatically and must be removed by
hand once the shared cluster's backups have been verified.

Backup granularity is per cluster, not per database: a point-in-time restore
rolls all four apps back together.

## Migration history

The four small apps were moved off their per-app clusters onto `shared-db` on
2026-11-27, one app per PR, each as a `pg_dump -Fc` / `pg_restore` with the row
counts of every table compared before and after:

| App | Tables | Notes |
| --- | ------ | ----- |
| seerr | 15 | identical |
| vaultwarden | 29 | identical |
| paperless-ngx | 75 | identical |
| home-assistant | 13 | `events` +1: a write landed between the baseline and the shutdown |

`home-assistant` also dropped from 127 MB to ~41 MB, the rest from 17 MB to
16 MB and the two small ones stayed put — the per-app clusters carried a lot of
index bloat that the dump/restore reclaimed.

The old backup chains are still in Garage and are the rollback path for each
app until they are deleted:

| App | Old chain |
| --- | --------- |
| seerr | `s3://seerr/seerr-cnpg-main/` |
| vaultwarden | `s3://vaultwarden/vaultwarden-cnpg-main-r3/` |
| paperless-ngx | `s3://paperless-ngx/paperless-ngx-cnpg-main/` |
| home-assistant | `s3://home-assistant/home-assistant-cnpg-main/` |

`vaultwarden` is the awkward one: the chart's revision scheme left `-r1`,
`-r2` and `-r3` prefixes, and the bare `vaultwarden-cnpg-main/` is a stale
2025 leftover. Only `-r3` holds the data from before the migration.

## Removing an app

Deleting a CNPG `Cluster` **deletes its PVCs**. There is no retain option
([cnpg#8442](https://github.com/cloudnative-pg/cloudnative-pg/issues/8442)), so
the moment a migrated app's old `Cluster` is pruned, the only remaining copy of
its data is the Barman chain in Garage (`s3://<app>/<cluster>/`). Keep that
prefix until the app has been running on `shared-db` for a while; restoring
from it is the rollback path.

The Longhorn volumes behind those PVCs can survive as orphaned `detached`
volumes and need deleting by hand:

```sh
kubectl -n longhorn-system get volumes.longhorn.io \
  -o json | jq -r '.items[] | select(.status.kubernetesStatus.pvcName|test("<cluster>")) | .metadata.name'
```

## Recovering

`recovery/cluster.yml` restores the `shared-db` backup chain into a throwaway
`shared-db-restore` cluster. It reads `serverName: shared-db` and archives its
own WAL under `serverName: shared-db-restore`, so the live cluster and its
backups are untouched.

```sh
kubectl apply -f fluxcd/apps/truecharts/postgres/recovery/cluster.yml
kubectl -n postgres wait --for condition=Ready --timeout=600s cluster shared-db-restore
kubectl -n postgres exec shared-db-restore-1 -c postgres -- psql -U postgres -c '\l'
kubectl -n postgres delete cluster shared-db-restore
```

For a real rebuild, delete the `shared-db` Cluster (PVCs included), copy the
manifest, replace every `shared-db-restore` with `shared-db`, set the archiving
`serverName` back to `shared-db` so the existing backup chain continues, and
apply. Add a `recoveryTarget` (`targetTime`/`targetLSN`) for point-in-time
recovery instead of restoring the latest WAL.

## Adding an app

1. Add a `DatabaseRole` and a `Database` to `roles.yml`/`databases.yml`.
2. Add the password to `secrets/db-roles.enc.yml` (`sops edit`), and a
   `kubernetes.io/basic-auth` Secret with the same name in `postgres`.
3. Add a SOPS-encrypted `<app>-db` Secret in the app's namespace with the host
   and password, and point the app's env at it.

## Notes

- `imageName` is pinned in `cluster.yml` (and mirrored in
  `recovery/cluster.yml`). Renovate tracks it through a `custom.regex` manager
  in `renovate.json`, because the `kubernetes` manager only scans
  `deploy.yml`/`cronjob.yml`/`login-job.yml`. The `standard-trixie` suffix is
  captured as a `compatibility` group, so only same-variant tags are proposed.
  Updates never automerge: a bump rolls the database instances. Removing the
  field falls back to the operator's default image.
- The unused `app` database/role created by `initdb` bootstrap is expected;
  it is not used by any application.
- immich is intentionally separate: it needs the `vectorchord` image and
  generates far more WAL than the other four combined.
