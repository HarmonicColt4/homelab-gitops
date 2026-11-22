# llama.cpp

`llama-server` runs in the `ai` namespace in router mode: models are declared
once in [`models-preset.ini`](../fluxcd/apps/ai/llama.cpp/models-preset.ini) and
served from a single process with `--models-max 1`, so only one model is
resident at a time and switching models unloads the previous one. It is exposed
at <https://llama.teamg.app>.

| Item      | Value                                                                |
| --------- | -------------------------------------------------------------------- |
| Manifests | `fluxcd/apps/ai/llama.cpp/`                                          |
| Image     | `ghcr.io/anbeeld/beellama.cpp:server-cuda13-v0.4.9` (Renovate)       |
| Service   | `ai/llama-cpp`, ClusterIP port `8080`                                |
| Edge      | `ai/llama.cpp` IngressRoute, Traefik `websecure`, `llama.teamg.app`  |
| Config    | ConfigMap `ai/llama-cpp-models-preset` (`models-preset.ini`)         |
| Secret    | Secret `ai/llama-cpp-hf-token` (`HF_TOKEN`, SOPS)                    |
| Storage   | PV/PVC `llama-cpp-models-nvme`, StorageClass `local-nvme`, 200Gi RWO |
| GPU       | `nvidia.com/gpu: 1`, pinned to `beast`                               |
| Strategy  | `Recreate` (the models volume is ReadWriteOnce)                      |

## Router mode

`--models-preset /config/models-preset.ini` declares the available models and
`--models-max 1` keeps a single one resident. Loading a different model unloads
the current one, so the first request after a switch pays the load cost; later
requests hit the resident model.

The `load-on-startup` key in the preset selects the model the router loads when
the process starts. Everything else in the file is per-model tuning — context
size, quantisation, KV-cache type, speculative-decoding drafter — and the
rationale for those choices is recorded as comments next to each key rather than
duplicated here.

## Why local NVMe, not Longhorn

The weights live in `/var/mnt/longhorn/llama-models` on `beast`, exposed through
the static `local-nvme` PV in
[`pv-nvme.yml`](../fluxcd/apps/ai/llama.cpp/pv-nvme.yml). Measured on that node:

| Path                     | Throughput |
| ------------------------ | ---------- |
| Longhorn volume (iSCSI)  | ~277 MB/s  |
| this directory (raw xfs) | ~1.6 GB/s  |

That gap is the difference between a ~60 s and a single-digit-second model
switch. `beast` has a single fully-partitioned NVMe, so the directory sits on
the Longhorn filesystem and bypasses the Longhorn engine entirely; Longhorn
still accounts for the space via `statfs`, so it cannot be overfilled.

The PV is pinned to `beast` with `nodeAffinity`, so the Deployment must stay on
that node. Capacity is bookkeeping only: a directory-backed local volume cannot
be provisioned or controller-expanded, and growing it means raising both the PV
capacity and the PVC request.

## Memory limit

The container limit must exceed model size plus working set — it is 24Gi,
comfortably above the current preset (a 12B Q4_K_M). Below that the cgroup
reclaims the mmap'd GGUF pages and every model switch re-reads the weights from
disk.

## Operating it

- The `local` volume source does **not** create its directory. After a `beast`
  reinstall, recreate `/var/mnt/longhorn/llama-models` before the Deployment can
  schedule, or the pod stays `Pending`.
- Model ids in requests are the section names in `models-preset.ini`
  (`gemma4-12b-q6-mtp`), with the `alias` values as additional names
  (`gemma4-12b-q6`). The `q6` suffix is historical: the preset now loads
  Q4_K_M so Whisper can share the card (see [`whisper.md`](whisper.md)).
- `/v1/models` answers before a model is loaded — it lists presets with
  `status.value` of `unloaded`/`loading`/`loaded`. Do not use it as a readiness
  signal; `/health` only reflects the router process, which is what the
  startup, readiness and liveness probes check.
