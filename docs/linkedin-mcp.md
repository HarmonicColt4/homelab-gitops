# LinkedIn MCP Server

[`stickerdaniel/linkedin-mcp-server`](https://github.com/stickerdaniel/linkedin-mcp-server)
runs as a plain `Deployment` in the shared `ai` namespace and is served at
<https://linkedin-mcp.teamg.app/mcp> over Streamable HTTP.

| Item      | Value                                                         |
| --------- | ------------------------------------------------------------- |
| Manifests | `fluxcd/apps/ai/linkedin-mcp/`                                |
| Workload  | `Deployment/linkedin-mcp`, 1 replica, pinned to `beast`       |
| Image     | `stickerdaniel/linkedin-mcp-server:4.31.0` (Renovate-tracked) |
| Service   | `ai/linkedin-mcp`, ClusterIP port `8080`                      |
| Edge      | `linkedin-mcp` IngressRoute, Traefik `websecure`              |
| Storage   | PVC `linkedin-mcp-session`, 5Gi `longhorn`, ReadWriteOnce     |
| Session   | `/home/pwuser/.linkedin-mcp` on that PVC, created by hand     |
| Secrets   | `LINKEDIN_MCP_HTTP_TOKEN` in SOPS-encrypted `secrets/enc.env` |

## Why it looks like this

Upstream ships a Docker image whose entrypoint is
`tini -- linkedin-mcp-entrypoint python -m linkedin_mcp_server`. The entrypoint
starts `Xvfb` on `:99` and the server runs a **headed** Chromium against it
(`HEADLESS=false` is baked into the image), because LinkedIn's anti-automation
checks behave differently in real headless mode. That drives most of the
manifest:

- **`nodeSelector: kubernetes.io/hostname: beast`** — a headed Chromium plus an
  X server is far too heavy for the arm64 control plane (`rpi5`) and the
  low-power nodes.
- **`/dev/shm` is a 512Mi memory-backed `emptyDir`** — Kubernetes defaults it to
  64Mi, which a headed Chromium exhausts and reports as renderer crashes.
- **The root filesystem is writable, and `/tmp` is _not_ an `emptyDir`.** The
  image re-runs the Patchright installer on every start to record install
  metadata, and that installer takes a cache lock under `/opt/patchright`
  (chowned to `pwuser` in the image). It also refuses a temp parent that is
  group- or other-writable without the sticky bit — which is exactly what a
  Kubernetes `emptyDir` is (0777, no sticky). Mounting one at `/tmp` fails with
  `Installer temporary roots can be replaced by another account in /tmp`. The
  image's own `/tmp` is 1777 and passes, so it is left alone.
- **`fsGroup: 1000` plus a `fix-volume-ownership` init container** — a Longhorn
  volume arrives owned by `root`. `fsGroup` only sets the _group_, and the
  server `chmod`s its profile root to 0700 on start, which fails with
  `EPERM` for a directory it does not own. The init container runs as root with
  only `CAP_CHOWN` and fixes the owner once; everything below the mount root is
  then created by `pwuser`.
- **`strategy: Recreate`** — the session volume is `ReadWriteOnce`, so a rolling
  update would deadlock on a multi-attach.
- **TCP probes, not HTTP** — FastMCP only answers on `/mcp` and rejects plain
  `GET`s without MCP headers, so an `httpGet` probe reports a false failure.
- **`LINKEDIN_MCP_HTTP_TOKEN` is mandatory from 4.31.0.** The server refuses to
  bind a non-loopback host without a client token and exits before `uvicorn`
  starts, so the TCP probe never passes and the pod crashloops. The token comes
  from the SOPS-encrypted `secrets/enc.env` through a `secretGenerator`, and
  every client must send `Authorization: Bearer <token>`.

`FASTMCP_HTTP_ALLOWED_HOSTS` lists the public name and the in-cluster Service
names. FastMCP answers `421` to any `Host` it was not told to serve; that check
is what stops a website you merely visit from driving this server through your
browser, so it must not be disabled — add names to the list instead.

## First-time sign-in

The server cannot create a LinkedIn session on its own in a container: upstream
skips browser auto-import under Docker and tells you to run `--login` on the
host. The equivalent here is a one-shot Job that mounts the same PVC and serves
the login browser at a token-protected URL.

The Job is **not** in `kustomization.yml` on purpose — Flux must never apply it,
because it would race the Deployment for the `ReadWriteOnce` volume and it needs
a human at a browser.

```bash
# 1. Release the session volume.
kubectl -n ai scale deploy/linkedin-mcp --replicas=0

# 2. Start the login job.
kubectl apply -f fluxcd/apps/ai/linkedin-mcp/bootstrap/login-job.yml
kubectl -n ai wait --for=condition=Ready pod -l job-name=linkedin-mcp-login

# 3. Read the token URL the job prints.
kubectl -n ai logs -f job/linkedin-mcp-login

# 4. In a second terminal, forward the viewer.
kubectl -n ai port-forward job/linkedin-mcp-login 6080:6080
```

Open the **full** URL from step 3 (it carries the access token), sign in, and
let the job exit on its own — it gives up after 30 minutes. `Ctrl+V` pastes
plain ASCII into the login browser, which is what a password manager should
give you.

```bash
# 5. Clean up and bring the server back.
kubectl -n ai delete job linkedin-mcp-login
kubectl -n ai scale deploy/linkedin-mcp --replicas=1
```

Verify with the `get_session_status` tool, or:

```bash
kubectl -n ai logs deploy/linkedin-mcp | grep -i session
```

### When the session expires

LinkedIn invalidates sessions periodically. Tool calls then start returning an
authentication error. Repeat the procedure above; nothing else changes. The
volume keeps the old profile until the new login replaces it.

## Connecting a client

Point an MCP client at the Streamable HTTP endpoint:

```json
{
  "mcpServers": {
    "linkedin": {
      "type": "streamable-http",
      "url": "https://linkedin-mcp.teamg.app/mcp",
      "headers": {
        "Authorization": "Bearer <token>"
      }
    }
  }
}
```

Read the token with:

```bash
sops --decrypt fluxcd/apps/ai/linkedin-mcp/secrets/enc.env | grep LINKEDIN_MCP_HTTP_TOKEN
```

In-cluster consumers should use
`http://linkedin-mcp.ai.svc.cluster.local:8080/mcp` and skip the TLS
hop. Both names are in `FASTMCP_HTTP_ALLOWED_HOSTS`. The token is required on
every transport, in-cluster included.

## Security

**The endpoint requires a bearer token.** Since 4.31.0 the server refuses to
start on a non-loopback host without one, so `LINKEDIN_MCP_HTTP_TOKEN` is not
optional here. The value lives in the SOPS-encrypted
`fluxcd/apps/ai/linkedin-mcp/secrets/enc.env` and reaches the container through
a `secretGenerator`-backed `Secret`. Whoever holds the token can read your
inbox, send messages and send connection requests as you, so treat it as a
credential: keep it out of client configs committed to Git and rotate it if it
leaks.

The route is published on the wildcard `*.teamg.app` certificate like the other
apps. The token is the only control on the endpoint; if that is not enough, add
a Traefik middleware to the IngressRoute — `IPAllowList` for LAN-only access —
before widening exposure. Do not set
`LINKEDIN_MCP_ALLOW_UNAUTHENTICATED_HTTP=true`: it disables the check that
exists to stop exactly this exposure.

To rotate the token, replace the value in `secrets/enc.env` with
`sops fluxcd/apps/ai/linkedin-mcp/secrets/enc.env`, commit, and update every
client. The `secretGenerator` hash changes, so the Deployment rolls on its own.

Also note that LinkedIn's User Agreement prohibits automated access. Accounts
using tools like this can be restricted. Use it sparingly.

## Upgrades

Renovate tracks the image tag through the `kubernetes` manager, whose
`managerFilePatterns` in `renovate.json` already covers `deploy.yml`. A new
upstream release opens a PR that bumps `image:` in
`fluxcd/apps/ai/linkedin-mcp/deploy.yml`; merging it is the whole upgrade.

- Upstream ships frequently and the server tracks LinkedIn's page structure, so
  do not pin an old tag for long — a stale image is the usual cause of tools
  returning empty data.
- `bootstrap/login-job.yml` carries the same tag and is tracked by the same
  manager (`/login-job\.yml$/` in `renovate.json`), so the two never drift.
- The session survives image upgrades: the profile is on the PVC, and the
  container re-derives its runtime profile from the stored cookies on start.

## Rollback

```bash
# Pin the previous tag in Git and let Flux reconcile.
flux reconcile kustomization apps --with-source

# Or, to get the old pod back immediately without touching Git:
kubectl -n ai set image deploy/linkedin-mcp \
  linkedin-mcp=stickerdaniel/linkedin-mcp-server:<previous-tag>
```

Flux reverts the imperative change on the next reconcile, so treat the second
form as a stopgap only.

## Troubleshooting

| Symptom                                                                     | Check                                                                                                                                                                |
| --------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Configuration error: HTTP transport on 0.0.0.0 ... no client token is set` | `LINKEDIN_MCP_HTTP_TOKEN` is missing or empty. Check the `linkedin-mcp-secret` Secret and the `secretKeyRef` in `deploy.yml`.                                        |
| `401 Unauthorized` from the MCP endpoint                                    | The client is not sending `Authorization: Bearer <token>`, or the token is stale. Re-read it from `secrets/enc.env`.                                                 |
| `421 Misdirected Request`                                                   | The `Host` you used is not in `FASTMCP_HTTP_ALLOWED_HOSTS`. Add it rather than removing the check.                                                                   |
| `503` from Traefik                                                          | `kubectl -n ai get ingressroute linkedin-mcp` and that the Service has endpoints.                                                                                    |
| Pod `Pending`                                                               | `beast` must be schedulable and the Longhorn volume attachable. `kubectl -n ai describe pod`.                                                                        |
| `Installer temporary roots can be replaced by another account in /tmp`      | `/tmp` was replaced by an `emptyDir`. Remove that mount; the image's own 1777 `/tmp` is required.                                                                    |
| `Browser installation failed` on a read-only root                           | `readOnlyRootFilesystem` is incompatible with this image. See the note in `deploy.yml`.                                                                              |
| Renderer crashes / blank pages                                              | `/dev/shm` too small. Confirm the `dshm` `emptyDir` is mounted at `/dev/shm`.                                                                                        |
| `[Errno 1] Operation not permitted: '/home/pwuser/.linkedin-mcp'`           | The volume root is not owned by uid 1000. The `fix-volume-ownership` init container did not run or failed; check `kubectl -n ai logs <pod> -c fix-volume-ownership`. |
| Tools return "no valid session"                                             | The session expired. Re-run the login procedure.                                                                                                                     |
| Tools time out on multi-page reads                                          | Raise `TOOL_TIMEOUT` (seconds) or `TIMEOUT` (milliseconds) in `deploy.yml`.                                                                                          |
| `browser is busy`                                                           | Only one process may hold the shared browser. Keep `replicas: 1`.                                                                                                    |
