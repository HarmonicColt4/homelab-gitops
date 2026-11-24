# Paperless-ngx

Paperless-ngx runs the TrueCharts `paperless-ngx` chart in the `paperless-ngx`
namespace and is exposed at <https://paperless.teamg.app>. Since app 3.5.1 it
has built-in AI features. This deployment uses `gemma4-12b-mtp` for AI-assisted
suggestions (titles, tags, correspondents, document types, storage paths and
dates) and `bge-m3` for the LLM index, similar-document retrieval and document
chat. Both are served by the in-cluster `llama.cpp` router.

| Item       | Value                                                                     |
| ---------- | ------------------------------------------------------------------------- |
| Manifests  | `fluxcd/apps/truecharts/paperless-ngx/`                                    |
| Chart      | `truecharts/paperless-ngx` 18.6.3 (app 3.5.1)                             |
| Values     | Secret `flux-system/paperless-ngx-values` (SOPS)                           |
| Chat model | Service `ai/llama-cpp`, port `8080`, preset `gemma4-12b-mtp`               |
| Embeddings | Same Service, preset `bge-m3` (`Q8_0`, 1024 dimensions)                   |
| Edge       | IngressRoute `paperless-ngx`, Traefik `websecure`, `paperless.teamg.app`   |

The model server is documented in [`llama.cpp.md`](llama.cpp.md): Gemma 4 12B
Q4_K_M with the MTP speculative-decoding drafter at 131072-token context, plus
`bge-m3` for embeddings. `--models-max 2` keeps both resident.

## AI configuration

The chart has no AI-specific values, so the settings are plain environment
variables on the main container. They live in the SOPS-encrypted Helm values
file under `workload.main.podSpec.containers.main.env`:

```yaml
PAPERLESS_AI_ENABLED: "true"
PAPERLESS_AI_LLM_BACKEND: openai-like
PAPERLESS_AI_LLM_ENDPOINT: http://llama-cpp.ai.svc.cluster.local:8080/v1
PAPERLESS_AI_LLM_MODEL: gemma4-12b-mtp
PAPERLESS_AI_LLM_API_KEY: sk-no-key-required
PAPERLESS_AI_LLM_REQUEST_TIMEOUT: "300"
PAPERLESS_AI_LLM_ALLOW_INTERNAL_ENDPOINTS: "true"
PAPERLESS_AI_LLM_EXTRA_PARAMS: '{"reasoning_effort":"none"}'
PAPERLESS_AI_LLM_EMBEDDING_BACKEND: openai-like
PAPERLESS_AI_LLM_EMBEDDING_ENDPOINT: http://llama-cpp.ai.svc.cluster.local:8080/v1
PAPERLESS_AI_LLM_EMBEDDING_MODEL: bge-m3
PAPERLESS_AI_LLM_EMBEDDING_API_KEY: sk-no-key-required
PAPERLESS_AI_LLM_EMBEDDING_CHUNK_SIZE: "1024"
```

Why these values:

- `openai-like`, not `ollama`: `llama-server` exposes an OpenAI-compatible
  `/v1` API, while the Ollama backend expects Ollama's own API.
- The endpoint is the in-cluster Service, not `llama.teamg.app`: Paperless runs
  inside the cluster, so the extra DNS and TLS hop buys nothing.
- `gemma4-12b-mtp` is the section name in
  [`models-preset.ini`](../fluxcd/apps/ai/llama.cpp/models-preset.ini), and
  therefore the model id in `/v1/models`. There are no aliases; do not use the
  historical `gemma4-12b-q6` name.
- `sk-no-key-required` is a placeholder. `llama-server` is started without
  `--api-key` and ignores `Authorization`; Paperless would fall back to `fake`
  anyway, so this is documentation, not a secret.
- `reasoning_effort: none` turns off Gemma 4's thinking. llama.cpp returns the
  reasoning in `reasoning_content`, but Paperless sends a tool-call request and
  reads only `tool_calls`; leaving thinking on spends tokens before every
  suggestion. This was verified through Paperless's own `AIClient`.
- `PAPERLESS_AI_LLM_CONTEXT_SIZE` is left at its default of 8192. Paperless
  truncates suggestion text to 4000 characters, and 8192 is the prompt budget
  for RAG; the model server itself keeps Gemma's full 131072-token context.
- `bge-m3` is the embedding preset, not a second chat model. It uses
  `pooling = cls` and an 8192-token context; Paperless' 1024-token chunks fit.
  Do not point `PAPERLESS_AI_LLM_MODEL` at it.
- `PAPERLESS_AI_LLM_EMBEDDING_CHUNK_SIZE` 1024 is safe for bge-m3's 8192-token
  context. A smaller embedding model with a 512-token limit would need this
  lowered.
