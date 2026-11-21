# AGENTS.md

This file provides guidance to agents working in this repository.

## What this repo is

GitOps configuration only: no application code, no package manager, no test suite.
"Build" means render manifests; "test" means dry-run apply.

```sh
kustomize build fluxcd/apps/<group>/<app> > /tmp/out.yml
kubectl apply --dry-run=client -f /tmp/out.yml
```

- The `flux` CLI is installed via Homebrew at `/home/linuxbrew/.linuxbrew/bin/flux`, but that directory is **not on the default non-interactive `PATH`** — call the absolute path or prepend it to `PATH`. `kubectl` and the Flux/Kubernetes MCP servers are also available.
- No linter/formatter config exists; match the surrounding YAML style.

## Non-obvious rules

- New YAML files use `.yml`. Four tracked `.yaml` files are legacy — `fluxcd/cluster/flux-system/{kustomization,gotk-components,gotk-sync}.yaml` and `fluxcd/apps/razzia/kustomization.yaml` — do not rename them. `talos/clusters/home/configs/*.yaml` is gitignored `talosctl` output, not repo content.
- `fluxcd/cluster/` must **not** contain a `kustomization.yaml`; Flux auto-generates one from every YAML in that directory. Never commit preview/test manifests there.
- `.flux-preview/` is gitignored; use it for branch-tracking preview GitRepository/Kustomization objects.
- `.roo/` and `.roomodes` are gitignored, so files under `.roo/rules-*/` are local-only and never committed.
- Plaintext secrets are never committed. Secret files (`secrets/enc.env`, `*.enc.yml`, `*.enc.env`) are SOPS-encrypted and consumed by `secretGenerator`/`secretRef`; Flux decrypts with the `sops-age` secret.
- Root `.sops.yaml` is the only SOPS config and uses path-specific `creation_rules`. A new secret path fails with `no matching creation rules` until a rule is added.
- Talos secrets are covered by the same root `.sops.yaml` (`path_regex: ^talos/clusters/home/secrets\.yml$`). `sops` matches the path relative to the config file, so it works from the repo root or from `talos/clusters/home`.
- `configMapGenerator`/`secretGenerator` remap the filename the container expects (`config.yaml=config.yml`, `values.yaml=global-values.yml`) because containers expect `.yaml` while the repo mandates `.yml`.
- HelmReleases live in `flux-system`; workloads live in the app namespace. TrueCharts releases use `valuesFrom` → `global-values` (generated in `fluxcd/apps/truecharts/kustomization.yml`) and `<app>-values`.
- `fluxcd/kustomizeconfig.yml` must be wired via `configurations:` in any kustomization using `valuesFrom`/`secretRef`, or referenced names are not rewritten.
- Renovate tracks Kubernetes images only in `deploy.yml`, `cronjob.yml`, `login-job.yml` and charts in `helmrelease.yml`/`repository.yml`; an image tag in any other filename is invisible. Regex managers additionally track the Talos installer image in `talos/clusters/*/patches/*.yml` and the Terraform version in `terraform/talos-clusters/*/README.md`.
- The Gitea `upgrade-container-image` workflow only fires on PRs touching `**/deploy.yml` or `**/cronjob.yml`.
- PVCs that must survive pruning need `kustomize.toolkit.fluxcd.io/ssa: IfNotPresent`.
- IngressRoutes: Traefik `websecure`, host `<name>.teamg.app`, no `tls:` block (wildcard cert). The name is usually the app (`mealie`, `sonarr`) but is sometimes abbreviated (`git` for Gitea, `nas` for TrueNAS, `ai` for Open WebUI, `id` for Pocket ID).
- Use `strategy: Recreate` for any Deployment mounting a ReadWriteOnce volume (multi-attach deadlock).
- A new app must be listed in its group kustomization (`fluxcd/apps/<group>/kustomization.yml`) and, for a new group, in `fluxcd/apps/kustomization.yml` — an app that is not listed is never reconciled. `fluxcd/apps/razzia` is currently in that state.
- Per-app operational docs live in `docs/<app>.md` and are linked from the README guide list; keep deep operational detail there, not in the README.
- TrueCharts values: fetch upstream before overriding — `.../charts/library/common/values.yaml` and `.../charts/stable/<chart>/values.yaml` from `trueforge-org/truecharts`.

## Talos / Terraform

- Cluster `teamg`: control plane `rpi5`, workers `hedy` and `beast`.
- `patches/common/allow-cp-worker.yml` and `patches/cilium.yml` are control-plane-only — never apply them to a worker.
- Patch order (later wins): `common_patches` → `controlplane_patches` → `<node>.yml`.
- Terraform root module is `terraform/talos-clusters/home`; reusable modules are in `terraform/modules/`. `talos_secrets_file` points at the decrypted, gitignored `secrets.yml` — produce it with `sops -d talos/clusters/home/secrets.enc.yml > talos/clusters/home/secrets.yml`.
- `terraform/talos-clusters/home/terraform.tfvars` selects the node: `node_name`, `machine_type`, `talos_schematic_file` and `disks`. The variable defaults (schematic `nuc11.yml`, node `beast`) are overridden there.
