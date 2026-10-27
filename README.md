# homelab-gitops

Monorepo consolidating the homelab GitOps configuration and Talos Linux node
provisioning that were previously kept in separate repositories
(`gpenda/fluxcd` and `gpenda/talos-linux`).

## Layout

| Path | Description |
| --- | --- |
| [`fluxcd/`](fluxcd) | Flux GitOps configuration for the Talos Kubernetes cluster (`apps`, `infrastructure`, `cluster`). |
| [`talos/`](talos) | Talos Linux machine configuration (extensions, patches, secrets) for the `home` cluster. |
| [`.gitea/`](.gitea) | Gitea Actions workflows and composite actions. |
| [`renovate.json`](renovate.json) | Renovate configuration covering both Flux and Talos dependencies. |
| [`.sops.yaml`](.sops.yaml) | SOPS/age creation rules for `fluxcd/` content. |

## Notes

- Both projects retain their original commit history (imported with `git subtree`).
- The Flux `GitRepository` points at this repository, and the `flux-system`
  Kustomization reconciles from [`fluxcd/cluster`](fluxcd/cluster).
- Talos secrets use the local [`talos/clusters/home/.sops.yaml`](talos/clusters/home/.sops.yaml) rules.
