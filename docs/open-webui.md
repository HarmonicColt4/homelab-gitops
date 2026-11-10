# Open WebUI

Open WebUI is deployed from the official Helm chart as a Flux `HelmRelease` in
the `ai` namespace and served at <https://ai.teamg.app>.

| Item        | Value                                                     |
| ----------- | --------------------------------------------------------- |
| Manifests   | `fluxcd/apps/ai/open-webui/`                              |
| HelmRelease | `flux-system/open-webui` (targets namespace `ai`)         |
| Chart / app | `open-webui` 18.0.0 / image tag `0.13.0`                  |
| Service     | `ai/open-webui`, ClusterIP port `80` -> container `8080`  |
| Edge        | `ai/open-webui` IngressRoute, Traefik `websecure`         |
| Storage     | PVC `ai/open-webui`, 10Gi `longhorn`, ReadWriteOnce       |
| Signing key | Secret `ai/open-webui-secrets` (`WEBUI_SECRET_KEY`, SOPS) |
| Database    | SQLite at `/app/backend/data/webui.db` on that PVC        |

## What Git owns, and what the Admin UI owns

Git owns the release, the Service, the storage, the edge route and the session
signing key. **It does not own model providers or model settings** — those are
configured in the Admin UI and persisted in the SQLite database.

This is deliberate, and it has one consequence worth internalising: provider
connections live only on the PVC. Lose the volume and every connection, model
setting and chat is gone. Keep an export outside Git (see
[Backup](#backup-and-restore)).

## First login

1. Open <https://ai.teamg.app>.
2. Sign up. The **first account created becomes the admin**.
3. Immediately restrict signups: **Admin Panel -> Settings -> General ->
   "Enable New Sign Ups" off**.

`WEBUI_SECRET_KEY` is injected from the SOPS secret and never appears in Git.
Rotating it invalidates all existing sessions.

## Adding model providers

Providers are added once, in the UI, and survive restarts and pod reschedules.

**Admin Panel -> Settings -> Connections**

The chart seeds one useless default connection (`https://api.openai.com/v1`
with the placeholder key `0p3n-w3bu!`). Delete it, then add:

| Connection | Base URL                                        | Key                                     |
| ---------- | ----------------------------------------------- | --------------------------------------- |
| llama.cpp  | `http://llama-cpp.ai.svc.cluster.local:8080/v1` | any placeholder, e.g. `sk-local-noauth` |
| OpenRouter | `https://openrouter.ai/api/v1`                  | `sk-or-v1-...`                          |

Notes:

- Use the **in-cluster** llama.cpp URL, not `https://llama.teamg.app/v1`; it
  stays off the public edge and skips a TLS hop.
- llama.cpp ignores the `Authorization` header, so any non-empty placeholder key
  works.
- llama.cpp runs `--models-max 1`. Selecting a model that is not loaded makes
  the server swap an 11-13 GB GGUF, which can take a minute or more. This is why
  `AIOHTTP_CLIENT_TIMEOUT` is set to `900`; do not lower it.
- OpenRouter advertises hundreds of models. Hide the ones you do not want in
  **Admin Panel -> Settings -> Models** (persisted in the database).
- Rate limits, spend caps and provider routing on the OpenRouter side are set in
  the OpenRouter dashboard, not here.

### Why providers are not environment variables

`OPENAI_API_BASE_URLS` and friends are `ConfigVar` (persistent config): they are
read from the environment **only on first launch**, then stored in the database
and ignored on every later start. Adding a provider by editing the HelmRelease
after the first boot therefore has no effect. The recovery options are:

- `RESET_CONFIG_ON_START=true` for one boot, which re-seeds the database from
  the environment (then remove it), or
- deleting the relevant row in the `config` table, or
- `ENABLE_PERSISTENT_CONFIG=false`, which makes the environment authoritative
  permanently and stops **all** Admin UI changes from persisting.

## Storage lifecycle

The PVC is Helm-managed (`persistence.provider: local` in the HelmRelease) and
carries `helm.sh/resource-policy: keep`, so uninstalling the release or pruning
it from Git leaves the data behind.

- The claim name is derived from `fullnameOverride: open-webui`. Changing that
  value (or the release name) makes the chart create a **new, empty** PVC and
  silently orphan all data. Treat it as immutable.
- Deleting the PVC is the only way to start fresh. Back up first.
- SQLite requires a filesystem with working file locking. Longhorn provides
  that; never move this volume to NFS/SMB.

## Backup and restore

1. Include `ai/open-webui` in the Longhorn recurring backup (the same mechanism
   used for the other application volumes) so the volume is recoverable.
2. Additionally keep a portable copy of the settings: the Admin UI exposes a
   config export (`/api/v1/configs/export` on some versions, or
   **Admin Panel -> Settings -> Database -> Export Config**). Store it in your
   password manager or a private location outside Git — it contains connection
   URLs but ideally no plaintext provider keys.
3. Restore order: PVC first, then the HelmRelease. The app reuses the existing
   claim because of the `keep` annotation.

## Upgrades

- Renovate tracks the **chart** version in `helmrelease.yml`. `image.tag` is
  intentionally empty, so the image follows the chart's `appVersion`: one bump
  moves both.
- Migrations run at startup and are gated by `ENABLE_DB_MIGRATIONS=true` and
  `UVICORN_WORKERS=1`. Keep both at one for this single-replica profile.
- `strategy: Recreate` is required: the RWO volume cannot be attached by two
  pods, so a rolling update would deadlock.
- Before a chart bump, check the upstream CHANGELOG for breaking changes and
  take a backup.

## Troubleshooting

| Symptom                                    | Check                                                                                                                                   |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| `503` from Traefik                         | `kubectl -n ai get ingressroute open-webui` and that Service `open-webui` has endpoints                                                 |
| Pod `Pending`, PVC unbound                 | `kubectl -n ai describe pvc open-webui` — Longhorn replica scheduling or disk pressure                                                  |
| Pod restart loop after upgrade             | `kubectl -n ai logs deploy/open-webui --previous`; usually a failed migration                                                           |
| Model list empty                           | Connections in Admin UI, then `kubectl -n ai exec deploy/llama-cpp -- curl -s localhost:8080/v1/models`                                 |
| First message after model switch times out | expected while llama.cpp loads the GGUF; confirm `AIOHTTP_CLIENT_TIMEOUT=900` is set                                                    |
| Chat does not stream                       | WebSocket blocked. Websocket support is enabled with the in-memory manager (`websocket.manager: ""`); Traefik needs no extra annotation |

## Not wired yet

- **mcpproxy-go** (`http://mcpproxy-go.ai.svc.cluster.local:8080`, see
  `fluxcd/apps/ai/mcpproxy-go/`) can be attached as a tool server from
  **Admin Panel -> Settings -> Tools**; it needs the `MCPPROXY_API_KEY` bearer
  token from `fluxcd/apps/ai/mcpproxy-go/secrets/enc.env`.
- **SSO via authentik**: the `authentik` forwardAuth middleware exists in
  `fluxcd/infrastructure/configs/traefik/middlewares/authentik.yml`, but Open
  WebUI has its own user system, so SSO is better configured as OIDC inside the
  app (**Admin Panel -> Settings -> Authentication**) than as a proxy gate. Set
  `WEBUI_URL` correctly first (`ENABLE_OAUTH_PERSISTENT_CONFIG` aside, a wrong
  `WEBUI_URL` breaks OAuth callbacks).
