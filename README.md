# homelab-gitops

Monorepo consolidating the homelab GitOps configuration and Talos Linux node
provisioning that were previously kept in separate repositories
(`gpenda/fluxcd` and `gpenda/talos-linux`).

Everything the cluster runs is declared here and reconciled by Flux. There is no
application code, package manager or test suite — "build" means render manifests
and "test" means dry-run apply.

Cluster `teamg`: control plane `rpi5`, workers `hedy` and `beast`, endpoint
`k8s.home.arpa`.

## Layout

| Path                             | Description                                                                                             |
| -------------------------------- | ------------------------------------------------------------------------------------------------------- |
| [`fluxcd/`](fluxcd)              | Flux GitOps configuration: `apps`, `infrastructure` (controllers, configs, iam, monitoring), `cluster`. |
| [`talos/`](talos)                | Talos machine configuration for the `home` cluster (extensions, patches, secrets).                      |
| [`terraform/`](terraform)        | Proxmox VM, Talos schematic and node modules, plus the `talos-clusters/home` root module.               |
| [`docs/`](docs)                  | Per-application operational guides.                                                                     |
| [`.gitea/`](.gitea)              | Gitea Actions workflow and composite action for the container-image upgrade PRs.                        |
| [`renovate.json`](renovate.json) | Renovate configuration covering both Flux and Talos dependencies.                                       |
| [`.sops.yaml`](.sops.yaml)       | SOPS/age creation rules for all encrypted content (`fluxcd/` and `talos/`).                             |
| [`AGENTS.md`](AGENTS.md)         | Working agreements for agents and contributors (validation commands, YAML rules, patch ordering).       |

## Reconciliation

- The Flux `GitRepository` `flux-system` points at this repository
  (`ssh://git@truenas.home.arpa:30009/gpenda/homelab-gitops.git`, branch `main`,
  1h interval), and the `flux-system` Kustomization reconciles from
  [`fluxcd/cluster`](fluxcd/cluster).
- [`apps.yml`](fluxcd/cluster/apps.yml) declares `apps` (path `./fluxcd/apps`)
  and `truecharts-apps` (path `./fluxcd/apps/truecharts`); both depend on
  `infra-configs` and decrypt SOPS secrets with the `sops-age` secret.
- Workloads live in their own namespaces; HelmReleases are created in
  `flux-system` and select the workload namespace with `targetNamespace`.

## Applications

| Group                                  | Contents                                                                         |
| -------------------------------------- | -------------------------------------------------------------------------------- |
| [`ai`](fluxcd/apps/ai)                 | `llama.cpp`, `whisper`, `hermes-agent`, `linkedin-mcp`, `mealie-mcp`, `searxng`, `wger-mcp`. |
| [`comms`](fluxcd/apps/comms)           | `waha` (WhatsApp HTTP API, linked device).                                       |
| `mealie`                               | Mealie recipe manager.                                                           |
| `truenas-auto-update`                  | Scheduled TrueNAS updater, per-host overlays.                                    |
| `unifi-os-server`                      | UniFi OS Server.                                                                 |
| [`truecharts`](fluxcd/apps/truecharts) | TrueCharts HelmReleases (`global-values` plus `<app>-values`).                   |

Application guides live in [`docs/`](docs):
[`hermes-agent.md`](docs/hermes-agent.md),
[`linkedin-mcp.md`](docs/linkedin-mcp.md),
[`llama.cpp.md`](docs/llama.cpp.md),
[`searxng.md`](docs/searxng.md),
[`waha.md`](docs/waha.md),
[`whisper.md`](docs/whisper.md),
[`wger.md`](docs/wger.md).

## Validation

Render a directory and dry-run the result before committing:

```sh
kustomize build fluxcd/apps/<group>/<app> > /tmp/out.yml
kubectl apply --dry-run=client -f /tmp/out.yml
```

## Secrets

- Plaintext secrets are never committed. `secrets/enc.env` is SOPS-encrypted and
  consumed by `secretGenerator`; Flux decrypts with the `sops-age` secret.
- The root [`.sops.yaml`](.sops.yaml) is the only SOPS config and uses
  path-specific `creation_rules`. A new secret path fails with
  `no matching creation rules` until a rule is added.
- Talos secrets are covered by the same file
  (`^talos/clusters/home/secrets\.yml$`). `sops` matches the path relative to
  the config file, so it works from the repo root or from
  `talos/clusters/home`.

## Notes

- Both projects retain their original commit history (imported with `git subtree`).
- [`talos/clusters/home/README.md`](talos/clusters/home/README.md) documents the
  manual `talosctl` patch workflow; [`terraform/`](terraform) drives the same
  cluster from Proxmox. Keep the two in sync when node configuration changes.
- `.flux-preview/` is gitignored and holds branch-tracking preview
  `GitRepository`/`Kustomization` objects.
