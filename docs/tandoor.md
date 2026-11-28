# Tandoor

Tandoor is a self-hosted recipe manager (cookbook, tags, search and shopping
list). It runs the TrueCharts `tandoor-recipes` chart in the `tandoor-recipes`
namespace and is exposed at <https://tandoor.teamg.app>. The database lives on
the shared `shared-db` CNPG cluster (role and database `tandoor-recipes`, see
[postgres.md](postgres.md)); media files live on a Longhorn PVC
(`tandoor-recipes-media`).

| Item       | Value                                                        |
| ---------- | ------------------------------------------------------------ |
| Manifests  | `fluxcd/apps/truecharts/tandoor-recipes/`                    |
| Chart      | `truecharts/tandoor-recipes` 23.0.1 (app 2.7.8)              |
| Values     | Secret `flux-system/tandoor-recipes-values` (SOPS)           |
| Database   | `shared-db` in `postgres`, role + database `tandoor-recipes` |
| Ingress    | `tandoor.teamg.app` → Service `tandoor-recipes:10029`        |

## tandoor-mcp

`tandoor-mcp` (`fluxcd/apps/ai/mcp/tandoor-mcp/`) wraps Tandoor as an MCP
server (`ghcr.io/cliftonz/tandoor-recipes-mcp`): stateless Streamable HTTP on
port 3737, bearer-gated. Cluster-internal only — deliberately no IngressRoute,
because the token grants full access to the account:

| Item       | Value                                                                        |
| ---------- | ---------------------------------------------------------------------------- |
| Manifests  | `fluxcd/apps/ai/mcp/tandoor-mcp/`                                            |
| In-cluster | `http://tandoor-mcp.ai.svc.cluster.local:3737/mcp` + bearer `TANDOOR_MCP_HTTP_TOKEN` |

The consumer is `hermes-agent`: its managed config has a `tandoor` entry
(`Bearer ${TANDOOR_MCP_TOKEN}`), sealed in the hermes-agent secrets
([`docs/hermes-agent.md`](hermes-agent.md) → MCP servers).

## Authentication

Login is Pocket ID OIDC — the values set `SOCIALACCOUNT_ONLY=1`, so the login
page only offers the **Pocket ID** button. The `gpenda` superuser carries the
matching Pocket ID email, so the first OIDC login auto-links to it
(`SOCIALACCOUNT_EMAIL_AUTHENTICATION_AUTO_CONNECT`) and joins the space as
admin (`SOCIAL_DEFAULT_ACCESS`/`SOCIAL_DEFAULT_GROUP`).

| Item       | Value                                                        |
| ---------- | ------------------------------------------------------------ |
| OIDC client| "Tandoor Recipes" in the Pocket ID admin, Restricted, PKCE on |
| Break-glass| Local password login at `/accounts/login/?form=1` (password kept out-of-band) |

The OIDC client credentials live SOPS-encrypted in the values Secret
(`SOCIALACCOUNT_PROVIDERS`). The client is restricted to the same Pocket ID
user group as the other app clients; re-create it there before re-pointing the
values.

## First-time setup

1. Sign in at <https://tandoor.teamg.app> with Pocket ID (passkey).
2. Create an API token under Settings → API and store it in
   `fluxcd/apps/ai/mcp/tandoor-mcp/secrets/enc.env` (`TANDOOR_TOKEN`) with
   `sops edit`. The MCP server picks it up on the next reconcile.
