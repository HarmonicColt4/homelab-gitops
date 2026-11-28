# llama.cpp

`llama-server` runs in the `ai` namespace in router mode: models are declared
once in [`models-preset.ini`](models-preset.ini) and
served from a single process. `--models-max 2` lets the chat model and the
embedding model stay resident together. It is exposed at
<https://llama.teamg.app>.

| Item      | Value                                                                |
| --------- | -------------------------------------------------------------------- |
| Manifests | `fluxcd/apps/ai/llama.cpp/`                                          |
| Image     | `ghcr.io/anbeeld/beellama.cpp:server-cuda13-v0.5.0` (Renovate)       |
| Service   | `ai/llama-cpp`, ClusterIP port `8080`                                |
| Edge      | `ai/llama.cpp` IngressRoute, Traefik `websecure`, `llama.teamg.app`  |
| Config    | ConfigMap `ai/llama-cpp-models-preset` (`models-preset.ini`)         |
| Secret    | Secret `ai/llama-cpp-hf-token` (`HF_TOKEN`, SOPS)                    |
| Storage   | PV/PVC `llama-cpp-models-nvme`, StorageClass `local-nvme`, 200Gi RWO |
| GPU       | `nvidia.com/gpu: 1`, pinned to `beast`                               |
| Strategy  | `Recreate` (the models volume is ReadWriteOnce)                      |

## Router mode

`--models-preset /config/models-preset.ini` declares the available models and
`--models-max 2` keeps two resident: `gemma4-12b-mtp` for chat/completions and
`bge-m3` for embeddings. A request for a third model would evict the
least-recently-used one; nothing in the stack does that today.

The `load-on-startup` key in each model section makes the router load both at
startup. Everything else in the file is per-model tuning — context size,
quantisation, KV-cache type, speculative-decoding drafter, pooling — and the
rationale for those choices is recorded as comments next to each key rather than
duplicated here.

## Why local NVMe, not Longhorn

The weights live in `/var/mnt/longhorn/llama-models` on `beast`, exposed through
the static `local-nvme` PV in
[`pv-nvme.yml`](pv-nvme.yml). Measured on that node:

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

## Embedding model

`bge-m3` is the dense embedding model used by Paperless-ngx. The preset uses
`Q8_0` (`smarttasks/bge-m3-GGUF`, ~605 MiB). Q5_K_M would save only ~166 MiB and
this workload does not hit Gemma's worst-case prefill peak; Q8_0 keeps a mean
cosine of ~0.9995 against F16, versus ~0.992 for Q5_K_M.

Required preset keys:

```ini
[bge-m3]
hf               = smarttasks/bge-m3-GGUF
hff              = bge-m3-Q8_0.gguf
embeddings       = true
pooling          = cls
ctx-size         = 8192
batch-size       = 2048
ubatch-size      = 2048
flash-attn       = off
n-gpu-layers     = 99
load-on-startup  = 1
```

- `pooling = cls` matches bge-m3's dense output. Without a pooling type,
  `/v1/embeddings` returns one vector per token and OpenAI clients fail.
- `ubatch-size = 2048` accepts Paperless' 1024-token chunks plus special tokens.
  The `[*]` ubatch of 1024 would reject them.
- `flash-attn = off` because this is an encoder, not a chat model.

Full GPU offload costs ~605 MiB of weights plus the child process' ~328 MiB CUDA
context. That leaves roughly 0.2–0.6 GiB free at Gemma's worst-case peak, so
this is a tight budget that can approach zero once driver and compute overheads
are counted. Do not add a third model and check `nvidia-smi` after rollout —
see [`whisper.md`](../whisper/README.md) for the co-tenant accounting.

## Memory limit

The container limit must exceed model size plus working set — it is 24Gi,
comfortably above the current preset (a 12B Q4_K_M plus a 0.6B embedding model).
Below that the cgroup reclaims the mmap'd GGUF pages and every model switch
re-reads the weights from disk.

## Operating it

- The `local` volume source does **not** create its directory. After a `beast`
  reinstall, recreate `/var/mnt/longhorn/llama-models` before the Deployment can
  schedule, or the pod stays `Pending`.
- Model ids in requests are the section names in `models-preset.ini`:
  `gemma4-12b-mtp` for chat and `bge-m3` for embeddings. There are no aliases,
  so use those exact ids. The historical `q6` suffix is gone: the chat preset
  loads Q4_K_M so Whisper can share the card (see [`whisper.md`](../whisper/README.md)).
  Paperless-ngx uses both ids for suggestions and RAG (see
  [`paperless-ngx.md`](../../truecharts/paperless-ngx/README.md)).
- `/v1/models` answers before a model is loaded — it lists presets with
  `status.value` of `unloaded`/`loading`/`loaded`. Do not use it as a readiness
  signal; `/health` only reflects the router process, which is what the
  startup, readiness and liveness probes check.
