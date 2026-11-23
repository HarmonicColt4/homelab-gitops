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
[`time-slicing.yml`](../fluxcd/infrastructure/controllers/nvidia-gpu-operator/time-slicing.yml))
advertises two `nvidia.com/gpu` resources so both pods can schedule, but it is
**time-multiplexing, not memory partitioning**: both pods see the whole card,
there is no per-pod cap, and the first pod to over-allocate wins while the other
gets a CUDA OOM.

The budget that keeps them apart:

| Component                                            | MiB     |
| ---------------------------------------------------- | ------- |
| llama.cpp Gemma 4 12B Q4_K_M @ 131072, expected peak | ~12,275 |
| Whisper large-v3 int8_float16, expected resident     | ~2,970  |
| Remaining margin                                     | ~1,131  |

llama.cpp was downshifted from Q6_K @ 262144 (measured peak 15,713 MiB) to
Q4_K_M @ 131072 for this. The arithmetic and the TODO for re-measurement live
in [`models-preset.ini`](../fluxcd/apps/ai/llama.cpp/models-preset.ini).

The risk is real: a long llama.cpp prefill and a Whisper transcription at the
same time can exceed the card even inside this budget, because neither process
knows the other's allocation. If that happens, the OOM kills whichever process
allocates last. The mitigation is the margin, not the scheduler.

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

## Phone dictation clients

An Android keyboard can use this endpoint as its speech provider, so the
transcript is typed into whatever field has focus (WhatsApp, Telegram, Signal,
SMS) and the message is sent from the app itself. Two clients are known to
work, and both take the same three settings.

| Client | Shape | Install |
| ------ | ----- | ------- |
| [Voice Keyboard](https://github.com/rustemar/voice-keyboard) | IME: a mic key on the keyboard records, then inserts the text, with optional silence auto-stop and "send after a pause" | F-Droid or GitHub Releases |
| [Sasayaki](https://github.com/pluja/sasayaki) | floating bubble over the keyboard, or the mic key of HeliBoard/FlorisBoard | GitHub Releases |

| Setting | Value |
| ------- | ----- |
| API base URL | `https://whisper.teamg.app/v1` |
| Model | `Systran/faster-whisper-large-v3` |
| API key | the `API_KEY` value of this app's secret, see [Rotating the API key](#rotating-the-api-key) |

Rules that cost time when they are missed:

- The base URL is the gateway, never `127.0.0.1` and never a pod address. A
  phone that is told `localhost` calls itself, and `*.svc.cluster.local` does
  not resolve off-cluster at all.
- The key is required on every route, so the client's key field must be filled
  in. A blank key sends no `Authorization` header and gets `403`.
- The client uploads the container its own recorder produces (OGG/Opus on
  Android 10 and later, M4A/AAC below that). Speaches decodes it with PyAV, so
  no `ffmpeg` or format conversion is needed on the phone.
- `Systran/faster-whisper-large-v3` is the only model in `ai/whisper-models`.
  Naming another one returns `404` telling the client to download it first.
- Set the client's language list to the languages actually spoken (here `en`,
  `fr`, `ru`). Auto-detect works, but an explicit language is better on short
  utterances, and none of these clients switches language mid-recording.

Measured 2026-11-24, model warm on the RTX 4080: an 11 s English clip through
`https://whisper.teamg.app` returned `200` in 0.43 s and 0.54 s wall clock,
including the Traefik hop.

### Reaching it from the phone

`whisper.teamg.app` resolves inside the LAN (to the ingress address
`10.25.25.11`) and the name has no public DNS record, so coverage depends on the
network the phone is on:

- Home Wi-Fi: works as-is, no extra record needed.
- Away from home: the phone needs a route to the LAN whose DNS resolves
  `teamg.app` to the internal address. Without that the name does not resolve
  at all. The public address `202.169.209.225` does forward `443` to Traefik and
  serves the wildcard certificate (verified with `curl --resolve`), so a
  `whisper.teamg.app` A record at Cloudflare is the single change that makes the
  endpoint reachable from any network.

To check the phone side, open `https://whisper.teamg.app/health` in its
browser. A `403` means routing and the certificate are fine and only the key is
missing, which is the expected answer from a network that can reach the
service.

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

[`config.yml`](../fluxcd/apps/ai/hermes-agent/config.yml) sets
`stt.provider: openai` with the in-cluster base URL and
`api_key: ${WHISPER_API_KEY}`. The key must be explicit: a private `base_url`
with no `api_key` resolves to the literal placeholder `not-needed`, which a
keyed Speaches rejects with 401. `voice.client_direct: false` forces the
gateway to relay audio, so mobile clients work without reaching the service
directly.
