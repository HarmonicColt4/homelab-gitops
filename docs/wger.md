# wger

[wger](https://wger.readthedocs.io) (workout, nutrition and weight tracking)
runs on the free hosted instance <https://wger.de> — no self-hosted wger app
in this cluster. The only wger workload is the official
[wger-mcp](https://github.com/wger-project/mcp-server) server in the `ai`
namespace, which exposes the wger REST API as MCP tools for hermes-agent.

| Item      | Value                                                     |
| --------- | --------------------------------------------------------- |
| Backend   | <https://wger.de> (free account, full feature set)        |
| Manifests | `fluxcd/apps/ai/mcp/wger-mcp/`                            |
| Image     | `ghcr.io/wger-project/mcp-server:2.7.1`                   |
| Service   | `ai/wger-mcp`, ClusterIP port `8765`, endpoint `/mcp`     |
| Auth      | `MCP_AUTH=static_token` — single user, no IdP             |
| Secret    | Secret `ai/wger-mcp-config*` (SOPS, `secrets/enc.env`)    |

## Credentials

`secrets/enc.env` (SOPS encrypted) holds two keys:

- `WGER_API_KEY` — the account key from wger.de, *Settings → API key*. It
  acts as a password for the whole account.
- `MCP_STATIC_TOKEN` — shared bearer token for `/mcp` (64 random hex chars).

The `WGER_API_KEY` ships as a placeholder until the wger.de account is
created; set it (and re-encrypt, the token stays untouched):

```sh
sops -d fluxcd/apps/ai/mcp/wger-mcp/secrets/enc.env \
  | sed 's/^WGER_API_KEY=.*/WGER_API_KEY=<your key>/' \
  | sops --encrypt > fluxcd/apps/ai/mcp/wger-mcp/secrets/enc.env
```

## Wiring hermes

Point the MCP client at `http://wger-mcp.ai.svc.cluster.local:8765/mcp` with
header `Authorization: Bearer <MCP_STATIC_TOKEN>`. Every call acts as the
single wger.de account behind `WGER_API_KEY` — rotate the key in wger.de and
re-encrypt the file if you suspect a leak.

## Notes

- wger.de is volunteer-run: no SLA, and the data lives on their servers.
- `MCP_TOOLS` is not set, so the full tool surface is registered (85+ tools,
  ~23k tokens of schema per request). Narrow it with
  `MCP_TOOLS=routines,workout_logs,...` if that is too much for the local
  model.
- If you later want the data on your own box (backups to the same Garage S3
  backend as the other CNPG clusters) or per-user OAuth
  (`MCP_AUTH=wger_oidc`), self-hosting is the upgrade path: the official
  [wger chart](https://github.com/wger-project/helm-charts) renders the full
  stack and supports an external database (`app.django.existingDatabase`)
  pointing at a CNPG cluster.
