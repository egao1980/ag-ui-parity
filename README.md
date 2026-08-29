# ag-ui-parity

Interop canary: **[`ag-ui-protocol`](https://github.com/egao1980/ag-ui-protocol)** + **[`ag-ui-backend-sse`](https://github.com/egao1980/ag-ui-backend-sse)** vs official **Python [`ag-ui-protocol`](https://pypi.org/project/ag-ui-protocol/)** and **Node [`@ag-ui/client`](https://www.npmjs.com/package/@ag-ui/client)** / [`@ag-ui/encoder`](https://www.npmjs.com/package/@ag-ui/encoder).

Lisp owns the harness. Node/Python peers are the SUT. **CI-only — not published to GHCR.**

HTTP client is `http-backend-async` × `event-backend-libuv` (not dexador).

```
SSE JSON  (interop surface)
  Lisp client  →  Lisp server    (in-process + hunchentoot / make-ag-ui-app)
  Lisp client  →  Node server    (@ag-ui/encoder + Express)
  Lisp client  →  Python server  (ag_ui.encoder + Starlette)
  Node client  →  Lisp server    (@ag-ui/client HttpAgent)
  Python client → Lisp server    (official Event models + httpx; no HttpAgent in the Python SDK)

WKT proto  (Lisp-only, in-process framed)
  encode-ag-ui-framed → decode-ag-ui-framed   (serdes :wkt / google.protobuf.Value)
  HTTP proto via Hunchentoot is skip — it writes Clack bodies as strings
```

A pass is GET `AgentCapabilities` (`identity.name` contains `parity`, `transport.streaming`) plus six canned runs keyed by the last user message: `echo`, `tools`, `state`, `reasoning`, `interrupt`, `resume`.

Official `@ag-ui/proto` **Event oneof** binary is **not** in scope — our `application/vnd.ag-ui.event+proto` is JSON-as-WKT, not wire-compatible.

## Run

```bash
cd peers/node && npm install
cd ../python && uv sync
export AG_UI_PARITY_PEERS=1
CL_SOURCE_REGISTRY="/path/to/cl-workspace//:" ros -e '(asdf:test-system "ag-ui-parity")' -q
```

Lisp↔Lisp only:

```bash
export AG_UI_PARITY_PEERS=0
ros -e '(asdf:test-system "ag-ui-parity")' -q
```

## Matrix

See [MATRIX.md](MATRIX.md).

## Env

| Variable | Default | Meaning |
|----------|---------|---------|
| `AG_UI_PARITY_PEERS` | on | `0` skips Node/Python peers |

Tracks [cl-stack#187](https://github.com/egao1980/cl-stack/issues/187).

## License

MIT