- The 300 s timeout covers a cold model reload. With `--models-max 2` Gemma and
  bge-m3 stay resident together, so embedding requests no longer evict the chat
  model; a request for a third model still would.

`PAPERLESS_AI_LLM_ALLOW_INTERNAL_ENDPOINTS` defaults to `true`, but it is set
explicitly because the endpoint resolves to a ClusterIP. Do not set it to
`false` while the endpoint is in-cluster.

## Enabling the features in the UI

The environment only defines the backend. After the pod rolls, an admin can
choose how suggestions are used under **Settings → Documents**:

- **ML**, **AI**, or both for the default suggestion source.
- Whether suggestions are requested automatically for documents carrying an
  inbox tag.

The **Suggest** button on a document detail page works without further
configuration. AI suggestions are additive; they never disable or replace the
existing classifier.

**Application Configuration overrides environment.** If values were ever saved
under **Settings → Application Configuration**, the database value wins over
the Kubernetes env. Clear or align those fields when changing this file.

## RAG, similar documents and document chat

`PAPERLESS_AI_LLM_EMBEDDING_BACKEND=openai-like` points Paperless at the same
`llama.cpp` Service and the `bge-m3` preset. Once the embedding environment is
live, build the index:

```sh
kubectl -n paperless-ngx exec deploy/paperless-ngx -- \
  python manage.py document_llmindex rebuild
```

The index is refreshed daily by `PAPERLESS_LLM_INDEX_TASK_CRON` (default
`10 2 * * *`). Suggestions are then grounded in similar existing documents, and
the toolbar chat can answer over a single document or the current view.

Changing the embedding model means rebuilding the index: vectors from different
models are not comparable. Keep the preset id (`bge-m3`) in sync with
`PAPERLESS_AI_LLM_EMBEDDING_MODEL`.

bge-m3 is a dense embedding model; the sparse and ColBERT heads are not used.
The preset must run with `pooling = cls` or `/v1/embeddings` returns one vector
per token and Paperless fails.

## Verifying

Both models should be `loaded` and reachable from Paperless:

```sh
kubectl -n ai exec deploy/llama.cpp -- curl -s localhost:8080/v1/models \
  | jq -r '.data[] | "\(.id) \(.status.value)"'
# gemma4-12b-mtp loaded
# bge-m3 loaded

kubectl -n paperless-ngx exec deploy/paperless-ngx -- \
  curl -s http://llama-cpp.ai.svc.cluster.local:8080/health
```

Check the embedding endpoint returns one 1024-dimension vector:

```sh
kubectl -n ai exec deploy/llama.cpp -- curl -s \
  http://127.0.0.1:8080/v1/embeddings \
  -H 'Content-Type: application/json' \
  -d '{"model":"bge-m3","input":["bonjour le monde"]}' \
  | jq '.data[0].embedding | length'
# 1024
```

Run one real suggestion through Paperless's AI client (the subprocess inherits
the Deployment's environment):

```sh
kubectl -n paperless-ngx exec deploy/paperless-ngx -- sh -c '
  cd /usr/src/paperless/src &&
  python manage.py shell -c "
from paperless_ai.client import AIClient
print(AIClient().run_llm_query(
    \"Document text: Invoice from ACME for car insurance, dated 2026-01-02.\"
))
"'
```

A healthy result is a classification dictionary with a `title`, `tags`,
`correspondents`, `document_types`, `storage_paths` and `dates`, not a text
answer. A timeout usually means the model was swapped out and is reloading.

## Caveats

- **One request per model at a time.** Both presets run `parallel = 1`, so
  suggestions serialize against each other and embedding requests serialize
  against each other. The two models are separate processes, so an embedding
  request does not wait behind a Gemma suggestion.
- **Tight VRAM budget.** Gemma at 131072, Whisper and bge-m3 Q8_0 leave roughly
  0.2–0.6 GiB free at Gemma's worst-case peak, and can approach zero once driver
  and compute overheads are counted. Do not add a third model to the router and
  check `nvidia-smi` after rollout.
- **Cold starts.** `load-on-startup = 1` keeps both models resident, but a
  request for a third model can evict the least-recently-used one. The first
  request after that waits for the reload.
- **Privacy.** Enabling AI sends OCR text to the configured backend. Here that
  backend is in-cluster; no document content leaves the cluster. Document text
  is still treated as untrusted input, and Paperless's system prompt tells the
  model not to follow instructions embedded in it.
- **Environment vs database.** A value saved in Application Configuration
  silently wins over the SOPS env. If AI behaves differently from this file,
  check the UI first.
