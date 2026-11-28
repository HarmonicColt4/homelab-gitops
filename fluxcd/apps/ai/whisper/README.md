# Whisper ASR

[Speaches](https://speaches.ai) serves OpenAI-compatible speech-to-text over
faster-whisper/CTranslate2 in the `ai` namespace. It shares the single RTX 4080
with llama.cpp through GPU time-slicing and is the STT backend for the Hermes
gateway. It is published at <https://whisper.teamg.app> behind an API key.

| Item      | Value                                                                           |
| --------- | ------------------------------------------------------------------------------- |
| Manifests | `fluxcd/apps/ai/whisper/`                                                       |
| Image     | `ghcr.io/speaches-ai/speaches:latest-cuda` (floating tag)                       |
| Service   | `ai/whisper`, ClusterIP port `8000`                                             |
| Edge      | `ai/whisper` IngressRoute, Traefik `websecure`, `whisper.teamg.app`             |
| Model     | `Systran/faster-whisper-large-v3`, `int8_float16`, resident (`WHISPER__TTL=-1`) |
| Secret    | Secret `ai/whisper-secret` (`API_KEY`, SOPS)                                    |
| Storage   | PVC `ai/whisper-models`, 10Gi `longhorn`, ReadWriteOnce                         |
| GPU       | `nvidia.com/gpu: 1` (time-sliced), pinned to `beast`                            |
| Strategy  | `Recreate` (the model cache is ReadWriteOnce)                                   |

## Why large-v3, not turbo

The three target languages are English, French and Russian. Whisper large-v3
has a 3.8% WER on Russian versus 6.0% for large-v3-turbo, and the turbo speed
advantage does not matter for short voice notes. `int8_float16` keeps the
resident footprint near 2.9 GB instead of ~4.5 GB for fp16.

## VRAM budget and co-tenancy risk

The RTX 4080 has 16,376 MiB. GPU time-slicing (see
[`time-slicing.yml`](../../../infrastructure/controllers/nvidia-gpu-operator/time-slicing.yml))
advertises two `nvidia.com/gpu` resources so both pods can schedule, but it is
**time-multiplexing, not memory partitioning**: both pods see the whole card,
there is no per-pod cap, and the first pod to over-allocate wins while the other
gets a CUDA OOM.

The budget that keeps them apart:

| Component                                              | MiB     |
| ------------------------------------------------------ | ------- |
| llama.cpp Gemma 4 12B Q4_K_M @ 131072, expected peak   | ~12,275 |
| llama.cpp bge-m3 Q8_0 embedding, full GPU              | ~933    |
| Whisper large-v3 int8_float16, expected resident       | ~2,970  |
| Remaining margin                                       | ~198    |

llama.cpp was downshifted from Q6_K @ 262144 (measured peak 15,713 MiB) to
Q4_K_M @ 131072 for this. The arithmetic and the TODO for re-measurement live
in [`models-preset.ini`](../llama.cpp/models-preset.ini). The
embedding model is required by Paperless-ngx; its preset and pooling setup are
in [`llama.cpp.md`](../llama.cpp/README.md).

That 198 MiB row is the conservative arithmetic. On 2026-11-25 the card
reported 2,602 MiB free with Gemma loaded and a CPU-only bge-m3 test instance
resident; moving that instance to the Q8_0 weights adds roughly 605 MiB, so the
practical peak margin is closer to 0.6 GiB. Treat 0.2–0.6 GiB as the real range;
it can approach zero once driver and compute overheads are counted.

The risk is real: a long llama.cpp prefill, a Whisper transcription and an
embedding request at the same time can exceed the card even inside this budget,
because neither process knows the other's allocation. If that happens, the OOM
kills whichever process allocates last. The mitigation is the margin, not the
scheduler.

## Model installation and cold starts

The model is installed by the `fetch-model` initContainer in `deploy.yml`,
before Speaches starts. It calls `huggingface_hub.snapshot_download()` with no
`allow_patterns`, so the cache receives the CTranslate2 weights **and** the
model card (`README.md`). Speaches reads that card at inference time to
discover the model's languages and task; without it the server raises an
assertion in `stt.py` and every transcription returns 500. The download runs in
an init container that exits non-zero on failure, so a bad install blocks the
pod instead of leaving a half-populated cache behind.

A fresh PVC therefore needs no manual step: create the claim and the first pod
start downloads ~3 GB. Expect the pod to sit in `Init:0/1` for several minutes
on a cold pull (there is no `activeDeadlineSeconds`, so a slow network does not
become a crash loop), then show `Completed` before the server container starts.

A cache created by the previous `postStart` warm-up holds the weights but no
`README.md`. On the first start against such a cache the init container logs
the missing card, deletes `models--Systran--faster-whisper-large-v3/` and
re-downloads once. That is a one-time migration; later starts find the card and
do nothing.

First-message-after-restart latency for a cold load is **unmeasured**. Record
it here once measured; `WHISPER__TTL=-1` keeps the model resident after that
first message.

## Measured numbers

Baseline before the co-tenant (2026-11-22, `nvidia-smi` inside the llama.cpp
pod, Gemma 4 12B Q6_K @ 262144 resident):

| State          | Used       | Free    |
| -------------- | ---------- | ------- |
| llama.cpp idle | 15,833 MiB | 543 MiB |

TODO: after the PR is merged and Flux reconciles, record:

- `nvidia-smi` inside the whisper pod while idle and during a transcription.
- llama.cpp load and peak on a long prompt with the Q4_K_M preset.
- The same two figures with both workloads active.

Replace the estimates in `models-preset.ini` and the table above with those
measurements.

## Adding a client

The API is OpenAI-compatible. Any client that accepts a custom base URL works:

```sh
export OPENAI_BASE_URL=https://whisper.teamg.app/v1
export OPENAI_API_KEY="$(sops --decrypt --input-type dotenv --output-type dotenv \
  fluxcd/apps/ai/whisper/secrets/enc.env | sed -n 's/^API_KEY=//p')"

curl -s -H "Authorization: Bearer $OPENAI_API_KEY" \
  -F file=@clip.wav \
  -F model=Systran/faster-whisper-large-v3 \
  https://whisper.teamg.app/v1/audio/transcriptions
```

In-cluster clients use `http://whisper.ai.svc.cluster.local:8000/v1` and skip
the ingress. Every endpoint, including `/health`, requires the key: Speaches
registers the API key as an app-level FastAPI dependency, so only the
auto-generated `/docs` and `/openapi.json` routes are unauthenticated. The
Kubernetes probes therefore use an `exec` handler that sends
`Authorization: Bearer $API_KEY` (see `deploy.yml`).

## Configuration gotchas

- `whisper.ttl` is a nested field, so the env var is `WHISPER__TTL` (double
  underscore). `STT_MODEL_TTL` is silently ignored and leaves the 300 s default.
- The model is fetched by the `fetch-model` initContainer, not by the server
  process. Keep its image tag and pull policy in sync with the server container:
  the interpreter it runs lives in that image's own venv.

## Rotating the API key

The key is shared by Speaches and Hermes (`WHISPER_API_KEY`). Rotate both in one
change so the gateway does not 401 between reconciles:

```sh
# 1. Generate a new key and re-encrypt the Whisper secret.
NEW_KEY="$(openssl rand -hex 32)"
printf 'API_KEY=%s\n' "$NEW_KEY" > /tmp/whisper.env
sops --encrypt --input-type dotenv --output-type dotenv \
  --filename-override fluxcd/apps/ai/whisper/secrets/enc.env \
  /tmp/whisper.env > fluxcd/apps/ai/whisper/secrets/enc.env

# 2. Update the Hermes copy.
sops --decrypt --input-type dotenv --output-type dotenv \
  fluxcd/apps/ai/hermes-agent/secrets/enc.env > /tmp/hermes.env
sed -i "s/^WHISPER_API_KEY=.*/WHISPER_API_KEY=$NEW_KEY/" /tmp/hermes.env
sops --encrypt --input-type dotenv --output-type dotenv \
  --filename-override fluxcd/apps/ai/hermes-agent/secrets/enc.env \
  /tmp/hermes.env > fluxcd/apps/ai/hermes-agent/secrets/enc.env

rm -f /tmp/whisper.env /tmp/hermes.env
```

Commit, push and let Flux reconcile. Both Deployments are `Recreate`, so the
rotation restarts them; in-flight Hermes sessions are lost.

## Hermes wiring

[`config.yml`](../hermes-agent/config.yml) sets
`stt.provider: openai` with the in-cluster base URL and
`api_key: ${WHISPER_API_KEY}`. The key must be explicit: a private `base_url`
with no `api_key` resolves to the literal placeholder `not-needed`, which a
keyed Speaches rejects with 401. `voice.client_direct: false` forces the
gateway to relay audio, so mobile clients work without reaching the service
directly.
