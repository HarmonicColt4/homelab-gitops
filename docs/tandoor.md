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

The intended consumer is `hermes-agent`; wire it up the same way as
`WGER_MCP_TOKEN` in the hermes-agent secrets.

## First-time setup

1. Open <https://tandoor.teamg.app> and register an account (the first user
   becomes the admin).
2. Create an API token under Settings → API Tokens and store it in
   `fluxcd/apps/ai/mcp/tandoor-mcp/secrets/enc.env` (`TANDOOR_TOKEN`) with
   `sops edit`. The MCP server picks it up on the next reconcile.
