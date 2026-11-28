# Garage Admin MCP

[`HalmSascha/garage-admin-mcp`](https://github.com/HalmSascha/garage-admin-mcp)
exposes the [Garage](https://garagehq.deuxfleurs.fr/) **Admin API** (port 3903
inside Garage) as MCP tools: cluster status, buckets, access keys and bucket/key
permissions. It is served at <https://garage-mcp.teamg.app/mcp> over
Streamable HTTP. Garage itself is not a Kubernetes app here — it runs on
TrueNAS and is reached at `truenas.home.arpa:30190` for the Admin API
(the S3 API is on `30188` and the web UI on `30186`).

| Item       | Value                                                                            |
| ---------- | -------------------------------------------------------------------------------- |
| Manifests  | `fluxcd/apps/ai/mcp/garage/`                                           |
| Workload   | `Deployment/garage-mcp`, 1 replica, `strategy: Recreate`                         |
| Image      | `ghcr.io/halmsascha/garage-admin-mcp:1.0.0` (Renovate-tracked)                   |
| Service    | `ai/garage-mcp`, ClusterIP port `8000`                                           |
| Edge       | `garage-mcp` IngressRoute, Traefik `websecure`, BasicAuth middleware             |
| Secrets    | `GARAGE_ADMIN_TOKEN` in SOPS `secrets/enc.env`; BasicAuth hash in SOPS `secrets/basic-auth.enc.yml` |
| Tool scope | Read **and write** (`GARAGE_ADMIN_READ_ONLY=false`)                              |
| S3 tools   | Disabled — no `GARAGE_ADMIN_S3_*` variables set                                  |

## Why it looks like this

- **The write tools are enabled.** `GARAGE_ADMIN_READ_ONLY=false` registers
  bucket/key create-update-delete and permission tools in addition to the
  read-only ones. This flag only controls what the server *offers*: the
  `GARAGE_ADMIN_TOKEN` must independently carry the matching Garage scopes, or
  the write calls fail with a Garage-side authorization error.
  `delete_bucket` and `delete_key` require a `confirm_id` that exactly matches
  the target ID, checked locally before any request leaves the pod.
- **There is no client authentication upstream.** The server exposes `/mcp` and
  `/healthz` on `0.0.0.0:8000` with no token check, so the public hostname is
  guarded by a Traefik `BasicAuth` middleware instead. Removing that middleware
  from `ingress-route.yml` would leave a public endpoint with read+write access
  to Garage. The BasicAuth credentials and the Garage admin token are two
  different secrets: the first authenticates the *client*, the second is what
  the pod uses to talk to Garage.
- **A Secret manifest, not `secretGenerator`, holds the BasicAuth hash.**
  Traefik requires the key to be named exactly `users`, which kustomize cannot
  produce from a dotenv file. The env-file generator is used only for
  `GARAGE_ADMIN_TOKEN`.
- **A read-only root filesystem with `/tmp` as an `emptyDir`.** The image is
  Python-based and runs as an unprivileged user; `HOME=/tmp` and
  `PYTHONDONTWRITEBYTECODE=1` keep library scratch files off the read-only root.
- **HTTP probes on `/healthz`.** Unlike FastMCP-only servers, this app serves a
  real plain-text `/healthz` that answers a normal `GET`, so no TCP-probe
  workaround is needed.
- **Pinned image tag.** Renovate's `kubernetes` manager tracks `deploy.yml`, so
  a new upstream release opens a PR that bumps the tag.

## First-time setup

Both secrets are committed as SOPS placeholders (`REPLACE_ME`). Until they are
replaced, Traefik rejects every request and the server cannot talk to Garage.

### 1. Create a scoped Garage admin token

On the TrueNAS host running Garage (or inside its container), create a token
with the scopes matching every registered tool:

```sh
garage admin-token create --scope \
  ListBuckets,GetBucketInfo,ListKeys,GetKeyInfo,GetClusterStatus,\
  GetClusterHealth,GetClusterStatistics,GetClusterLayout,GetNodeInfo,\
  GetNodeStatistics,CreateBucket,UpdateBucket,DeleteBucket,AddBucketAlias,\
  RemoveBucketAlias,CreateKey,UpdateKey,DeleteKey,ImportKey,\
  AllowBucketKey,DenyBucketKey garage-mcp
```

Use a dedicated scoped token, not the master `admin_token` from `garage.toml`.
The token is printed once; copy it before leaving the terminal. Confirm with
`garage admin-token list`.

### 2. Generate a BasicAuth credential

```sh
htpasswd -nB garage-mcp
```

Copy the whole `user:$2y$...` line. The password can be generated with
`openssl rand -base64 24` if you don't want to choose one.

### 3. Fill in the encrypted secrets

```sh
# Replace GARAGE_ADMIN_TOKEN=REPLACE_ME with the token from step 1.
sops fluxcd/apps/ai/mcp/garage/secrets/enc.env

# Replace the users value with the htpasswd line from step 2. Quote it:
#   users: 'garage-mcp:$2y$05$...'
sops fluxcd/apps/ai/mcp/garage/secrets/basic-auth.enc.yml
```

Commit both files. The `secretGenerator` hash changes for the env file, so the
Deployment rolls on its own; the BasicAuth Secret updates in place and Traefik
picks it up without a restart.

Verify:

```sh
curl -i -u 'garage-mcp:<password>' https://garage-mcp.teamg.app/healthz
# Expect: HTTP/2 200 and body "ok"
```

## Connecting a client

MCP clients that support custom headers can send HTTP Basic auth:

```json
{
  "mcpServers": {
    "garage": {
      "type": "streamable-http",
      "url": "https://garage-mcp.teamg.app/mcp",
      "headers": {
        "Authorization": "Basic <base64 of user:password>"
      }
    }
  }
}
```

Generate the header value with:

```sh
printf '%s' 'garage-mcp:<password>' | base64 -w0
```

OpenCode's `remote` server type does not expose arbitrary headers, so this
endpoint is intended for clients that do (or for `curl`/MCP inspector). Keep
the Base64 credential out of committed client configs — it is a password in
reversible encoding.

In-cluster consumers can use
`http://garage-mcp.ai.svc.cluster.local:8000/mcp`, which skips the TLS
hop **and the BasicAuth middleware**. Only trusted in-cluster workloads should
be given that URL. Hermes Agent is not wired to this server at present.

## Upgrades

Renovate tracks the image tag in `deploy.yml`. Merging its PR is the whole
upgrade. The app is stateless — no PVC — so a rollout cannot lose data. The
Garage admin token and BasicAuth hash survive upgrades because they live in
separate Secrets.

## Rollback

```sh
# Pin the previous tag in Git and let Flux reconcile.
flux reconcile kustomization apps --with-source

# Or, for an immediate stopgap that Flux will revert on the next reconcile:
kubectl -n ai set image deploy/garage-mcp \
  garage-mcp=ghcr.io/halmsascha/garage-admin-mcp:<previous-tag>
```

## Troubleshooting

| Symptom                                             | Check                                                                                                              |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `401 Unauthorized` from the public hostname         | Missing/wrong BasicAuth credential, or the `users` Secret still holds `REPLACE_ME`.                                 |
| Traefik `500` on every request                      | The `users` value is not a valid htpasswd line — re-run `htpasswd -nB` and quote the whole value.                    |
| Pod never becomes ready                             | `GARAGE_ADMIN_TOKEN` is still the encrypted placeholder; check the Secret and `kubectl -n ai logs deploy/garage-mcp`. |
| Tools return a Garage authorization error           | The admin token lacks the scopes for the tool being called (especially the write tools). Re-create it with the full scope list. |
| `/healthz` is fine but tools cannot reach Garage    | Wrong `GARAGE_ADMIN_URL` port — the Admin API is `30190`, not the S3 port `30188` or web UI `30186`.                 |
| `404` on `/mcp`                                     | The endpoint is `/mcp`, not `/` or `/sse`.                                                                          |
| Write tools are missing from the tool list          | `GARAGE_ADMIN_READ_ONLY` is not `false`, or the pod is running an older image.                                      |

## Rotation

Edit and save the relevant file with `sops` — it re-encrypts on write and the
`secretGenerator` hash changes, rolling the Deployment for the admin token.
Update every MCP client when rotating the BasicAuth password, and remember that
Base64 is not encryption: treat client configs holding the header as secrets.
