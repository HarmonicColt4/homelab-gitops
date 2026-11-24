# WAHA — WhatsApp HTTP API

Read/write access to a personal WhatsApp account from inside the cluster, used by
Hermes Agent. It is a **linked device**: WAHA's `gows` engine (whatsmeow in Go)
registers as a second device exactly like WhatsApp Web does. Nothing runs on the
phone and no password is involved.

- Namespace `comms`, image `devlikeapro/waha:gows-2026.10.1` (Renovate tracks the
  `gows-<version>` tag in `deploy.yml`).
- Service `waha.comms.svc.cluster.local:3000`, ClusterIP only. There is no
  IngressRoute and there should not be one: the API can send messages as the
  account holder.
- Session data (`/app/.sessions`, including the device credentials) lives on the
  `waha-sessions` Longhorn PVC, so a pod restart reconnects without a QR scan.
  Media (`/app/.media`) is an emptyDir — it dies with the pod, which is fine for
  text reads; persist it only if media history becomes a requirement.

## Why this engine

`gows` talks the WhatsApp websocket directly. No Chromium, so the pod fits in
1Gi and does not need `--disable-dev-shm-usage` or a browser sandbox. GOWS also
stores chats/contacts/messages by default; the NOWEB engine needs an explicit
`store` block per session before `GET /chats` and `GET /messages` answer
anything, and WEBJS needs a browser.

## Security model

Three credentials, deliberately separate:

| Credential | Where | Purpose |
|---|---|---|
| `WAHA_API_KEY` (sha512 hash) | Secret `waha-secret-*`, from `secrets/enc.env` (SOPS) | Server-side auth. WAHA accepts an `X-Api-Key` whose sha512 matches. |
| plain admin key | `/opt/data/.secrets/waha_api_key.txt` (mode 600) on the Hermes PVC | Session control: create, restart, logout, mint keys. |
| per-session read key | `/opt/data/.secrets/waha_read_key.txt` (mode 600) | Day-to-day reads. `actions: {read: true, send/control/setting/app/delete: false}` — a leaked copy cannot send a message. Verified: `POST /api/sendText` with it returns 403. |

The plain admin key never enters Git. Only its hash is committed, and the hash
cannot be used as an API key.

Mint a read key (idempotent per session) with the admin key:

```sh
curl -s -X POST -H "X-Api-Key: $(cat /opt/data/.secrets/waha_api_key.txt)" \
  -H 'Content-Type: application/json' \
  -d '{"isAdmin":false,"session":"default","isActive":true,
       "actions":{"read":true,"send":false,"control":false,"setting":false,"app":false,"delete":false}}' \
  http://waha.comms.svc.cluster.local:3000/api/keys
```

## Reading messages

```sh
R=$(cat /opt/data/.secrets/waha_read_key.txt)
B=http://waha.comms.svc.cluster.local:3000

curl -s -H "X-Api-Key: $R" "$B/api/default/chats/overview?limit=20"     # name + last message per chat
curl -s -H "X-Api-Key: $R" "$B/api/default/chats?limit=100"             # raw chat list
curl -s -H "X-Api-Key: $R" "$B/api/default/chats/<chatId>/messages?limit=50&downloadMedia=false"
```

`<chatId>` is `<phone>@c.us` for a person and `<id>@g.us` for a group; `all` works
in place of a chat id on GOWS. Message bodies are in `body`; media needs
`downloadMedia=true` (or a second call) because the files land in the ephemeral
media volume. Escape `@` as `%40` in paths that also carry a message id.

`sessions/default?sortBy=...` style parameters are not accepted on
`GET /chats` in this version — it returns `400 Bad Request`; sort client-side
instead.

## Pairing and re-pairing

Create the session once (it persists on the PVC):

```sh
K=$(cat /opt/data/.secrets/waha_api_key.txt)
curl -s -X POST -H "X-Api-Key: $K" -H 'Content-Type: application/json' \
  -d '{"name":"default","start":true}' http://waha.comms.svc.cluster.local:3000/api/sessions
```

Then fetch the QR and scan it from **WhatsApp → Settings → Linked devices → Link
a device**:

```sh
curl -s -H "X-Api-Key: $K" -o qr.png http://waha.comms.svc.cluster.local:3000/api/default/auth/qr
```

`GET /api/{session}/auth/qr` is the working verb here (the documented `POST`
returns 404 in 2026.10.1) and it must run while the status is `SCAN_QR_CODE`,
otherwise it answers `422 Session status is not as expected`.

The QR rotates every ~20-40s and the session drops to `FAILED` if the code sits
unscanned, so pair promptly after `restart`:

```sh
curl -s -X POST -H "X-Api-Key: $K" http://waha.comms.svc.cluster.local:3000/api/sessions/default/restart
```

Success looks like `"status": "WORKING"` and `me.id` set to the account's own
`<number>@c.us`. `FAILED` is not fatal: restart, then fetch a fresh QR. Only
`POST /api/sessions/logout` destroys the pairing.

## Probes and the API-key exclusion

Both spellings of the exclusion variable are set
(`WAHA_API_KEY_EXCLUDE_PATH` and `WHATSAPP_API_KEY_EXCLUDE_PATH` with
`health,ping`). With only the `WAHA_` form the pod's `/health` probe answered
`401` and the Deployment never became Ready — the Service had no endpoints and
every call from inside the cluster looked like a connection refusal. If probes
start failing again, check which name this image honours before changing probe
paths.

`/health` and `/ping` answer without a key by design; every other path needs
`X-Api-Key`.

## History coverage

A linked device only receives the history window WhatsApp chooses to push: here
that included chats back to 2023, but the complete archive stays on the phone.
Everything sent or received from now on is stored.

## Known limits

- WAHA CORE (the free tier) runs one session. A second account needs a second
  deployment or a paid tier.
- The image has no `USER` directive, so the container runs as root; the `comms`
  namespace is labelled `baseline` rather than `restricted` for that reason and
  every capability is dropped. `runAsNonRoot` will break the entrypoint's writes
  under `/app`.
- Re-pairing is required after `logout`, a phone reset, or WhatsApp unlinking the
  device from the phone.
- No MCP wrapper yet. Reads are plain HTTP from the Hermes pod; an MCP server in
  front of these endpoints is the next step if tool-call ergonomics matter more
  than one `curl`.
