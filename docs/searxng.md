# SearXNG

SearXNG is deployed as plain Kubernetes manifests in the `ai` namespace and
served at <https://searxng.teamg.app> (LAN/cluster only). It is tuned as a
single-user, JSON-first metasearch backend for LLM tooling such as Open WebUI.

| Item       | Value                                                              |
| ---------- | ------------------------------------------------------------------ |
| Manifests  | `fluxcd/apps/ai/searxng/`                                          |
| Image      | `ghcr.io/searxng/searxng:2026.11.15-2d500cb6b` (Renovate-tracked)  |
| Service    | `ai/searxng`, ClusterIP port `8080`                                |
| Edge       | `ai/searxng` IngressRoute, Traefik `websecure`, `searxng-lan-only` |
| Config     | ConfigMap `ai/searxng-config` (`settings.yml`, `limiter.toml`)     |
| Secret     | Secret `ai/searxng-secret` (`SEARXNG_SECRET`, SOPS)                |
| Scheduling | `kubernetes.io/arch: amd64`                                        |
| Storage    | `emptyDir` for `/var/cache/searxng` and `/tmp` (no PVC)            |

## Why this configuration

The instance is deliberately not a public SearXNG:

- `search.formats: [html, json]` — LLM clients call
  `/search?q=...&format=json`.
- `server.limiter: false` and no Valkey — the inbound limiter is for public
  instances; a single user does not need it and it would add a Redis hop.
- `search.autocomplete: ""` and `favicon_resolver: ""` — no extra upstream
  requests per keystroke or per result.
- `search.suspended_times` and `ban_time_on_fail` are raised so a rate-limited
  or CAPTCHA'd engine is parked for longer instead of being retried every few
  minutes from the same egress IP.
- `outgoing.request_timeout`, `max_request_timeout` and `retries` bound the
  fan-out so one slow engine cannot stall the whole response.
- The Google engines (`google cse`, `google scholar`, `google news`,
  `google videos`) are disabled: they are enabled by default and answer a
  self-hosted instance with CAPTCHAs/429s almost immediately.
- `ahmia` and `torch` are removed from the catalogue: there is no Tor proxy.
- `general.contact_url` is required by the Wikipedia, Wikidata and
  OpenStreetMap engines.

## LLM integration

In-cluster consumers should use the Service directly and skip Traefik:

```
http://searxng.ai.svc.cluster.local:8080/search?q=<query>&format=json
```

For Open WebUI: **Admin Panel -> Settings -> Web Search**, enable Web Search,
set the engine to `searxng`, and set the query URL to the URL above. The
`format=json` parameter is what makes the response machine-readable.

The Traefik route is restricted to private address space by the
`searxng-lan-only` `ipAllowList` middleware. The instance has no
authentication of its own, so do not remove that middleware without adding an
auth layer.

## Renovate

SearXNG publishes date-based tags (`YYYY.M.DD-<sha>`), which Renovate's default
Docker versioning cannot order. `renovate.json` therefore sets
`versioning: "regex:^(?<major>\\d{4})\\.(?<minor>\\d{1,2})\\.(?<patch>\\d{1,2})-[a-f0-9]+$"`
for `ghcr.io/searxng/searxng` (and the Docker Hub mirror). The `kubernetes`
manager already scans `deploy.yml`, so a new tag produces a normal PR.

## Operations

```sh
# Force a reconcile after a Git push
flux reconcile kustomization apps --with-source

# Watch the rollout
kubectl -n ai rollout status deploy/searxng

# Logs
kubectl -n ai logs deploy/searxng -f
```

The Deployment is stateless; the only writable state is the favicon cache in an
`emptyDir`, so a pod restart is always safe.

## Rollback

Flux owns the image tag, so a durable rollback is a Git revert of the tag in
`fluxcd/apps/ai/searxng/deploy.yml` followed by a reconcile. `kubectl rollout
undo` only helps until the next reconcile.

## Secret rotation

`SEARXNG_SECRET` signs session cookies. Rotate it with:

```sh
sops fluxcd/apps/ai/searxng/secrets/enc.env
```

then commit and reconcile. Rotating it invalidates existing browser sessions
but does not affect the JSON API.
