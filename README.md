# homelab-gitops

Monorepo consolidating the homelab GitOps configuration and Talos Linux node
provisioning that were previously kept in separate repositories
(`gpenda/fluxcd` and `gpenda/talos-linux`).

## Layout

| Path                             | Description                                                                                       |
| -------------------------------- | ------------------------------------------------------------------------------------------------- |
| [`fluxcd/`](fluxcd)              | Flux GitOps configuration for the Talos Kubernetes cluster (`apps`, `infrastructure`, `cluster`). |
| [`talos/`](talos)                | Talos Linux machine configuration (extensions, patches, secrets) for the `home` cluster.          |
| [`.gitea/`](.gitea)              | Gitea Actions workflows and composite actions.                                                    |
| [`renovate.json`](renovate.json) | Renovate configuration covering both Flux and Talos dependencies.                                 |
| [`.sops.yaml`](.sops.yaml)       | SOPS/age creation rules for `fluxcd/` content.                                                    |

## Notes

- Both projects retain their original commit history (imported with `git subtree`).
- The Flux `GitRepository` points at this repository, and the `flux-system`
  Kustomization reconciles from [`fluxcd/cluster`](fluxcd/cluster).
- Talos secrets use the local [`talos/clusters/home/.sops.yaml`](talos/clusters/home/.sops.yaml) rules.

## llama.cpp model serving

[`fluxcd/apps/ai/llama.cpp`](fluxcd/apps/ai/llama.cpp) runs `llama-server` in
router mode: models are declared in
[`models-preset.ini`](fluxcd/apps/ai/llama.cpp/models-preset.ini) and served
from a single process with `--models-max 1`, so only one model is resident at a
time and switching models unloads the previous one.

Two things matter for switching latency, both already configured:

- **Model storage is local NVMe, not Longhorn.** The models live in
  `/var/mnt/longhorn/llama-models` on `beast`, exposed through the static
  `local-nvme` PV in [`pv-nvme.yml`](fluxcd/apps/ai/llama.cpp/pv-nvme.yml).
  Reading through the Longhorn engine measured ~277 MB/s; the raw filesystem
  gives ~1.6 GB/s, which is the difference between a ~60 s and a ~6 s model
  switch. `beast` has a single fully-partitioned NVMe, so the directory sits on
  the Longhorn filesystem and bypasses the engine; Longhorn accounts for the
  space via `statfs`.
- **The container memory limit must exceed model size + working set** (24Gi for
  the current 11-13 GB GGUFs). Below that the cgroup reclaims the mmap'd GGUF
  pages and every switch re-reads the weights from disk.

Operational notes:

- The `local` volume source does **not** create its directory. After a `beast`
  reinstall, recreate `/var/mnt/longhorn/llama-models` before the Deployment
  can schedule, or the pod will stay `Pending`.
- The PV is pinned to `beast` via `nodeAffinity`; the Deployment must stay on
  that node.
- Model ids in requests are the section names in `models-preset.ini`
  (`qwen3.8-27b`, `air`), with the `alias` values as additional names.
- `/v1/models` answers before a model is loaded - it lists presets with
  `status.value` of `unloaded`/`loading`/`loaded`. Do not use it as a readiness
  signal; `/health` only reflects the router process.
